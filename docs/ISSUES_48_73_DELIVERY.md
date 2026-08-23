# Issues 48–73 delivery record

Authoritative source: the GitHub tracker title for each requested number. The
listed issues have empty bodies and no comments, so each title is the complete
acceptance criterion. Numbers 53–62 resolve to already-merged pull requests,
not open issues.

| Issue / criterion | Required observable behavior and boundary case | Implementation | Direct evidence | Status |
|---|---|---|---|---|
| 48 — versioned forms | A draft pins a version; older versions remain readable offline. Unknown versions fail back to legacy rather than corrupting a draft. | Versioned definition store, `submissions.form_version`, payload/server persistence, per-submission provider override. | `form_definition_store_test`, migration and payload tests. | SATISFIED |
| 49 — geometry outbox | Reshape, split, and merge persist their complete local mutation and one replayable job in a transaction. A failed write rolls back. | Drift revision/outbox repository and sync worker route. | `feature_geometry_revisions_test`, `feature_geometry_update_sync_test`. | SATISFIED |
| 50 — geometry conflicts | Optimistic mismatch is flagged and never silently overwrites either side; keep-server and retry-local are explicit resolutions. | Server `ST_Equals` checks; failed revision state; transactional resolution methods including split/merge rollback. | Conflict and resolution repository tests; sync permanent-failure test. | SATISFIED |
| 51 — structured skip logic | Downloaded JSON conditions change visibility without a rebuild; malformed or unknown operators fail closed. | `FormDefinition`, Drive/FTP sidecar acquisition, reactive form evaluation. | `form_definition_test`, acquisition and Drive API suites. | SATISFIED |
| 52 — finalized geometry lock | Completed/demolished, submitted, or remotely closed work cannot enter or persist geometry editing. | Map affordance guards plus server-side finalized/assignment checks. | Map reshape lock tests; migration inspection. | SATISFIED |
| 53–62 — merged tracker artifacts | These numbers are merged PRs rather than open issues; their merged state must remain regression-free. | No duplicate implementation. Existing behavior retained. | GitHub state inspection; full Flutter suite. | NOT_APPLICABLE_WITH_EVIDENCE |
| 63 — split polygons | A building polygon can be split at two non-adjacent vertices; invalid cuts are rejected and both halves sync atomically. | Split action, geometry primitive, local transaction, guarded RPC. | Geometry operation and repository tests. | SATISFIED |
| 64 — edit policy | Published feature-type and field policy enables/disables geometry and individual form controls. | Definition edit policy wired through map and all building/road sections. | Definition policy test and form/widget suite. | SATISFIED |
| 65 — answer/geometry rules | Conditions can combine answers with area, length, vertex count, feature type, and distance to boundary. | Unified evaluation context and reactive geometry signal. | Form-definition and geometry-signal tests. | SATISFIED |
| 66 — merge polygons | Only same-type polygons sharing an edge are candidates; secondary geometry is tombstoned and replayed atomically. | Merge action/primitive, lineage columns, transaction, guarded RPC. | Geometry operation and repository tests. | SATISFIED |
| 67 — snapping | Dragged vertices and inserted midpoints snap to nearby vertices/edges within tolerance, preferring a very close vertex. | Snap primitive integrated into overlay/controller. | Geometry operation plus editor controller/overlay suites. | SATISFIED |
| 68 — undo | Every session move/add/remove remains undoable. | Existing editor operation stack retained for new snapping path. | Full reshape operation/controller/banner suites. | SATISFIED |
| 69 — geometry sections | Section visibility re-evaluates when feature geometry changes. | Geometry stream feeds the same definition conditions used by forms. | Definition geometry rule and notifier/controller suites. | SATISFIED |
| 70 — boundary warning | Polygon and road edits outside the assignment boundary are stopped; distance override never bypasses the boundary. Server repeats the check. | Map save validation and PostGIS `ST_CoveredBy`. | Polygon/sketch/map reshape tests; migration inspection. | SATISFIED |
| 71 — answer-driven appearance | “Does not exist/demolished” changes map appearance and prevents geometry editing. | Derived `demolished` status and gray renderer treatment. | Feature repository and map renderer suites. | SATISFIED |
| 72 — preview | Rules can be exercised interactively before field use, showing visible/hidden targets and constraints. | Routed preview screen with answer/area controls. | `form_preview_screen_test`. | SATISFIED |
| 73 — shared constraints | One definition supplies field hints, client Done eligibility, preview results, and server validation; unknown versions are rejected. | Constraint hints/validation and version-aware upload wrapper. | Definition/hint/payload tests; migration inspection. | SATISFIED |

## Change-set accounting

| Change unit | Provenance | Contract/boundaries reviewed | Risk | Disposition |
|---|---|---|---|---|
| Form definition model, cache, providers, preview, assets | 48, 51, 64, 65, 69, 72, 73 | Drive/FTP acquisition, old-draft lookup, form sections, Done path, router/home | Medium | REVIEWED_AFTER_FIX |
| Drift schema/generated model/payload | 48, 49, 50, 63, 66 | v7/v12 partial migrations, v14 upgrade, repositories, sync worker | High | REVIEWED_AFTER_FIX |
| Geometry primitives/editor/actions/renderer | 52, 63, 66–71 | Polygon validity, snapping tolerance, boundary, locks, renderer, undo | High | REVIEWED_AFTER_FIX |
| Supabase migration and RPC routing | 48–50, 52, 63, 66, 70, 73 | Auth membership, RLS/grants, idempotency, row locks, optimistic concurrency, boundary/finalized gates | High | REVIEWED_CLEAN (static; local Docker unavailable) |
| Regression tests and compatibility fakes | all | Direct consumers and older partial-schema/test implementations | Low | REVIEWED_AFTER_FIX |

## Consolidated validation

- `flutter test`: 823 passed, 2 intentionally skipped.
- `flutter analyze --no-fatal-infos`: zero errors; repository-baseline warnings remain.
- `git diff --check`: clean.
- Supabase local runtime validation could not run because Docker returned an
  API-version 500 while inspecting the local Supabase database container.
  The migration was reviewed statically for explicit search paths, membership
  authorization, RLS/grants, idempotency ordering, row locks, and atomicity.
