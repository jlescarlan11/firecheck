# Shapefile Export Validation (Pre-Share Gate)

## User Story

As an Enumerator, I want the app to verify that my shapefiles are complete before allowing me to export and share them, so that I don't deliver a broken or rejected submission to the course coordinator.

## Interpretation

"Upload" in the original story maps to the **Export Shapefile → Share** action. The enumerator exports their collected data as a shapefile ZIP and shares it with the coordinator. Validation must run before the share sheet fires to prevent broken ZIPs from being delivered.

## Out of Scope

- Validating the geometric integrity of features inside the `.shp` file (topology, self-intersections)
- Auto-generating missing `.prj` files (exporter always generates `.prj` from EPSG:32651)
- `.prj` warning + checkbox (`.prj` can never be missing from the export)
- Server-side re-validation

---

## Architecture

A two-phase validation gate is inserted into the existing export pipeline:

```
HomeScreen tap
      │
      ▼
ExportValidating          ← NEW state (spinner, no cancel)
      │
      ├─ fail ──► ExportValidationFailed(errors)   ← NEW state
      │                 │
      │           HomeScreen shows per-layer
      │           error list below tile (persistent,
      │           not a dismissable snackbar)
      │           Auto-resets to ExportIdle.
      │
      ▼ pass
ExportInProgress          (existing)
      │
      ▼
[ShapefileExporter generates ZIP]
      │
      ▼
Post-export sanity check  ← NEW step inside exporter
      │
      ├─ fail ──► ExportFailed("Something went wrong, please try again")
      │
      ▼ pass
ExportDone → share sheet fires  (existing)
```

The existing download-side `ShapefileValidator` (7 rules, `lib/core/sync/shapefile/validation/`) is **not modified**.

---

## New Files

| File | Purpose |
|---|---|
| `lib/core/sync/shapefile/export/shapefile_export_validator.dart` | DB validation logic — pure domain, no UI |
| `lib/core/sync/shapefile/export/export_validation_result.dart` | Result model |

## Modified Files

| File | Change |
|---|---|
| `ShapefileExportNotifier` | Two new states; calls validator before export |
| `ShapefileExporter` | Post-export sanity check on generated ZIP |
| `HomeScreen` | Renders error list when in `ExportValidationFailed` |
| `.arb` l10n files | New validation error message keys |

---

## Components

### `ExportValidationResult`

```dart
class ExportValidationResult {
  final bool isValid;
  final List<ExportLayerError> errors;
}

class ExportLayerError {
  final ExportLayer layer;       // enum: buildings, roads
  final ExportLayerIssue issue;  // enum: emptyLayer, missingRequiredFields
}
```

`ExportLayerError` carries only enums — no strings. The HomeScreen maps `(layer, issue)` pairs to localized strings, keeping `AppLocalizations` out of the core domain layer.

### `ShapefileExportValidator`

Single public method:

```dart
Future<ExportValidationResult> validate(String assignmentId)
```

Two checks per layer type (buildings, roads):

1. **Empty layer** — `COUNT(*) WHERE assignment_id = ? AND type = ?` → 0 = hard block
2. **Missing required fields** — `COUNT(*) WHERE assignment_id = ? AND type = ? AND (feat_id IS NULL OR primary_attr IS NULL)` → any null = hard block

`primary_attr` means `bldg_use` for buildings, `road_type` for roads. The validator maps `ExportLayer → required column` internally.

### `ShapefileExportNotifier` — new states

```
ExportValidating
ExportValidationFailed(List<ExportLayerError> errors)
```

Auto-reset to `ExportIdle` after `ExportValidationFailed`, matching the existing `ExportFailed` pattern.

### Post-export sanity check (inside `ShapefileExporter`)

After `ZipEncoder.encode()` returns, scan the in-memory archive:
- Each expected layer must have `.shp`, `.shx`, `.dbf` entries present
- Each entry must have `bytes.length > 0`
- Failure throws `ExportSanityException` → caught by notifier → `ExportFailed`

---

## Error Messages (l10n)

| Condition | Plain-language message |
|---|---|
| Buildings layer empty | "No buildings recorded. Survey at least one building before exporting." |
| Roads layer empty | "No roads recorded. Survey at least one road before exporting." |
| Buildings have incomplete forms | "Some building entries are missing required fields. Complete all building forms before exporting." |
| Roads have incomplete forms | "Some road entries are missing required fields. Complete all road forms before exporting." |
| Exporter sanity failure | "Export failed. Please try again." |

All validation errors appear as a **persistent inline list below the Export Shapefile tile** — not a dismissable snackbar — so the enumerator can read all issues at once. The tile is greyed out while in `ExportValidationFailed`.

---

## Testing

### `ShapefileExportValidator` unit tests (seeded Drift in-memory DB)

- Buildings layer empty → `isValid: false`, `buildings/emptyLayer` error
- Roads layer empty → `isValid: false`, `roads/emptyLayer` error
- Both layers empty → `isValid: false`, two errors
- Buildings with null `bldg_use` → `isValid: false`, `buildings/missingRequiredFields` error
- Roads with null `road_type` → `isValid: false`, `roads/missingRequiredFields` error
- All layers complete → `isValid: true`, no errors

### `ShapefileExportNotifier` state machine tests (extend existing 6-test file)

- Validation failure → state sequence: `Idle → Validating → ValidationFailed → Idle` (auto-reset)
- Validation pass → proceeds to `ExportInProgress` (existing happy path unchanged)

### `ShapefileExporter` sanity check tests (extend existing exporter tests)

- Archive missing `.shx` entry → throws `ExportSanityException`
- Archive with zero-byte `.dbf` → throws `ExportSanityException`
- Valid archive → no exception

---

## Definition of Done

- All acceptance criteria pass in QA
- Validation logic has unit tests covering empty layers and missing required fields
- State machine tests cover new `ExportValidating` and `ExportValidationFailed` states
- Sanity check tests cover missing and zero-byte archive entries
- Error messages reviewed for clarity
- `flutter analyze` clean
