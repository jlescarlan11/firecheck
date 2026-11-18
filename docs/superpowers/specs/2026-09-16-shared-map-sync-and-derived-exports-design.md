# Shared map sync and generated exports

Date: 2026-09-16
Status: Proposed architecture. This document does not implement or deploy the new flow.

## Product decision

Each assignment has one shared map. Supabase stores its accepted features and survey records. Phones keep an offline copy and private drafts. Completing work queues changes for automatic sync; the server accepts valid changes, and other authorized phones fetch them. Download packages and Drive exports are generated from that accepted map in the background.

Recommended default, pending product feedback: **Mark complete means share when connected.** Saving a draft does not share it. A manual Sync action retries pending work. Automatic publication applies only after validation and conflict resolution; supervisor approval is not required by default.

User experience:

1. Download a map once and work offline.
2. Save drafts privately; mark finished surveys complete.
3. See “Saved on this phone” while offline, then “Synced” after server acceptance.
4. Teammates receive accepted changes when connected, without downloading the whole map again.
5. Drive automatically exposes one current combined export for the assignment.

[Architecture diagram](2026-09-16-shared-map-sync.diagram.md)

## What exists today

These findings describe the inspected working tree, including the earlier upload fixes, rather than claiming this proposal already exists.

| Area | Existing behavior | Required change |
| --- | --- | --- |
| Local sync | Drift jobs, dependency ordering, retries, finalize action | Stable operation identity for every completed revision; automatic scheduling |
| Collaboration | Realtime wakeups and remote attribution/new-feature pulls | Durable unified feed covering edits, deletes, geometry and configuration |
| Conflict handling | Submission base versions, conflict RPCs, keep-both/overwrite resolution | Explicit accepted-state model and consistent rules for every mutation |
| Get Maps | Published copies of source/input files | Snapshot of accepted shared state, followed by newer deltas |
| Drive output | Local completed-feature exports organized by map and contributor | Server-generated combined export, including the complete map |
| Geometry bootstrap | Phones can publish imported features into Supabase | Server-owned import with stable identity and controlled activation |

Relevant implementation: `lib/core/sync/domain/finalize_submission.dart`, `lib/core/sync/data/sync_jobs_repository.dart`, `lib/core/sync/data/remote_attributions_pull_service.dart`, `lib/core/sync/worker/realtime_sync_controller.dart`, `lib/features/assignment/data/canonical_feature_publisher.dart`, `lib/core/sync/shapefile/shapefile_exporter.dart`, and `server/drive-gateway/src/app.ts`.

The existing timestamp-based pulls are not a complete replication protocol. The current exporter reads the phone's completed local features, so it cannot be treated as everyone's authoritative combined map. The existing published package is a copy of input, not necessarily the latest accepted fieldwork.

## Ownership and folder meaning

| Component | Responsibility |
| --- | --- |
| Supabase database | Authoritative accepted records, permissions, revisions, conflict decisions and sync receipts |
| Phone database | Downloaded accepted state, private drafts, pending operations, photo queue and sync cursor |
| Input | Original import material and provenance; changed only through an explicit import workflow |
| Published snapshots | Internal immutable download packages generated from accepted state |
| Drive output | Human-facing combined GIS export generated from the same accepted state |

Published and output are derived representations of one map, not competing editable masters. They may use different formats: a mobile package preserves native types and relationships, while a GIS export provides compatible layers. If formats match, reuse the same artifact rather than create another copy.

Target Drive layout:

```text
firecheck/
  input/                           original source material
  output/
    guadalupe-sitio-3/
      Current                      shortcut to the latest complete version
      Archive/
        r000042/                   immutable combined export and manifest
        r000041/
    cebu/
      Current
      Archive/
  published/                       internal download artifacts, if Drive is retained for them
```

Expose “Current map” in the app, not these internal distinctions. Retain existing contributor folders as historical material during migration. Do not delete or automatically merge old exports based on folder names alone. A single ZIP per GIS version prevents users receiving mismatched `.shp`, `.shx`, and `.dbf` files.

## Accepting completed work

Completing a survey writes an immutable operation into the local outbox in the same SQLite transaction as the completion state. Capture assignment ID, author, entity IDs, form version, expected base revisions and payload. Later edits create a new operation ID; reusing a successful entity-level job would hide later changes.

An authenticated server mutation endpoint performs one short database transaction:

1. Check assignment membership, role, assignment status and payload/form/geometry validity.
2. Look up `(assignment_id, actor_id, operation_id)`. Return its stored result for an identical retry; reject the same ID with a different payload hash.
3. Compare expected entity revisions. Accept compatible changes or record a conflict without replacing accepted state.
4. Commit accepted records, a map revision, a complete change bundle, the operation receipt and an export-job request together.

No Drive request or file generation belongs in this transaction. A lost network response is safe: retrying the same operation returns the original outcome. A permanent validation error remains visible for correction; transient failures retry with bounded backoff.

Start with record-level optimistic concurrency. Two people editing different records can both succeed. If both edit the same building from revision 12, accepting the first must not silently overwrite it with the second. Show the competing values and let an authorized user resolve them. Field-level automatic merging can be added later for demonstrably independent fields.

Preserve the distinction between a map feature and observations attached to it. Multiple household surveys or explicitly retained observations may be legitimate. Do not collapse them into one row per feature. Define accepted, conflicting and superseded states explicitly and define the current-map projection deterministically. Existing conflict/keep-both RPCs mean `superseded_at IS NULL` alone is not sufficient to identify one accepted value.

## Sending changes to other phones

Add an ordered change feed per assignment. For each accepted mutation, lock the assignment revision row, increment its revision, and commit the records and change bundle while holding that lock. This avoids a cursor skipping a transaction that allocated a sequence number early but committed late. Keep transactions short; measure contention before adding parallel writers per map.

Each bundle contains immutable values for its revision, including upserts, tombstones, geometry operations and relevant schema/configuration references. Do not construct an old revision's response by joining mutable current rows. Splits and merges form one atomic bundle.

Suggested contract:

```text
commit_operation(operation_id, assignment_id, expected_revisions, payload)
  -> accepted(revision) | conflict(details) | rejected(reason)

get_changes(assignment_id, after_revision, through_revision?, page_token?)
  -> complete_bundles[], through_revision, next_page_token, has_more

get_snapshot_manifest(assignment_id)
  -> snapshot_revision, schema_version, artifacts[], checksums
```

Fix a high-water revision for each paginated catch-up. Advance the phone's cursor only in the same SQLite transaction that applies complete bundles. An interrupted pull can safely replay. Scope caches, cursors and jobs by account and assignment; switching maps must not retarget an in-flight operation.

Realtime notifications trigger a pull; they are not the durable delivery mechanism. Also pull after reconnection, app resume and periodically while active. Missed notifications must not lose work. Offline phones catch up when they reconnect, subject to mobile background execution limits.

Apply remote changes to the accepted local mirror, keeping unsent drafts and completed pending edits as separate overlays. Flag a changed base for review instead of overwriting the user's work. Receiving a deletion must preserve any local draft long enough to resolve or recover it.

If the cursor predates retained history, return `bootstrap_required`. Download snapshot R, verify it, install it transactionally and then fetch revisions after R. Preserve drafts, pending operations and attachment references throughout. Stable server UUIDs must survive package regeneration and map renaming.

## Building packages and exports

Use a durable database job table with leases, attempt counts, retry times and a generation/fencing token. Coalesce bursts of changes into one desired latest revision per map. A process crash must leave a recoverable job; a fire-and-forget request is insufficient.

The worker materializes an exact database snapshot and its revision in a consistent database transaction, then builds files from those frozen rows outside the transaction. Reading independent live pages can produce a mixed version and is not acceptable. Benchmark snapshot materialization; large maps may require a bounded materialization strategy before rollout.

Generate the native mobile package and the GIS ZIP from that same frozen dataset. Include all accepted map features, including unsurveyed ones, with survey observations in explicitly defined related layers. Preserve feature IDs, coordinate reference metadata, encoding and form version. Preserve full-fidelity source values in the native package when shapefile field limits require a documented mapping.

Upload to an immutable version location, verify file checksums and completeness, then atomically promote the database manifest pointer. Never point to a partially built version or let a slower older job replace a newer version. Update the Drive Current shortcut as a retryable projection; the database manifest remains authoritative if that final Drive update temporarily fails.

The app reports the represented revision and export freshness. It can say “Changes synced; export updating.” Existing users receive deltas immediately even if Drive is unavailable. New downloads use the last complete snapshot plus subsequent changes.

Photos have separate durable transfer jobs and readiness states. Record acceptance can precede optional media completion; any required-media policy must be explicit. Store stable object references, not expiring signed URLs inside permanent packages. Fetch authorized URLs when needed. An export manifest identifies unavailable media rather than pretending it is complete.

## Deployment and resource limits

Reuse Supabase, Drift and the existing gateway initially. This does not require microservices or a full event-sourcing rewrite; the change log exists for replication and audit, while accepted tables remain the read model.

Start with a Postgres job table and an authenticated scheduled dispatcher that runs bounded, resumable worker slices. Confirm scheduler availability and benchmark representative maps before selecting execution limits. Supabase currently documents 256 MB memory, 2 seconds CPU per request and a 150-second Free-plan worker duration; file generation cannot be assumed to fit merely because network I/O is fast. [Supabase function limits](https://supabase.com/docs/guides/functions/limits)

If exports exceed those limits, keep record sync operational and choose an explicit suitable worker deployment before enabling automatic exports at that scale. Do not silently add a paid service. No large native GIS dependency is assumed available inside Edge Functions.

RLS and server checks enforce assignment access on mutations, deltas, snapshots and media. Export access must reflect who may view its contents; do not expose household details to all map viewers by default. Cache artifacts by permission scope where necessary. Service credentials stay on the server. Revocation stops subsequent authorized access; already downloaded offline data cannot be remotely erased by changing RLS alone. [Supabase Realtime authorization guidance](https://supabase.com/docs/guides/realtime/postgres-changes)

## Progress and recovery in the app

| Situation | User-facing state |
| --- | --- |
| Draft saved | Saved on this phone |
| Completed offline | Waiting for connection |
| Sending operations | Syncing 3 of 8 changes |
| Accepted records | Synced |
| Concurrent incompatible edit | Needs review |
| Media still transferring | Synced · 2 photos pending |
| Derived files pending | Export updating |

Use measured per-file percentages for transfers with known byte totals. Use an indeterminate preparation state when total work is unknown. Do not fabricate percentages for database validation, merging or packaging. Repeating Sync with no new operations does no work; a new edit becomes a new revision.

## Migration and implementation gates

1. **Inventory and preserve.** Back up server data and manifests; inspect stable IDs, accepted/conflict rows, source geometry and old exports on one pilot assignment. Inventory existing client versions. Preserve phone drafts and outboxes.
2. **Server protocol.** Add explicit accepted-state rules, operation receipts, revisions, change bundles and job records. Route every writer, including legacy RPCs and administrative imports, through revisioned commits or block incompatible writers before activation. Test conflicts and retry behavior first.
3. **Phone sync.** Add a versioned local migration for the accepted mirror, draft overlays and operation identities. Replace timestamp cursors with revision cursors. Enable per assignment using server capabilities. Disable mobile baseline publishing for migrated maps.
4. **Automatic completion sync.** Connect Mark complete to outbox scheduling, lifecycle catch-up and honest statuses. Validate on two phones with offline work before changing the default workflow.
5. **Generated snapshots and exports.** Build shadow artifacts from server state, compare them with expected records, benchmark worker limits, then activate the versioned download manifest and Drive Current projection.
6. **Retire old paths.** Archive historical per-user exports after verification. Remove local full-map export from normal collaboration only when the server export path is proven. Keep explicit diagnostic/manual export separate if needed.

Baseline import needs explicit provenance and collision handling; it must not recreate deleted features from an old phone package. An input replacement becomes an audited server import with a revision or new baseline epoch, not an unnoticed file overwrite.

Rollback disables automatic scheduling or new export promotion while preserving accepted writes and all receipts. Never roll back by restoring an old database snapshot over newly accepted fieldwork. Keep the previous complete package available and use compatible deltas, or temporarily disable new downloads if compatibility cannot be preserved.

## Acceptance criteria

- Two phones can finish different surveys offline, reconnect, and receive both accepted results.
- Conflicting edits to one feature never silently replace accepted work; resolution is audited.
- Repeating an operation after a lost response creates neither duplicate records nor duplicate map revisions.
- Crashes before and after receipt/cursor persistence recover without losing drafts or skipping changes.
- Geometry edits, additions, deletions, splits and merges converge across phones.
- Expired cursors trigger safe bootstrap; account/map switching cannot leak or misroute data.
- Every enabled writer produces revisioned changes; old clients cannot bypass the protocol.
- Drive failure does not block collaboration; failed and out-of-order export jobs cannot corrupt Current.
- Snapshot R plus subsequent deltas produces the same accepted state as a fresh server view.
- Permissions are checked for records, photos, snapshots and exports, including revoked membership.
- Transfer progress reflects measured work; unchanged completed work is not uploaded again.

Initial performance targets to measure, not current guarantees: accepted online changes visible to another active connected phone within 5 seconds at p95; exports normally current within 5 minutes after a short burst of edits. Establish representative map sizes and concurrency before committing to these targets.

## First implementation milestone

Prove reliable two-phone record sync on one pilot map: operation idempotency, explicit conflict semantics, ordered changes and protected local drafts. Then generate a combined export from that verified shared state. Folder cleanup alone cannot establish correct collaboration.

## Implementation follow-through

The core record-sync and generated-export flow is now implemented locally. See [implementation and rollout notes](../plans/2026-09-16-shared-map-sync-rollout.md) for the exact delivered scope, bounded GeoJSON/native-package format, migration order, scheduler setup and release checks. The live service has not been switched to this architecture.
