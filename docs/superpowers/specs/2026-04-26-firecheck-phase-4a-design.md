# FireCheck Mobile — Phase 4a Design Spec

**Date:** 2026-04-26
**Status:** Draft v1 (brainstorming output)
**Phase:** 4a — Sync engine (outbox + worker + retry + connectivity + 401/409 + WorkManager + bundle export)
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Predecessor:** `docs/superpowers/specs/2026-04-26-firecheck-phase-3b-design.md`
**Successor (planned):** Phase 4b — Review screen + Upload Data flow + Assignment Lock UI

## 1. Summary

Phase 4a delivers the full sync engine for FireCheck Mobile: outbox transaction, sync worker with retry/backoff, two-phase photo upload, connectivity- and lifecycle-triggered resume, WorkManager periodic ticks, 401 auth refresh, 409 assignment-closed-remotely halt + JSON+ZIP bundle export. No user-facing UI — Phase 4b builds the Review screen and Upload Data flow that surface this engine to the user. For Phase 4a, the engine is triggered by an internal debug long-press on the Home screen.

After this ships, an enumerator can:

1. Survey buildings/roads with photos as today (Phase 2/3a/3b unchanged).
2. Tap Done → submission transitions to `ready_to_upload` (no outbox yet).
3. Long-press the Home screen's debug trigger → `manualDrainNow()` runs the outbox transaction for all `ready_to_upload` submissions and starts the sync worker.
4. Worker uploads to Supabase: submissions first (with bundled OLP + attrs payload), then photos in two-phase upload, then any `is_new=true` features. Up to 3 concurrent. Retry/backoff per spec. Connectivity loss pauses; restoration resumes. WorkManager wakes the worker every ~15 min in the background.
5. On 409 (assignment closed by supervisor), the worker halts the queue, marks the assignment `closed_remotely`, and writes a JSON+ZIP bundle of unsynced work + photo files to the Downloads folder.

## 2. Scope

### In scope

- **Drift schema bump v4 → v5**: add `closedRemotely` (bool default false) to `assignments`. Matching Supabase migration 005.
- **Outbox transaction** (`FinalizeSubmissionUseCase`): Drift transaction that writes sync_jobs rows for one submission + N photos + 0|1 new_feature, atomically. Idempotent: re-execution skips already-queued entities.
- **Sync worker** (`SyncWorker`): drains pending sync_jobs, max 3 concurrent. Submission jobs first; photo jobs blocked on parent submission until `uploaded`. State transitions per outcome.
- **`SyncOutcome` sealed class**: `Success` / `TransientFailure(error)` / `PermanentFailure(error)` / `AuthExpired` / `AssignmentClosed(assignmentId)`.
- **Two-phase photo upload**: phase 1 fetch signed URL + PUT file; phase 2 mark photo uploaded server-side + UPDATE local `photos.upload_status='uploaded'` + `storage_path`.
- **Retry/backoff**: pure `nextRetryAt(attempts)` returning 30s, 2m, 10m, 1h, then null (dead). 4xx (except 401, 409) → dead immediately.
- **Trigger sources**:
  - Manual: Phase 4a debug long-press on Home (replaced by Phase 4b's "Start Upload" button).
  - Connectivity-regained via `connectivity_plus`.
  - App-foregrounded via `AppLifecycleListener.onResume`.
  - WorkManager periodic ticks (~15 min) via `workmanager` package.
- **Auth refresh on 401**: call `Supabase.instance.client.auth.refreshSession()` once, retry inline. If refresh fails, treat as transient. If retry also returns 401, treat as transient (no infinite loop).
- **409 assignment-closed-remotely**: worker halts queue; `AssignmentLockRepository.markClosed(id)` sets `closed_remotely=true`; `PendingWorkBundle.exportFor(id)` writes JSON+ZIP to app's Downloads dir; lock state stream exposed for Phase 4b's blocking UI.
- **`SyncApi` testability seam**: abstract interface; `SupabaseSyncApi` real impl; `FakeSyncApi` test double with controllable response queue.
- **Singleton `SyncController`**: facade exposing `start()` / `triggerNow()` + status stream. Wires connectivity + lifecycle listeners + WorkManager registration.

### Out of scope (Phase 4b territory)

- Review screen (UI for Upload Data action with validation warnings + per-job progress UI).
- Biometric gate before Upload Data.
- "Start Upload" button — replaces the Phase 4a debug trigger.
- Assignment-locked blocking screen + share-sheet for the bundle file.
- Submitted-state lock preventing further edits after `assignments.submitted_at` is set.

### Out of scope forever (per master spec §15)

- Polygon/road reshape during upload.
- Real-time multi-enumerator collaboration.
- Server-side validation responses surfaced as inline form errors.
- Supervisor approval / messaging in-app.
- iOS background upload (v2).

## 3. Architecture

### 3.1 Module layout

```
lib/core/sync/
├── domain/
│   ├── sync_job_status.dart           # constants: pending|in_progress|success|failed|dead
│   ├── sync_entity_type.dart          # constants: submission|photo|new_feature
│   ├── retry_schedule.dart            # pure: nextRetryAt(attempts) → DateTime?
│   ├── sync_outcome.dart              # sealed
│   └── finalize_submission.dart       # use case: outbox transaction
├── data/
│   ├── sync_jobs_repository.dart      # CRUD + claim/release helpers
│   ├── submission_payload_builder.dart # joins submission+attrs+olp → JSON
│   ├── sync_api.dart                  # abstract interface
│   ├── supabase_sync_api.dart         # real Supabase impl
│   └── fake_sync_api.dart             # in-memory test double
├── worker/
│   ├── sync_worker.dart               # main loop + per-outcome state transitions
│   ├── sync_controller.dart           # singleton facade
│   ├── connectivity_listener.dart     # connectivity_plus subscription
│   ├── lifecycle_listener.dart        # AppLifecycleListener.onResume
│   └── workmanager_dispatcher.dart    # WorkManager callbackDispatcher + periodic schedule
├── failure/
│   ├── assignment_lock_repository.dart # closed_remotely state + stream
│   └── pending_work_bundle.dart        # JSON+ZIP writer
└── presentation/
    └── sync_providers.dart             # Riverpod wiring
```

### 3.2 Modified files

- `lib/core/db/tables/assignments.dart` — add `closedRemotely` column.
- `lib/core/db/database.dart` — `schemaVersion 4 → 5` + onUpgrade branch.
- `lib/core/db/database.g.dart` — regenerated.
- `pubspec.yaml` — add `connectivity_plus`, `workmanager`, `archive`, `share_plus`, `path_provider` (verify last is direct).
- `android/app/src/main/AndroidManifest.xml` — INTERNET (probably present), `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`.
- `lib/main.dart` — initializes WorkManager + starts SyncController + initial drain on app launch.
- `lib/features/home/presentation/home_screen.dart` — adds debug long-press trigger (replaced in 4b).
- `supabase/migrations/005_assignments_closed_remotely.sql`.

### 3.3 Reused infrastructure

`AppDatabase` Drift connection, `submissions`/`photos`/`features`/`sync_jobs` tables (all from Phase 0), Supabase auth + Storage clients, FK chain test seeding, `submittedBy` not `enumeratorId`.

### 3.4 Data flow

**Outbox transaction (triggered by Phase 4a debug long-press):**
```
manualDrainNow()
  → for each submission with sync_status='ready_to_upload':
      FinalizeSubmissionUseCase.execute(id)
        Drift txn:
          UPDATE submissions.sync_status='queued'
          INSERT sync_jobs(submission, id) if not exists
          for each photo: INSERT sync_jobs(photo, photo.id, blocks_on=id) if not exists
          if feature.is_new: INSERT sync_jobs(new_feature, feature.id) if not exists
  → SyncController.triggerNow()
    → SyncWorker.drain()
```

**Worker drain loop:**
```
SyncWorker.drain()
  while assignment not locked:
    claim up to 3 pending sync_jobs (submission first, then photos with parent uploaded, then new_features)
    if claimed empty: return
    parallel:
      for each job: process via _execute → _applyOutcome → state transition
```

**Trigger sources feed SyncController.triggerNow:**
```
manual debug long-press        ─┐
ConnectivityListener (online)  ─┼─→ SyncController.triggerNow()
SyncLifecycleListener (resume) ─┤      → SyncWorker.drain() (deduped)
WorkManager periodic ~15min    ─┘
```

## 4. Schema bump v4 → v5

### 4.1 Drift table

`lib/core/db/tables/assignments.dart` adds:
```dart
BoolColumn get closedRemotely => boolean().withDefault(const Constant(false))();
```

### 4.2 Drift migration

`lib/core/db/database.dart`:
```dart
@override
int get schemaVersion => 5;

// onUpgrade — preserve all existing branches; append:
if (from < 5) {
  await m.addColumn(assignments, assignments.closedRemotely);
}
```

Regenerate: `dart run build_runner build --delete-conflicting-outputs`.

### 4.3 Supabase migration 005

`supabase/migrations/005_assignments_closed_remotely.sql`:
```sql
alter table public.assignments
  add column closed_remotely boolean not null default false;
```

### 4.4 Verified existing schema

Phase 0 already has `photos.uploadStatus` (text default 'pending') + `photos.storagePath` (nullable text). No additions needed there.

## 5. Outbox transaction

`FinalizeSubmissionUseCase.execute(submissionId)` opens `_db.transaction { ... }` and:

1. UPDATEs `submissions.sync_status='queued'` + `updated_at=now`.
2. INSERTs sync_jobs row with `entity_type='submission'`, `entity_id=submissionId` IF an existing row with that (entity_type, entity_id) doesn't exist (skip-if-exists).
3. SELECTs all photos for the submission. For each, INSERTs sync_jobs row with `entity_type='photo'`, `entity_id=photo.id`, `blocks_on_submission_id=submissionId` (skip-if-exists).
4. SELECTs the parent feature. If `feature.isNew=true`, INSERTs sync_jobs row with `entity_type='new_feature'`, `entity_id=feature.id` (skip-if-exists).
5. Returns `FinalizeResult(submissionId, photoCount, newFeatureQueued)`.

Atomicity: any thrown exception rolls back the entire transaction. The user can re-tap to retry.

## 6. Sync worker

### 6.1 `SyncOutcome` sealed class

```dart
sealed class SyncOutcome { const SyncOutcome(); }
class Success extends SyncOutcome { const Success(); }
class TransientFailure extends SyncOutcome { const TransientFailure(this.error); final String error; }
class PermanentFailure extends SyncOutcome { const PermanentFailure(this.error); final String error; }
class AuthExpired extends SyncOutcome { const AuthExpired(); }
class AssignmentClosed extends SyncOutcome { const AssignmentClosed(this.assignmentId); final String assignmentId; }
```

### 6.2 HTTP-to-outcome mapping (`SupabaseSyncApi`)

| HTTP | Outcome |
|---|---|
| 2xx | `Success` |
| 401 | `AuthExpired` |
| 409 | `AssignmentClosed(assignmentId)` |
| 4xx (other) | `PermanentFailure` |
| 5xx / network / timeout | `TransientFailure` |

### 6.3 Per-outcome state transitions

| Outcome | Action |
|---|---|
| `Success` | `markSuccess(jobId)` — UPDATE sync_jobs.status='success'. For submission jobs: also UPDATE local submissions.sync_status='uploaded'. For photo jobs: also UPDATE local photos.upload_status='uploaded' + storage_path. |
| `TransientFailure` | `attempts++`. If `nextRetryAt(attempts) == null` → `markDead(jobId, error, attempts)`. Else → `markPendingRetry(jobId, attempts, lastError, nextRetryAt)`. |
| `PermanentFailure` | `markDead(jobId, error, attempts+1)`. |
| `AuthExpired` | `Supabase.instance.client.auth.refreshSession()`. If refresh succeeds, retry `_execute(job)` inline. If retry yields `AuthExpired` again → treat as `TransientFailure('repeat 401')`. If refresh fails → `TransientFailure('auth refresh failed')`. |
| `AssignmentClosed(id)` | `assignmentLock.markClosed(id)`. Job goes back to `pending` with no `next_retry_at` (worker will exit on next iteration's lock check). Bundle export runs in the background. |

### 6.4 Concurrency + claiming

`SyncJobsRepository.claimUpToN(n)` opens a Drift transaction:
1. SELECT up to N rows where `status='pending'` AND (`next_retry_at IS NULL` OR `next_retry_at <= now`) AND (`blocks_on_submission_id IS NULL` OR EXISTS submission with id=blocks_on_submission_id and sync_status='uploaded').
2. ORDER BY: `entity_type='submission'` first (so parents finish before dependent photos), then `created_at ASC`.
3. UPDATE selected rows to `status='in_progress'`.
4. Return claimed rows.

`SyncWorker.drain()` calls claim repeatedly until empty, processing each batch via `Future.wait` (true parallelism). The `_running` flag dedupes overlapping `triggerNow()` calls.

### 6.5 Retry schedule

`retry_schedule.dart` — pure:
```dart
DateTime? nextRetryAt(int attempts, {DateTime? now}) {
  final base = now ?? DateTime.now();
  return switch (attempts) {
    1 => base.add(const Duration(seconds: 30)),
    2 => base.add(const Duration(minutes: 2)),
    3 => base.add(const Duration(minutes: 10)),
    4 => base.add(const Duration(hours: 1)),
    _ => null, // dead after 5th attempt
  };
}
```

## 7. Triggers

### 7.1 Manual (Phase 4a debug long-press)

Hidden long-press gesture on a Home screen card. Calls:
```dart
SyncController.manualDrainNow()
  → for each ready_to_upload submission: FinalizeSubmissionUseCase.execute(id)
  → SyncController.triggerNow()
```

Replaced in Phase 4b by the Review screen's "Start Upload" button.

### 7.2 Connectivity-regained

`ConnectivityListener.start()` subscribes to `Connectivity().onConnectivityChanged`. On any transition to a non-`none` connectivity state, calls `controller.triggerNow()`. Started once at app launch from `main.dart`.

### 7.3 App-foregrounded

`SyncLifecycleListener.start()` registers an `AppLifecycleListener(onResume: () => controller.triggerNow())`. Started once at app launch.

### 7.4 WorkManager periodic ~15 min

`workmanager_dispatcher.dart` exposes a `@pragma('vm:entry-point')` `callbackDispatcher` that initializes Supabase + Drift in the background isolate, assembles a `SyncController`, and calls `controller.triggerNow()`.

`registerPeriodicSync()` is called from `main.dart` after `Supabase.initialize`:
```dart
await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
await Workmanager().registerPeriodicTask(
  'firecheck-sync-periodic',
  'firecheck.sync',
  frequency: const Duration(minutes: 15),
  constraints: Constraints(networkType: NetworkType.connected),
);
```

## 8. 409 assignment-closed-remotely + bundle export

### 8.1 Lock state

`AssignmentLockRepository`:
- `markClosed(assignmentId)` → UPDATE `assignments.closed_remotely=true`. Awaits the bundle export via `PendingWorkBundle.exportFor(id)` in the background.
- `isLocked()` → SELECT closed_remotely from assignments where id=current.
- `lockStateStream()` → Drift watch stream on the assignments row.

Worker checks `assignmentLock.isLocked()` at the top of every `drain()` loop iteration. If locked, returns immediately.

### 8.2 Bundle export

`PendingWorkBundle.exportFor(assignmentId)`:
1. Gets `getDownloadsDirectory()` (or app docs as fallback).
2. Path: `firecheck-pending-<assignmentId>-<timestamp>.zip`.
3. Builds `Archive`:
   - `data.json` — JSON dump of all unsynced submissions + their attrs + household_surveys + photos metadata + new features.
   - `photos/<photo_id>.jpg` — copies each unsynced photo file's bytes.
4. Encodes with `ZipEncoder().encode(archive)`.
5. Writes to file; returns `File`.

Phase 4a writes the file proactively when the lock fires. Phase 4b's UI surfaces the file path via the lock stream and offers the share-sheet.

## 9. Riverpod wiring

`sync_providers.dart`:
```dart
final syncApiProvider = Provider<SyncApi>((ref) => SupabaseSyncApi(...));
final syncJobsRepositoryProvider = Provider((ref) => SyncJobsRepository(ref.watch(appDatabaseProvider)));
final assignmentLockRepositoryProvider = Provider((ref) => AssignmentLockRepository(ref.watch(appDatabaseProvider)));
final syncWorkerProvider = Provider((ref) => SyncWorker(
  api: ref.watch(syncApiProvider),
  repo: ref.watch(syncJobsRepositoryProvider),
  payload: SubmissionPayloadBuilder(ref.watch(appDatabaseProvider)),
  assignmentLock: ref.watch(assignmentLockRepositoryProvider),
));
final syncControllerProvider = Provider((ref) {
  final controller = SyncController(worker: ref.watch(syncWorkerProvider));
  ref.onDispose(controller.stop);
  return controller;
});
```

`main.dart` wiring:
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Supabase.initialize(...);
  await registerPeriodicSync();
  runApp(const ProviderScope(child: FireCheckApp()));
}
```

`FireCheckApp` reads `syncControllerProvider`, calls `controller.start()` (spins up Connectivity + Lifecycle listeners + initial drain) inside `initState` of a top-level wrapper.

## 10. Testing strategy

### 10.1 Unit tests (no Flutter deps)

- `retry_schedule` boundary cases: attempts 1–4 → expected durations; ≥5 → null. 5 tests.
- `sync_outcome` sealed class equality + sub-type identity. 4 tests.
- `submission_payload_builder` — JSON shape for building, road, building+OLP, road-no-OLP. ~6 tests.
- `pending_work_bundle` — pure data.json content for known unsynced fixtures.

### 10.2 Repository tests (NativeDatabase.memory + FK chain)

- `SyncJobsRepository.claimUpToN` — claims N pending; respects next_retry_at; respects blocks_on_submission_id; orders submission jobs first; atomic claim under concurrent calls.
- `SyncJobsRepository.markSuccess/markPendingRetry/markDead` — state transitions persist correctly.
- `FinalizeSubmissionUseCase.execute` — atomic transaction; idempotent re-execution; rolls back on simulated failure.
- `AssignmentLockRepository` — markClosed + isLocked + stream emissions.

### 10.3 Worker tests (FakeSyncApi)

- Success → job marked success, submission row updated.
- TransientFailure → attempts++, next_retry_at scheduled.
- 5th TransientFailure → marked dead.
- PermanentFailure (4xx) → marked dead immediately.
- AuthExpired → refreshSession called (mocked), retry inline.
- AuthExpired → AuthExpired (loop) → treated as transient.
- AssignmentClosed → AssignmentLock marked, worker loop exits.
- Photo job blocked by parent submission status — claimed only after parent uploaded.
- Concurrent drain calls deduped.
- Max 3 concurrent enforced.

### 10.4 Integration

- `ConnectivityListener` — fake Connectivity stream; assert `controller.triggerNow()` fires on online transitions.
- `SyncLifecycleListener` — fake `AppLifecycleListener.onResume` → trigger fires.
- WorkManager: skip automated test; verify via manual happy path + `adb logcat | grep WorkManager`.

### 10.5 End-to-end (manual happy path on Pixel 7 emulator)

1. Survey a building with a photo. Tap Done → `ready_to_upload`.
2. Disable network. Long-press Home debug trigger → outbox writes sync_jobs → worker fails with TransientFailure → jobs go to pending with next_retry_at.
3. Re-enable network. ConnectivityListener fires → worker drains → submission then photo upload.
4. Inspect Supabase admin UI: row in submissions, file in Storage, photos.storage_path set.
5. Force-stop 16 minutes. WorkManager periodic tick fires (visible in logcat).
6. Server-side flip `assignments.closed_remotely=true`, trigger another drain → 409 → AssignmentLock fires → bundle file appears in Downloads.

### 10.6 Acceptance gate

- `flutter analyze` clean.
- `flutter test` ≥ 220 passing (Phase 3b ended at 191; Phase 4a adds ~30+ tests).
- `flutter build apk --debug` succeeds.
- Manual happy path completes end-to-end on the emulator.
- Tag `phase-4a-sync-engine` (push remains user-gated).

## 11. Conventions reused

- Drift codegen via `dart run build_runner build --delete-conflicting-outputs`.
- Riverpod 2.5 with `Provider` for services + `StateNotifierProvider` where stream-shaped state is needed.
- Sealed classes for state machines (`SyncOutcome`).
- `very_good_analysis` lint set; project-wide overrides preserved.
- `subagent-driven-development` for plan execution.
- Commit format `<type>(<scope>): <subject>` + Claude trailer.
- AppDatabase-inside-testWidgets-body for widget tests (none expected in 4a).
- FK chain test seeding (assignments → features → submissions → photos → sync_jobs).
- `submittedBy` (NOT `enumeratorId`) on `SubmissionsCompanion.insert`.
- No automatic push; tagging happens at the final task; user pushes manually.

## 12. Risks documented

- **OEM background-kill policies** (Xiaomi, Vivo, Oppo, Realme, Huawei). WorkManager may not fire on aggressive OEMs. Mitigation: connectivity + foreground triggers work regardless of OEM. Document only; no code action.
- **Auth refresh race** — concurrent 401s both call `refreshSession()`. Supabase SDK serializes refresh; both jobs get the new token. Document; revisit if observed flakiness.
- **Photo file deleted between capture and upload** — `FileNotFoundException` → PermanentFailure → photo job dies. Photo row stays with `upload_status='failed'`; surfaced in Phase 4b's review screen.
- **Bundle-export ZIP size** — assignment with 100 buildings × 3 photos × ~200KB ≈ 60MB. Acceptable for share-sheet; slow to build. Profile if seen in pilot.
- **`closedRemotely` discovery latency** — queue learns about a closed assignment only when it next tries to upload. Acceptable per spec; supervisors are expected to coordinate.

## 13. Open items / Phase 4b dependencies

- Phase 4b will replace the debug long-press trigger with the real "Start Upload" button on the Review screen.
- Phase 4b will surface the bundle file path via `assignmentLockRepository.lockStateStream()` and add the share-sheet button.
- Phase 4b will read `syncJobsRepository` status to render per-submission progress in the Review screen.
- Phase 4b will set `assignments.submitted_at` after all sync_jobs complete and lock the UI.
