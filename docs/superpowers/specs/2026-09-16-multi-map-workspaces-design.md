# Multiple downloaded maps and explicit working assignment

Status: implemented locally; validation results are recorded below.

## Implementation notes

- Drift v18 adds account-scoped explicit selection and boundary provenance. Existing
  data is preserved; no map is selected automatically after migration.
- My Maps, the Working on switcher, per-map progress, and download completion use
  explicit selection. Drawings require confirmation before leaving; forms retain
  their existing draft-save-on-back behavior.
- Existing `/map` and `/review` URLs are retained with a no-selection redirect.
  Sketches capture their assignment and review snapshots carry their owner ID.
  Feature links for a different map show an actionable My Maps message instead of
  opening fields under the wrong assignment.
- Forms use one atomic JSON snapshot per assignment, including version history.
  A pending-import marker blocks form editing if configuration promotion fails.
  Legacy shared files remain on disk and require refresh when ownership is unknown.
- Upload progress is keyed by assignment; queued operations retain their original
  owner. Sync reconnects for selection changes. Closed assignments no longer
  redirect the entire app to a blocker.
- Camera position persistence is deferred; opening a map fits its stored boundary.
  Existing local cache/access policies and server permissions are unchanged.
- No connected Android device was available for a physical-device walkthrough.
  Automated widget, repository, migration, and upload tests cover the local flow.


## Decision

Keep many downloaded maps. Let the user explicitly choose one assignment for
Gather Data. Persist that choice across launches. Downloading or refreshing a
map must never silently change the working assignment.

Use “map” in the UI and the existing assignment ID as the internal identity.
Map names, overlapping boundaries, and camera position do not determine ownership.

## Findings in the current implementation

- `assignment_repository.dart` selects the newest `createdAt` as current.
- `shapefile_importer.dart` writes that timestamp during import, including an
  upsert. It uses `boundary.shp`, or a rectangle around imported buildings when
  the boundary file is missing.
- `map_providers.dart` displays features from every assignment, while
  `map_screen.dart` validates a new sketch against the current assignment.
- `new_feature_repository.dart` already accepts an explicit assignment ID.
- Review providers and the upload use case independently look up current.
- Tile download resolves current instead of the assignment being downloaded.
- Remote cache and realtime controllers duplicate newest-assignment SQL.
- The router globally redirects to a blocker when current is closed, which
  would prevent selecting another map.
- Downloaded field requirements and form definitions use shared stores. Merely
  switching the boundary provider would leave another map's forms in effect.
- Home progress currently aggregates features and jobs across assignments.

These are code findings, not confirmation of the data stored on the user's phone.

## User flow

### My Maps

Provide a local downloaded-map list, accessible from Home and the map switcher.
Each row shows name, working-map indicator, local gathering progress, pending
uploads, and closed status. Keep download/import status and offline basemap
availability separate: imported survey data can be usable while tiles are pending
or unavailable. Use existing import identity rather than the display name.

Download maps remains the remote discovery flow. Completion offers **Work on
this map** and **Back to My Maps**; only the first explicitly selects it.

### Gather Data

- No selected map: open My Maps. No downloaded maps: show Download maps.
- Valid selection: resume that map directly.
- Header: **Working on: Cebu ▾**, with a visible study boundary.
- Show editable features only from the selected assignment in the first release.
  The geographic basemap can still show surrounding locations.
- Map panning and GPS recentering do not change assignment.
- Outside-area message: **This building is outside Cebu's study area.** Provide
  **Switch map**. Preserve the drawing until the user chooses what to do.
- Store camera position per assignment if implemented; otherwise fit its boundary
  when opened. Camera state is presentation state only.

### Switching with unfinished work

Clean map: switch immediately. Unsaved geometry: offer **Keep working** or
**Discard drawing and switch**. A form with a supported draft save offers
**Save draft and switch** as well. Failed draft saves keep the current screen.
Do not imply geometry drafts are persisted unless that capability is implemented.

Saved drafts stay under their original feature and assignment. An upload already
started continues for its captured assignment after a switch.

Closed maps remain listed and available for supported read/export actions. Block
their edits at the assignment level, while keeping My Maps accessible. Preserve
the existing rule that submitted status alone is not a hard edit lock.

## State and identity

Introduce `AssignmentSelectionRepository` backed by a small local Drift table:

| Field | Purpose |
| --- | --- |
| `userId` (primary key) | Selection belongs to the signed-in account |
| `assignmentId` (nullable reference) | Last explicitly selected local assignment |
| `selectedAt` | Diagnostic timestamp; never an ownership rule |

Selection must reference a locally available assignment accessible under existing
account/access rules. A local selection does not grant server permissions. Audit
existing account/cache isolation during implementation rather than assuming the
current assignment table supplies a complete authorization model.

On upgrade preserve all assignments, features, drafts, and jobs. Start with no
explicit selection and ask the user to choose on first Gather Data, including
single-map installations. Do not seed the selection from import timestamps.
On sign-out clear in-memory context; on sign-in restore only that account's valid
selection. A missing/unavailable selection returns to My Maps without fallback to
the newest row. Local selection must work offline for locally available data.

### Proposed APIs

```dart
// Repositories
watchDownloadedAssignments();
watchAssignment(String assignmentId);
getAssignment(String assignmentId);
watchSelectedAssignmentId(String userId);
selectAssignment({required String userId, required String assignmentId});

// Riverpod context
selectedAssignmentIdProvider;
selectedAssignmentProvider;
assignmentFeaturesProvider(assignmentId);
assignmentLockProvider(assignmentId);
assignmentProgressProvider(assignmentId);
assignmentReviewProvider(assignmentId);
assignmentFormConfigProvider(assignmentId);
```

Represent selection loading, absent selection, unavailable assignment, and ready
assignment explicitly. Disable writes during unresolved context. Replace the
ambiguous current-assignment APIs after migrating consumers; do not leave a second
newest-import fallback. Any temporary alias must delegate to explicit selection.

## Assignment stays fixed for each operation

At screen/session entry capture `assignmentId`. Prefer assignment-bearing routes
such as `/assignments/:assignmentId/map` and `/assignments/:assignmentId/review`.
Feature routes resolve ownership from the stored feature. A mismatched deep link
must resolve to the feature's owner or show an error, never use the selected map's
boundary or form settings for a different feature.

Each sketch session holds its assignment ID. Finish uses that ID to reload the
boundary and edit eligibility, validate geometry, and persist. A mutation use case
performs the local eligibility and ownership check together with the write in a
transaction; UI checks alone are insufficient. Existing remote checks remain.
Apply the same owner-based validation to reshaping existing features.

Each review snapshot and upload request carries its assignment ID. The upload use
case accepts it explicitly and verifies the review belongs to it before starting.
Every confirmation, enqueue, progress stream, export, and finalization uses that
captured identity, including after asynchronous work or a map switch.

The selected map is a navigation preference. Persisted feature ownership and
queued job ownership are durable facts and never change when selection changes.

## Downloads and form files

Pass the acquired map's `localAssignmentId` through import completion, tile-pack
creation, sidecar refresh, and ready-state counts. Do this even on the
already-downloaded shortcut. Never call `getCurrentAssignment()` in that pipeline.
Reimporting the same identity updates that map; downloading another identity keeps
both maps. Preserve existing local edits according to the importer conflict rules.

Store field requirements and form definitions under assignment-specific paths,
with versioned definitions where supported. Providers key caches by assignment
and config revision; open drafts use their recorded form version where available.
Stage files during acquisition and promote the matching config with a successful
import/refresh; define recovery if file promotion or the database update fails.
A failed download must not change another map's form configuration.

Legacy shared sidecars have uncertain ownership. Copy into an assignment's namespace
only when provenance is demonstrable. Otherwise preserve the legacy file, mark the
assignment configuration as needing refresh, and request a config refresh. Do not
silently attribute that shared configuration to every downloaded map. Explicitly
distinguish an intentionally absent sidecar (bundled default policy) from legacy
configuration whose ownership is unknown before permitting affected form writes.

## Boundaries

Keep each imported boundary separate; combining Cebu and Guadalupe into one allowed
region would still leave new-feature ownership ambiguous. Manual selection is
authoritative even when boundaries overlap.

Record boundary provenance during import: supplied boundary, inferred building
extent, or absent. Explain inferred extents in map details so users understand why
the editable area can be smaller than the named place. Preserve the existing
missing-boundary behavior initially; never describe an absent boundary as verified.
Malformed supplied geometry should produce an import issue rather than silently
claiming that all locations are allowed. Do not broaden this work into a replacement
geometry engine; separately verify the supported polygon types and edge behavior.

## Sync, locks, progress, and navigation

| Concern | Intended scope |
| --- | --- |
| Gathering features, boundary, forms, badges | Screen/session assignment |
| Review, export, upload progress | Explicit review/upload assignment |
| My Maps progress | Each row's assignment |
| Home totals | All locally available maps, labeled “All maps” |
| Global upload queue | All queued maps, each labeled by assignment |
| Outbound background jobs | Job's stored owner; independent of selection |
| Interactive remote cache/realtime | Selected assignment |

On selection change, cancel the old UI subscriptions, attach new assignment
subscriptions, and trigger a delta refresh. Tag async results by assignment or
generation so late results cannot appear as the newly selected map. Existing jobs
continue draining across assignments. Pending local work must remain retryable
without reopening its map.

Remove duplicated newest-assignment SQL in cache/realtime controllers. Replace the
startup-only lock listener with lifecycle-managed assignment subscriptions. Drive
enqueue on submission must receive the assignment that was submitted instead of
re-reading selection. Apply closure restrictions to the targeted assignment route
and mutation; never globally redirect away from My Maps or Download maps.

## Delivery sequence

1. **Explicit context:** schema migration, selection repository, keyed assignment
   queries/providers, operation identity contracts, and migration tests.
2. **Isolation:** migrate download/tiles/config stores, geometry/forms, review,
   uploads/exports, locks, and sync consumers. Remove all newest-import selection.
3. **User flow:** My Maps, selection header, routes, boundary display, dirty-work
   switching, and scoped progress labels.
4. **Release validation:** exercise the complete two-map flow on a device. Ship the
   selector only when consumers above use the same identity contract.

No server schema change is assumed for the selector itself. Verify existing server
authorization and upload contracts during implementation. No data reassignment,
map deletion, combined boundaries, or automatic location-based switching is included.

## Acceptance scenarios

- Import Cebu then Guadalupe; choose Cebu; add a valid Cebu building and verify its
  saved assignment ID, review contents, queued job ownership, and export destination.
- Download or refresh Guadalupe while Cebu is selected; Cebu remains selected;
  downloaded tiles, counts, and sidecars belong to Guadalupe.
- Switch to Guadalupe; observe its own features, boundary, config, progress, and
  locks. Restart offline and retain selection.
- Draw outside Cebu but inside Guadalupe: reject for Cebu; do not silently assign
  to Guadalupe. In overlap, the selected assignment owns the new feature.
- Switch with unsaved geometry/form work; cancellation or failed draft save loses
  nothing. Drafts and edits retain ownership after revisiting.
- Start a Cebu upload then switch maps during confirmation or transfer; all upload
  stages still target Cebu and its progress is labeled accordingly.
- Close Guadalupe remotely; Cebu remains usable and My Maps remains reachable.
  A close arriving during a sketch prevents committing it once locally observed.
- Deliver a delayed Cebu remote/config response after switching: Guadalupe's UI
  remains unaffected. Cebu's stored jobs still retry in the background.
- Upgrade a two-map database: preserve rows and drafts; show the chooser; handle
  unowned legacy sidecars explicitly. Check account change and invalid selection.
- Assert active-session code and sync controllers contain no newest-import lookup;
  test same-name assignments using different IDs and deep links to an inactive map.

Use focused repository/migration and use-case tests for identity and data integrity,
widget tests for switching/blocking, and a device walkthrough for map and offline
behavior. Architecture-only work does not require running application tests.


## Validation results (2026-09-16)

- Full Flutter suite: 933 passed, 2 skipped (`flutter test --concurrency=4`).
- `flutter analyze --no-pub`: no errors; lint diagnostics remain.
- Final Android debug build succeeded (`flutter build apk --debug --no-pub`).
- `git diff --check`: passed.
- Device testing: no Android device/emulator was connected. The APK has not been
  installed on the user's phone or published.
