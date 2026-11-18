# Shared map sync: implementation and rollout

Status: deployed to production on 2026-09-16; shared sync is enabled for `cebu` and `guadalupe-sitio-3`. Android 0.1.5 (4008) is installed on the connected TECNO phone.

## Implemented flow

A completed survey on an enabled map is frozen into a durable local operation. Supabase validates and accepts it, or returns an explicit conflict. Accepted changes form ordered, immutable transaction bundles. Other phones pull those bundles, preserving unfinished local work. Realtime wakes the pull; foreground polling, reconnect, resume and Android background work provide additional recovery paths.

The server generates a native map package and a combined GeoJSON export. Get Maps installs the native package and catches up from its revision. Drive shows `output/<map>/Current.geojson`, with older versions and registered contributor uploads under Archive. Record sync succeeds independently of export creation.

Important implementation choices:

- Existing maps use the old flow until explicitly activated. A failed network call never silently switches an enabled map back to timestamp sync.
- Database schema is Drift v19. Existing drafts, jobs, photos and map selections are preserved.
- Frozen submissions are read-only. A new survey/observation gets a new ID. Explicit additional observations retain multiple household surveys when the shared building/road attributes agree; incompatible shared attributes require review.
- Unresolved conflicts and dedup candidates do not enter accepted exports.
- Household responses stay in the protected survey database. Shared packages exclude household responses; public-facing GeoJSON also omits free-text remarks, CBMS IDs and photo references.
- The initial GIS output is GeoJSON, not a regenerated shapefile ZIP. Original shapefile imports remain supported for legacy maps. Native packages preserve stable IDs and accepted survey relationships.
- No change-history pruning is enabled. Existing clients can replay from zero; new downloads use a complete snapshot plus deltas. Cursor-expiration/compaction is unnecessary until retention is introduced.
- Export jobs coalesce to the latest consistent database snapshot. A retry may build a newer revision; it never publishes a mixture of revisions. Incomplete archive artifacts are not used for downloads.
- Current exports are bounded to 10,000 projected features and 16 MiB per artifact. Larger exports report a retryable operational failure while record sync continues; increasing those limits requires worker profiling.
- Original source/form sidecars are retained across generated downloads. Replacing input files cannot overwrite an activated map's generated download pointer. Assignment metadata changes advance the export revision; existing phone metadata is refreshed through Get Maps. A separate form/configuration delta protocol remains a future extension; existing versioned definitions remain valid for submitted work.

## Changed components

- Migration `20260916082726_shared_map_revision_sync.sql`: private replication tables, deferred complete-bundle capture, operation/resolution receipts, explicit conflict exclusion, photo registration, baseline activation, guarded legacy writes and repairs to existing form/geometry RPCs.
- `lib/core/sync/data/shared_map_sync.dart`: ordered pulls, transactional snapshot installation, protected drafts, tombstones and deferred local projection.
- `lib/core/sync/domain/finalize_submission.dart`: immutable outbox payloads and duplicate completion guard.
- Sync controllers/repositories: periodic retry, claim recovery and account-scoped processing. WorkManager now opens the real saved database.
- Get Maps acquisition: native package support with the existing verified download transport.
- Review: automatic completed-work sync, manual retry, and separation from Drive export completion on enabled maps.
- `server/drive-gateway/src/shared-map-export.ts`: bounded snapshot generation, verified uploads, leases, serialization of promotion, retries and a single Current export.
- Gateway endpoints: supervisor baseline activation, shared status, authenticated export dispatch and protection against legacy input publication on enabled maps.

## Verification

Run against disposable local databases, never a production database:

```sh
flutter test test/core/db test/core/sync test/features/review test/features/assignment
npm --prefix server/drive-gateway run check
npm --prefix server/drive-gateway run prepare:edge
```

The new server integration suite uses a disposable database on a local Supabase Postgres container at port 55441. Set `SHARED_SYNC_TEST_DATABASE_URL` to an alternative localhost PostGIS database. The ordinary gateway suite uses its existing independent test database configuration. Both suites create and drop their own named test databases.

```sh
cd server/drive-gateway
node --import tsx --test test/shared-map.test.ts
```

The historical August geometry migration uses unqualified PostGIS types with an empty search path. The test bootstrap disables body validation for that historical migration only; the new migration installs corrected definitions with normal validation. Existing deployed migration history is not rewritten.

Coverage includes duplicate/concurrent retries, membership denial, conflict resolution replay, additional observations, photo registration, immutable transaction bundles, tombstones, snapshot installation, draft preservation and reconciliation, failed exports, and database access restrictions. Real-device two-user field testing and hosted worker CPU profiling remain release checks, not claims established by local tests.

## Deployment order

1. Back up the live database, manifests and the installed client's saved fieldwork. Record the current gateway deployment version. Do not restore an older database over accepted new work as a rollback strategy.
2. Apply the new migration through the normal migration process. Private map state defaults to disabled. Existing ambiguous active submissions are conservatively marked as conflicts; inspect those rows before activating a pilot.
3. Deploy the generated gateway and a mobile build containing Drift v19. Confirm source registrations, assignment membership and stable source feature IDs. Do not activate a map while older clients are still expected to edit it.
4. Configure a strong random `EXPORT_WORKER_TOKEN` as a gateway secret. Store its matching value in Supabase Vault as `firecheck_export_worker_token`, and the full internal worker URL as `firecheck_export_worker_url`. Run `server/drive-gateway/sql/schedule-shared-exports.sql` with administrative access. It dispatches one bounded job every minute. The token belongs only on the server, never in an APK.
5. On one pilot map, submit a verified GeoJSON-derived baseline manifest to the supervisor-only endpoint below. The request is additive: existing fieldwork and geometry win. Keep IDs identical to the existing source manifest. It rejects duplicate IDs, out-of-boundary geometry and cross-map ID reuse.
6. Trigger one export, verify native download and Current GeoJSON, then test two signed-in phones through offline completion, reconnection, conflict resolution, photo transfer and app restart. Check that the hosted worker stays within its CPU/memory/runtime budget.
7. Activate additional maps after the pilot passes. Historical files are moved only when the new combined export is successfully promoted; no file content is deleted.

Baseline activation request:

```text
POST /v1/admin/assignments/<assignment UUID>/shared-baseline
Authorization: Bearer <supervisor session>
{
  "expectedFeatureCount": 1,
  "features": [{
    "id": "<stable source feature UUID>",
    "type": "building",
    "geometry": {"type": "Polygon", "coordinates": ["<valid coordinates>"]}
  }]
}
```

The JSON above illustrates the contract; replace the geometry with actual valid GeoJSON. The endpoint requires an existing source registration and rejects activation of an already activated map. For automated jobs use the internal token endpoint; manual supervisor testing can call `POST /v1/admin/shared-map-exports/run`.

Check `GET /v1/assignments/<id>/shared-status` for accepted revision, exported revision and last export error. Inspect the private job table for leases and retry times. Alert on persistently stale exports or repeated failures; do not interpret a successful HTTP dispatch with `processed:false` as a newly generated map.

## Rollback

Pause the export cron job and keep the last complete download package available. Keep accepting/replaying the revision protocol for already enabled clients; do not downgrade them to untracked writes. Disable rollout to additional assignments. Preserve receipts, revisions, drafts and pending operations. Correct and redeploy the worker/client without dropping accepted records.

## Local verification record

- Client regression suite: 377 tests passed across database, sync, review, assignment/download and submission-tab coverage.
- Upgrade recovery: the additional v18-to-v19 test passed with an interrupted job restored to pending and its saved draft preserved.
- Static analysis of `lib` and `test`: no errors; existing warnings/style findings remain.
- Gateway TypeScript compilation and Edge artifact generation passed. All 29 server tests passed, covering the existing gateway and the shared-map path using the restricted gateway role.
- Supabase security advisors were run against the isolated test database. They reported inherited mutable-search-path helpers and the historical PostGIS extension/reference table in `public`; touched internal helpers now have fixed search paths. The new private replication tables have RLS and explicit server-only policies/permissions, verified by integration tests.
- Scheduler setup follows the documented [Supabase cron/Vault pattern](https://supabase.com/docs/guides/functions/schedule-functions) and [pg_net API](https://supabase.com/docs/guides/database/extensions/pg_net). No hosted schedule was created during implementation.
- Release APK 0.1.5 (ARM64 version code 4008) was built successfully and passed the 47.72 MB size check. No live database migration, Drive write, map activation or phone installation was performed for this implementation. ADB listed no connected device during the final checks.


## Production rollout record — 2026-09-16

- User explicitly authorized backend deployment and activation after Android installation.
- Backed up application/gateway schema and data, migration history, source manifests, and gateway version 8 under the ignored, restricted `.secrets/shared-map-rollout/` directory. These backups contain private data and must not be committed.
- Production was missing `20260823123559_add_versioned_forms_and_geometry_operations`. Applied it and `20260916082726_shared_map_revision_sync` in one transaction, recording both migration versions. Function-body validation was disabled only for the historical definitions, then restored before the corrected shared-sync definitions. No partially migrated state was exposed.
- Deployed gateway version 10 (ACTIVE) with its server-only export token. Updated the deployment tool to retain that token on future deployments.
- Configured matching Vault secrets and the one-minute export scheduler. Verified an active schedule, successful dispatch, and HTTP 200 responses from the hosted worker.
- Downloaded and checksum-verified both original source manifests (13 Cebu files and 4 Guadalupe files). Ran the production Flutter importer against them in a disposable local database to derive the exact stable IDs: 5 Cebu and 1,428 Guadalupe source features. All were already present in production; no baseline insertion or geometry replacement was necessary. Guadalupe retains four additional field-created features.
- Two Guadalupe source geometries touched the boundary with a 1.776e-15-degree reprojection difference from their stored counterparts. Verified they were within 1 cm of the recorded boundary and retained all existing geometry unchanged. Activated the already complete canonical baselines using the administrative activation function.
- Both maps published revision 1 with matching exported revisions and no recorded export error. Downloaded native and GIS artifacts and verified checksums, assignment IDs, revisions, and counts: Cebu 5 features; Guadalupe 1,432 features. Each Drive map folder contains exactly `Current.geojson` and `Archive`.
- Verified the member-role change RPC returns the complete revision-1 bundles for both assignments. Existing submissions were preserved; zero rows required the migration's ambiguous-conflict marker.
- Hosted security advisors were run. The existing PostGIS `spatial_ref_sys` RLS finding, mutable-search-path helper warnings, extension-placement warnings, and authentication configuration warnings remain; no private sync table is exposed without RLS. Intentional authenticated RPC grants are reported by the function-execution advisor.
- Android installation and launch succeeded earlier. During live verification the phone was locked; the user was asked to unlock it. A new end-to-end phone submission and two-user offline/conflict scenario have not been performed against production.


## On-device verification — 2026-09-16 evening

- Verified on the installed TECNO Android build after the user unlocked and authenticated in Review.
- The initial cellular connection failed Android internet validation and reset Supabase token-refresh requests. After the user connected Wi-Fi, shared-map pulls succeeded.
- Cebu switched to `Review and sync`, displayed `No new changes to sync` and `Up to date`.
- Guadalupe also switched to `Review and sync` and displayed seven completed surveys. Triggering its existing sync action successfully uploaded the pending photo job (`4691040a` prefix); the home-screen sync warning cleared.
- The server advanced Guadalupe from revision 1 to revision 2 and the automatic exporter caught up to revision 2 with no export error. Cebu remained at revision 1 with no export error.
- Remaining observed UI inconsistency: Guadalupe continued to show `Sync changes` after the success message and cleared job warning, while Cebu correctly showed `Up to date`. The local reason for that remaining change indicator has not been established; do not claim duplicate-upload gating is fully verified on both maps.
- No survey answers or geometry were edited during this check. A second-user/offline-conflict scenario is still not covered by this single-phone verification.


## Guadalupe sync indicator resolved — 2026-09-16

- On-device status-only diagnostics established the actual outstanding work: one geometry revision in `ready_to_upload`, seven uploaded surveys, nine uploaded photos, and two private drafts. Diagnostics were removed from the final build.
- The geometry job had exhausted retries during a DNS/auth refresh outage. Review omitted geometry jobs from its failure/progress queries and omitted geometry revisions from its completion message, so it incorrectly announced success while continuing to enable Sync changes.
- Review now includes geometry jobs and current attribution/new-feature job types, exposes failures and retry controls, and reports remaining geometry explicitly. Discarded geometry is excluded from pending-change checks and no longer blocks applying later shared changes.
- Retrying the hidden job exposed a legacy split ordering issue: the child feature had already uploaded, but the split transaction tried to insert its UUID again. Migration `20260916123208_recover_preuploaded_split_features.sql` allows recovery only when the existing new child matches assignment, type, geometry and lineage, is not deleted/merged/pending dedup, and the two halves partition the original parent within negligible projection rounding. Child survey records remain untouched; mismatches fail explicitly.
- Migration applied through `supabase db push` after a dry run confirmed it was the sole pending migration. The prior function definition is backed up in the restricted rollout directory.
- Installed Android 0.1.6, version code 4010. The user's fingerprint authentication opened Review. Retried the preserved geometry operation; the worker logged success. Guadalupe changed to `Up to date` / `No new changes to sync`; Android accessibility confirms the button is disabled and not clickable.
- Backend records remain unchanged in count: Guadalupe 1,432 features and 7 surveys, Cebu 5 features and 1 survey. Guadalupe advanced to shared revision 3; the automatic export reached revision 3 with no error. Exactly one split revision and the correct child-to-parent lineage were verified.
- Validation: final 74 client tests and 13 shared-backend integration tests passed, including discarded-geometry reconciliation, visible failed geometry jobs, accurate completion reporting, preuploaded child recovery with survey preservation, rejection of mismatches, and idempotent retries. ARM64 release passed the size check; `git diff --check` passed. Security advisor findings are unchanged from the prior rollout.
