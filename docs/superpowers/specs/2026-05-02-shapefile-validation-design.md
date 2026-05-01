# Shapefile Integrity Validation at Download Time

**Date:** 2026-05-02
**Status:** Draft, awaiting review
**Author:** John Lester Escarlan (with brainstorming assistance)
**Branch:** 19-as-an-enumerator-i-want-the-app-to-reject-a-broken-input-shapefile-at-download-time-so-that-i-dont-waste-a-day-on-an-unusable-assignment

---

## User Story

> As an Enumerator, I want the app to reject a broken input shapefile at download time, so that I don't waste a day on an unusable assignment.

---

## Background

Enumerators currently discover shapefile problems only after traveling to the field and attempting to use the assignment. By that point, the day's work is lost. The existing `ShapefileValidator` checks file-set completeness, CRS (EPSG:32651), and required DBF column names — but it does not check header integrity, record-count consistency, geometry sanity, or download checksums.

This story expands validation into a graduated rule pipeline and adds the missing checks, a soft-warning path, a retry path for transient download failures, and fire-and-forget logging to Supabase so supervisors can identify and replace broken source files.

---

## Decisions

| Topic | Choice | Rationale |
|---|---|---|
| Architecture | Graduated rule pipeline (Approach B) | Each rule is independently testable with a known-bad fixture, matching the DoD. Adding or removing a rule is a one-line change to the orchestrator list. |
| Validation timing | After download, before Drift transaction (current timing unchanged) | Files are already in RAM after `DriveDownloadComplete`. Moving checks earlier into the download stream adds complexity with no user-visible benefit. |
| Checksum source | Drive REST v3 MD5 from file metadata | Already returned by `googleapis` during the download loop — no extra round-trip. Detects truncated or corrupted downloads. |
| Supervisor notification | Fire-and-forget insert to `validation_failures` Supabase table | No push-notification infrastructure exists. Supabase is the existing backend. Ops/supervisors query the table directly. |
| Notification failure handling | Swallow exception, debug-print only | The enumerator-facing error must never be blocked by a failed report write. |
| Transient vs. fatal error | `isRetryable` flag on `GetMapsError` | Re-uses the existing error state. Transient failures (network drop, timeout) set the flag; validation failures do not — they require supervisor action. |
| Soft-warning UX | Full-screen state with explicit "Continue anyway" / "Cancel" | "Warned but allowed to proceed" implies active acknowledgment, not a passive toast. |
| Missing `.prj` severity | Warning (not fatal) | User story explicitly lists missing `.prj` as a soft-warning case. |

---

## Architecture

### New directory

```
lib/core/sync/shapefile/
  validation/
    shapefile_validation_rule.dart     ← sealed RuleOutcome + abstract rule interface
    validation_report.dart             ← ValidationReport(fatals, warnings, failedRule, checksum)
    rules/
      r1_checksum_rule.dart
      r2_file_set_rule.dart
      r3_header_integrity_rule.dart
      r4_index_consistency_rule.dart
      r5_attribute_integrity_rule.dart
      r6_geometry_sanity_rule.dart
      r7_projection_rule.dart
  shapefile_validator.dart             ← refactored to orchestrate rule list
  shapefile_importer.dart              ← unchanged except ValidationReport on error
```

### Rule interface

```dart
sealed class RuleOutcome {}
class RulePassed extends RuleOutcome {}
class RuleFatal extends RuleOutcome {
  final String ruleName;   // goes to Supabase log, never shown to enumerator
  final String userMessage;
}
class RuleWarning extends RuleOutcome {
  final String userMessage;
}

abstract class ShapefileValidationRule {
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  );
}
```

### Orchestrator (`ShapefileValidator.validate`)

New signature:
```dart
ValidationReport validate(
  Map<String, Uint8List> files,
  Map<String, String> expectedMd5s,
)
```

`dbfFields` is removed from the signature. Validation now runs on raw bytes only, before any parsing step. R5 reads column names directly from the `.dbf` header descriptor records (bytes 32+, 32 bytes each, field name in bytes 0–10). `ShapefileImporter` is updated to call `validator.validate()` before calling `DbfParser.parse()`.

Rules run in order. The first `RuleFatal` stops the pipeline and populates `ValidationReport.fatalRule`. Warnings accumulate. A `ValidationReport` with no fatals and no warnings is clean.

### `DriveDownloadComplete` change

```dart
// Before
DriveDownloadComplete(Map<String, Uint8List> files)

// After
DriveDownloadComplete(
  Map<String, Uint8List> files,
  Map<String, String> expectedMd5s,   // keyed by filename, value is Drive's MD5 hex string
)
```

`GoogleDriveApi` populates `expectedMd5s` from the `md5Checksum` field already present in Drive REST v3 file metadata. No extra network call required.

### New package

```yaml
crypto: ^3.0.0   # for md5.convert(bytes).toString()
```

---

## Validation Rules

Rules run cheap-to-expensive; first fatal stops the pipeline.

### R1 — Checksum (fatal)

For each downloaded file, compute `md5.convert(bytes).toString()` and compare against `expectedMd5s[filename]`. A mismatch means the download was truncated or corrupted in transit.

**User message:** `getMapsChecksumError` → "The map file was damaged during download."

### R2 — File-set completeness (fatal + soft warning)

Layers `boundary`, `buildings`, `roads` must each have `.shp`, `.dbf`, `.shx`, `.prj`. Each file must be non-empty (`bytes.length > 0`). If any required file is missing or empty, return `RuleFatal`.

After confirming all files are present, if the total download size exceeds 100 MB, accumulate a `RuleWarning` and continue (does not stop the pipeline).

**Fatal user message:** `getMapsIncompleteFilesError` → "Map files are missing or incomplete."
**Warning user message:** `getMapsWarningLargeFile` → "This assignment is unusually large and may be slow to load."

### R3 — Header integrity (fatal, per `.shp`)

- Header length ≥ 100 bytes.
- Bytes 0–3 big-endian == 9994 (0x0000270A).
- Declared file length (bytes 24–27 big-endian int32, units: 16-bit words) × 2 == actual byte length.

**User message:** `getMapsHeaderError` → "Map geometry file is corrupted."

### R4 — Index consistency (fatal, per layer)

- `.shx` record count = `(shxFileLength − 100) / 8`.
- `.shp` record count = walk content records from byte 100 (each record has an 8-byte header: 4-byte record number + 4-byte content length in 16-bit words).
- Counts must match.
- Each `.shx` offset (bytes 0–3 of each 8-byte `.shx` record, big-endian int32, in 16-bit words) × 2 must fall within `.shp` byte bounds.

**User message:** `getMapsIndexError` → "Map index is inconsistent with geometry."

### R5 — Attribute integrity (fatal, per `.dbf`)

- Header ≥ 32 bytes.
- Version byte (offset 0) is `0x03` or `0x83`.
- Record count (bytes 4–7, little-endian int32) == `.shp` record count for that layer.
- Required columns present: `buildings.dbf` needs `feat_id`, `bldg_use`, `bldg_type`; `roads.dbf` needs `feat_id`, `road_type`. (Moved from current `ShapefileValidator`.)

**User message:** `getMapsAttributeError` → "Map attribute table is corrupted or mismatched."

### R6 — Geometry sanity (fatal)

- Total feature count across all layers ≥ 1.
- Bounding box of each `.shp` (bytes 36–67: four `double64` little-endian — Xmin, Ymin, Xmax, Ymax) is non-degenerate: not all zeros, Xmax > Xmin, Ymax > Ymin.

**User message:** `getMapsGeometryError` → "Map contains no usable features."

### R7 — Projection (warning / fatal)

- `.prj` absent → `RuleWarning`.
- `.prj` present but does not contain `"32651"` → `RuleFatal`.
- `.prj` present and contains `"32651"` → `RulePassed`. (Existing check, moved here.)

**Fatal user message:** `getMapsCrsError` → "Map uses an unsupported coordinate system."
**Warning user message:** `getMapsWarningMissingPrj` → "Projection file missing — map may not align correctly."

---

## State Machine Changes

### New `GetMapsState` variants

```dart
// Added between DownloadingShapefiles and ImportingShapefiles
ValidatingShapefiles()

// Soft-warning path: holds pending files so import can proceed without re-downloading
ShapefileWarning({
  required List<String> warnings,
  required Map<String, Uint8List> pendingFiles,
  required Map<String, String> expectedMd5s,
})
```

### `GetMapsError` change

```dart
GetMapsError(Failure failure, {bool isRetryable = false})
```

- Transient failures (network drop, timeout mid-download) → `isRetryable: true`.
- Validation failures → `isRetryable: false` (requires supervisor action).

### New notifier methods

- **`acknowledgeWarning()`** — reads `pendingFiles` from current `ShapefileWarning` state and calls internal `_import()`.
- **`retryDownload()`** — re-runs `confirmDownload()` for the previously selected assignment. Only callable when `state is GetMapsError && state.isRetryable`.

### Updated `confirmDownload()` flow

```
storage pre-check
  ↓
state = DownloadingShapefiles
  ↓
driveApi.downloadShapefiles() stream
  ↓ DriveDownloadComplete(files, expectedMd5s)
state = ValidatingShapefiles
  ↓
report = validator.validate(files, expectedMd5s)
  ├─ fatals → unawaited(reporter.log(...))
  │         → state = GetMapsError(ShapefileValidationFailure, isRetryable: false)
  ├─ warnings only → state = ShapefileWarning(warnings, files, expectedMd5s)
  └─ clean  → _import(files)
```

---

## Error Handling & UX

### New l10n keys

```
// Fatal error reasons (shown in GetMapsError view body)
getMapsChecksumError        → "The map file was damaged during download."
getMapsIncompleteFilesError → "Map files are missing or incomplete."
getMapsHeaderError          → "Map geometry file is corrupted."
getMapsIndexError           → "Map index is inconsistent with geometry."
getMapsAttributeError       → "Map attribute table is corrupted or mismatched."
getMapsGeometryError        → "Map contains no usable features."
getMapsCrsError             → "Map uses an unsupported coordinate system."

// Shared footer on every fatal validation error
getMapsContactSupervisor    → "Contact your supervisor to request a corrected file."

// ValidatingShapefiles screen label
getMapsValidating           → "Checking map files…"

// ShapefileWarning screen
getMapsWarningTitle         → "This assignment has minor issues"
getMapsWarningContinue      → "Continue anyway"
getMapsWarningMissingPrj    → "Projection file missing — map may not align correctly."
getMapsWarningLargeFile     → "This assignment is unusually large and may be slow to load."
```

### Fatal validation error screen

Existing `GetMapsError` view. Renders `Failure.message` as the reason and appends `getMapsContactSupervisor` as a static footer. No "Retry" button.

### Soft-warning screen (`ShapefileWarning` state)

Full-screen state (same slot as other full-screen states). Lists each warning. Two buttons: **"Continue anyway"** (`acknowledgeWarning()`) and **"Cancel"** (`reset()`).

### Transient failure screen

`GetMapsError` view with `isRetryable: true`. Renders a **"Retry"** button that calls `retryDownload()`. No "Contact supervisor" footer.

### `ValidatingShapefiles` screen

Existing progress-spinner layout with `getMapsValidating` label. No progress bar — validation is sub-second.

---

## Notification & Logging

### Supabase table

```sql
create table validation_failures (
  id            uuid primary key default gen_random_uuid(),
  assignment_id text        not null,
  enumerator_id text        not null,
  failed_rule   text        not null,
  file_checksum text,
  message       text        not null,
  created_at    timestamptz not null default now()
);
```

Row-level security: enumerators insert only; supervisors/ops select only.

### `ValidationFailureReporter`

```dart
abstract class ValidationFailureReporter {
  Future<void> report({
    required String assignmentId,
    required String enumeratorId,
    required String failedRule,
    required String message,
    String? fileChecksum,
  });
}
```

- `SupabaseValidationFailureReporter` — direct `.from('validation_failures').insert(...)`. Any exception is caught, swallowed, and debug-printed. Never blocks the UI.
- `FakeValidationFailureReporter` — captures calls for test assertions.

Called in `confirmDownload()` via `unawaited(reporter.report(...))` immediately before `state = GetMapsError(...)`.

---

## Testing

### Rule unit tests

One file per rule. Fixtures are constructed in-memory via byte manipulation.

| Test file | Representative cases |
|---|---|
| `r1_checksum_rule_test.dart` | Flip one byte → `RuleFatal`; matching bytes → `RulePassed`. |
| `r2_file_set_rule_test.dart` | Missing file → `RuleFatal`; zero-byte file → `RuleFatal`; all present → `RulePassed`. |
| `r3_header_integrity_rule_test.dart` | Wrong file code → `RuleFatal`; truncated declared length → `RuleFatal`; valid header → `RulePassed`. |
| `r4_index_consistency_rule_test.dart` | Count mismatch → `RuleFatal`; offset out of bounds → `RuleFatal`; consistent → `RulePassed`. |
| `r5_attribute_integrity_rule_test.dart` | Count mismatch → `RuleFatal`; bad version byte → `RuleFatal`; missing column → `RuleFatal`; valid → `RulePassed`. |
| `r6_geometry_sanity_rule_test.dart` | Zero features → `RuleFatal`; all-zero bbox → `RuleFatal`; Xmax == Xmin → `RuleFatal`; valid → `RulePassed`. |
| `r7_projection_rule_test.dart` | Missing `.prj` → `RuleWarning`; wrong CRS → `RuleFatal`; correct CRS → `RulePassed`. |

### Orchestrator tests (`shapefile_validator_test.dart`)

- Fail-fast: R1 fails → R2–R7 never invoked (confirmed via spy).
- Warning accumulation: R1–R6 pass, R7 warns → `ValidationReport` has no fatals, one warning.
- Clean path: all pass → report is clean.

### Notifier integration tests (added to `get_maps_notifier_test.dart`)

Using existing `FakeDriveApi` extended with `expectedMd5s`:
- Fatal validation → state sequence ends at `GetMapsError(isRetryable: false)`.
- Soft warning → state reaches `ShapefileWarning`; `acknowledgeWarning()` proceeds to `ImportingShapefiles`.
- Transient error → `GetMapsError(isRetryable: true)`; `retryDownload()` restarts download.
- `FakeValidationFailureReporter` asserts `report()` called with correct `failedRule` on fatal.

---

## Out of Scope

- Client-side shapefile repair.
- Upstream hardening of the assignment-creation pipeline.
- Offline re-validation of files downloaded before this story ships.
- Widget/screenshot tests for the two new screen states.

---

## Definition of Done

- Validation runs on every shapefile download.
- All acceptance criteria pass in QA, including the transient-failure and soft-warning paths.
- `validation_failures` table is queryable by ops.
- All new l10n keys reviewed.
- Unit tests cover each validation rule with a known-bad in-memory fixture per rule.
