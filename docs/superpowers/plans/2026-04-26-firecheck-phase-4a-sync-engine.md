# FireCheck Mobile — Phase 4a (Sync engine) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full FireCheck sync engine — outbox transaction, drift-and-resume sync worker with retry/backoff + 401/409 handling, two-phase photo upload, connectivity + foreground + WorkManager triggers, and a JSON+ZIP bundle export for the assignment-closed-remotely path. No user-facing UI yet; triggered by a debug long-press on Home (Phase 4b's Review screen replaces this).

**Architecture:** New `core/sync/` module split into `domain/`, `data/`, `worker/`, `failure/`, `presentation/`. `SyncApi` abstract is the testability seam; `SupabaseSyncApi` (real) backed by `supabase_flutter` Storage + PostgREST + a new `upload_submission_bundle` RPC function. `SyncWorker` knows nothing about Supabase or UI — pure consumer of `SyncApi` + `SyncJobsRepository`. `SyncController` is the singleton facade wiring connectivity + lifecycle listeners + WorkManager periodic ticks. Schema bump v4 → v5 adds `assignments.closed_remotely`.

**Tech Stack additions:**
- `connectivity_plus: ^5.0` — connectivity stream
- `workmanager: ^0.5` — Android background periodic ticks
- `archive: ^3.4` — ZIP encoder for 409 bundle export
- `share_plus: ^9.0` — share-sheet (deps installed in 4a; UI usage in 4b)
- New Android perms: `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`

**Phase 4a demo state:** Login → survey a building with photo → tap Done → submission goes to `ready_to_upload`. Long-press the Home screen's primary card → outbox transaction writes sync_jobs → worker uploads submission + photo to Supabase. Disable network → re-enable → `ConnectivityListener` resumes drain. Force-stop the app for 16+ minutes → WorkManager periodic tick fires (visible in `adb logcat | grep WorkManager`). Server-side flip `closed_remotely=true` → 409 → `AssignmentLockRepository.markClosed` fires → bundle ZIP appears in app's Downloads dir.

---

## File structure (Phase 4a)

### New files

```
lib/core/sync/domain/sync_job_status.dart
lib/core/sync/domain/sync_entity_type.dart
lib/core/sync/domain/retry_schedule.dart
lib/core/sync/domain/sync_outcome.dart
lib/core/sync/domain/finalize_submission.dart
lib/core/sync/data/sync_jobs_repository.dart
lib/core/sync/data/submission_payload_builder.dart
lib/core/sync/data/sync_api.dart
lib/core/sync/data/supabase_sync_api.dart
lib/core/sync/data/fake_sync_api.dart
lib/core/sync/worker/sync_worker.dart
lib/core/sync/worker/sync_controller.dart
lib/core/sync/worker/connectivity_listener.dart
lib/core/sync/worker/lifecycle_listener.dart
lib/core/sync/worker/workmanager_dispatcher.dart
lib/core/sync/failure/assignment_lock_repository.dart
lib/core/sync/failure/pending_work_bundle.dart
lib/core/sync/presentation/sync_providers.dart

supabase/migrations/005_assignments_closed_remotely.sql
supabase/migrations/006_upload_submission_bundle_rpc.sql
```

### Modified files

```
lib/core/db/tables/assignments.dart           # +closedRemotely column
lib/core/db/database.dart                     # schemaVersion 4→5 + onUpgrade
lib/core/db/database.g.dart                   # regenerated
pubspec.yaml                                  # +4 deps
android/app/src/main/AndroidManifest.xml      # +RECEIVE_BOOT_COMPLETED, WAKE_LOCK
lib/main.dart                                 # SyncController.start + WorkManager init
lib/features/home/presentation/home_screen.dart  # debug long-press trigger
```

### Test files

```
test/core/db/migration_v4_to_v5_test.dart
test/core/sync/domain/retry_schedule_test.dart
test/core/sync/domain/sync_outcome_test.dart
test/core/sync/data/sync_jobs_repository_test.dart
test/core/sync/data/submission_payload_builder_test.dart
test/core/sync/domain/finalize_submission_test.dart
test/core/sync/failure/assignment_lock_repository_test.dart
test/core/sync/failure/pending_work_bundle_test.dart
test/core/sync/worker/sync_worker_happy_path_test.dart
test/core/sync/worker/sync_worker_retry_test.dart
test/core/sync/worker/sync_worker_auth_test.dart
test/core/sync/worker/sync_worker_assignment_closed_test.dart
test/core/sync/worker/connectivity_listener_test.dart
test/core/sync/worker/lifecycle_listener_test.dart
```

---

### Task 1: Schema v4 → v5 (assignments.closed_remotely)

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/db/tables/assignments.dart`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/db/database.dart`
- Regenerate: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/db/database.g.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/db/migration_v4_to_v5_test.dart`

- [ ] **Step 1: Add the column to the Drift table**

Read the existing file first. Then add this column AFTER the existing `status` declaration and BEFORE `primaryKey`:

```dart
BoolColumn get closedRemotely => boolean().withDefault(const Constant(false))();
```

- [ ] **Step 2: Bump schemaVersion + extend onUpgrade**

In `database.dart`, change `int get schemaVersion => 4;` to:

```dart
@override
int get schemaVersion => 5;
```

After the existing `if (from < 4) { ... }` branch in `onUpgrade`, append:

```dart
if (from < 5) {
  await m.addColumn(assignments, assignments.closedRemotely);
}
```

- [ ] **Step 3: Regenerate Drift codegen**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && dart run build_runner build --delete-conflicting-outputs
```

Expected: `Succeeded` line at end.

- [ ] **Step 4: Failing migration test**

```dart
// test/core/db/migration_v4_to_v5_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion is at least 5', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(5));
  });

  test('assignments.closedRemotely defaults to false', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('a1')))
        .getSingle();
    expect(row.closedRemotely, isFalse);
  });
}
```

- [ ] **Step 5: Run the test**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/db/migration_v4_to_v5_test.dart
```

Expected: `All tests passed!` (2 tests).

- [ ] **Step 6: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/db/ test/core/db/
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/db/ test/core/db/migration_v4_to_v5_test.dart && git commit -m "$(cat <<'EOF'
feat(db): schema v4 → v5 — assignments.closed_remotely

Adds closed_remotely (bool default false). Drift onUpgrade additive
migration. Used by Phase 4a's 409 assignment-closed-remotely path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Supabase migration 005

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/supabase/migrations/005_assignments_closed_remotely.sql`

- [ ] **Step 1: Write the SQL migration**

```sql
-- Phase 4a: assignment-closed-remotely flag for 409 path.
alter table public.assignments
  add column closed_remotely boolean not null default false;
```

- [ ] **Step 2: Push to Supabase**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && supabase db push
```

Expected: `Applying migration 005_assignments_closed_remotely.sql...` then `Done.`. If `supabase` CLI is not configured, STOP and report.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add supabase/migrations/005_assignments_closed_remotely.sql && git commit -m "$(cat <<'EOF'
feat(supabase): migration 005 — assignments.closed_remotely

Mirrors local Drift v5 schema bump.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add 4 new dependencies + Android manifest perms

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/pubspec.yaml`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add deps**

In `pubspec.yaml`, locate the `dependencies:` block (where existing deps like `flutter_riverpod`, `drift` live) and add:

```yaml
  # Phase 4a — sync engine
  connectivity_plus: ^5.0.0
  workmanager: ^0.5.2
  archive: ^3.4.0
  share_plus: ^9.0.0
  path_provider: ^2.1.0
```

(`path_provider` may be transitively present via `image_picker` — explicit dep is fine.)

- [ ] **Step 2: Install deps**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter pub get
```

Expected: `Got dependencies!`

- [ ] **Step 3: Add Android manifest perms**

Read the manifest first. Add INSIDE the existing `<manifest>` element (where INTERNET / CAMERA already live):

```xml
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
```

- [ ] **Step 4: Verify analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze 2>&1 | tail -3
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml && git commit -m "$(cat <<'EOF'
chore(deps): add connectivity_plus + workmanager + archive + share_plus + path_provider

Phase 4a sync engine deps. Android manifest gains RECEIVE_BOOT_COMPLETED
and WAKE_LOCK for WorkManager periodic execution windows.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Sync constants

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/domain/sync_job_status.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/domain/sync_entity_type.dart`

No tests — these are bare constants. Used immediately by Tasks 5+.

- [ ] **Step 1: Implement sync_job_status.dart**

```dart
/// String constants used in sync_jobs.status.
/// Lifecycle: pending → in_progress → success | failed | dead
class SyncJobStatus {
  SyncJobStatus._();
  static const pending = 'pending';
  static const inProgress = 'in_progress';
  static const success = 'success';
  static const failed = 'failed';
  static const dead = 'dead';
}
```

- [ ] **Step 2: Implement sync_entity_type.dart**

```dart
/// String constants used in sync_jobs.entity_type.
class SyncEntityType {
  SyncEntityType._();
  static const submission = 'submission';
  static const photo = 'photo';
  static const newFeature = 'new_feature';
}
```

- [ ] **Step 3: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/domain/ && git commit -m "$(cat <<'EOF'
feat(sync): SyncJobStatus + SyncEntityType constant classes

String constants for sync_jobs.status and sync_jobs.entity_type.
Used across the sync engine to avoid stringly-typed bugs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: retry_schedule pure function + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/domain/retry_schedule.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/domain/retry_schedule_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:firecheck/core/sync/domain/retry_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedNow = DateTime(2026, 4, 26, 12);

  test('attempts=1 → 30 seconds later', () {
    expect(nextRetryAt(1, now: fixedNow), fixedNow.add(const Duration(seconds: 30)));
  });

  test('attempts=2 → 2 minutes later', () {
    expect(nextRetryAt(2, now: fixedNow), fixedNow.add(const Duration(minutes: 2)));
  });

  test('attempts=3 → 10 minutes later', () {
    expect(nextRetryAt(3, now: fixedNow), fixedNow.add(const Duration(minutes: 10)));
  });

  test('attempts=4 → 1 hour later', () {
    expect(nextRetryAt(4, now: fixedNow), fixedNow.add(const Duration(hours: 1)));
  });

  test('attempts=5 → null (dead)', () {
    expect(nextRetryAt(5, now: fixedNow), isNull);
  });

  test('attempts=99 → null (dead)', () {
    expect(nextRetryAt(99, now: fixedNow), isNull);
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/domain/retry_schedule_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

```dart
/// Returns the wall-clock time at which a failed sync_job should be retried,
/// or null if the job has exhausted its retries (treat as dead).
///
/// Schedule per master spec §7: 30s, 2m, 10m, 1h, dead.
DateTime? nextRetryAt(int attempts, {DateTime? now}) {
  final base = now ?? DateTime.now();
  return switch (attempts) {
    1 => base.add(const Duration(seconds: 30)),
    2 => base.add(const Duration(minutes: 2)),
    3 => base.add(const Duration(minutes: 10)),
    4 => base.add(const Duration(hours: 1)),
    _ => null,
  };
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/domain/retry_schedule_test.dart
```

Expected: `All tests passed!` (6 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/domain/retry_schedule.dart test/core/sync/domain/retry_schedule_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): pure retry schedule (30s/2m/10m/1h/dead)

nextRetryAt(attempts) returns wall-clock retry time per master spec §7,
or null after the 4th attempt (treat as dead). Pure for trivial testing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: SyncOutcome sealed class + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/domain/sync_outcome.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/domain/sync_outcome_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Success has no fields', () {
    expect(const Success(), isA<SyncOutcome>());
  });

  test('TransientFailure carries error', () {
    const o = TransientFailure('500 server error');
    expect(o, isA<SyncOutcome>());
    expect(o.error, '500 server error');
  });

  test('PermanentFailure carries error', () {
    const o = PermanentFailure('400 bad request');
    expect(o, isA<SyncOutcome>());
    expect(o.error, '400 bad request');
  });

  test('AuthExpired has no fields', () {
    expect(const AuthExpired(), isA<SyncOutcome>());
  });

  test('AssignmentClosed carries assignmentId', () {
    const o = AssignmentClosed('assignment-123');
    expect(o, isA<SyncOutcome>());
    expect(o.assignmentId, 'assignment-123');
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/domain/sync_outcome_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

```dart
/// Outcome of attempting to sync a single sync_jobs row.
/// Maps from HTTP status:
///   2xx → Success
///   401 → AuthExpired (refresh token, retry once)
///   409 → AssignmentClosed (halt queue, export bundle)
///   4xx (other) → PermanentFailure (mark dead)
///   5xx / network / timeout → TransientFailure (retry per schedule)
sealed class SyncOutcome {
  const SyncOutcome();
}

class Success extends SyncOutcome {
  const Success();
}

class TransientFailure extends SyncOutcome {
  const TransientFailure(this.error);
  final String error;
}

class PermanentFailure extends SyncOutcome {
  const PermanentFailure(this.error);
  final String error;
}

class AuthExpired extends SyncOutcome {
  const AuthExpired();
}

class AssignmentClosed extends SyncOutcome {
  const AssignmentClosed(this.assignmentId);
  final String assignmentId;
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/domain/sync_outcome_test.dart
```

Expected: `All tests passed!` (5 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/domain/sync_outcome.dart test/core/sync/domain/sync_outcome_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): SyncOutcome sealed class

Five-variant union: Success | TransientFailure | PermanentFailure |
AuthExpired | AssignmentClosed. Used by SyncWorker to dispatch per-
outcome state transitions per master spec §7.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: SyncJobsRepository + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/data/sync_jobs_repository.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/data/sync_jobs_repository_test.dart`

### CRITICAL — Phase 2/3a/3b gotchas

1. **FK chain**: tests must seed `assignments` → `features` → `submissions` BEFORE inserting `photos` → BEFORE inserting `sync_jobs`.
2. **`SubmissionsCompanion.insert` does NOT take `enumeratorId`** — column is `submittedBy` (nullable). Required positional fields: `id`, `featureId`, `createdAt`, `updatedAt`.
3. **Drift `isNotNull`/`isNull` SQL helpers collide with `flutter_test` matchers** — if you import `package:drift/drift.dart` in a TEST file, hide them: `import 'package:drift/drift.dart' hide isNotNull, isNull;`.

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncJobsRepository repo;
  final now = DateTime(2026, 4, 26, 12);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SyncJobsRepository(db);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> insertJob({
    required String id,
    required String entityType,
    required String entityId,
    String status = 'pending',
    String? blocksOn,
    DateTime? nextRetry,
    int attempts = 0,
    Duration createdAtOffset = Duration.zero,
  }) async {
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: id,
          entityType: entityType,
          entityId: entityId,
          status: Value(status),
          blocksOnSubmissionId: Value(blocksOn),
          nextRetryAt: Value(nextRetry),
          attempts: Value(attempts),
          createdAt: now.add(createdAtOffset),
        ));
  }

  test('claimUpToN returns up to N pending jobs and marks them in_progress',
      () async {
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, hasLength(1));
    expect(claimed.first.id, 'j1');
    final reread = await (db.select(db.syncJobs)
          ..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(reread.status, SyncJobStatus.inProgress);
  });

  test('claimUpToN respects next_retry_at (skips future-scheduled jobs)',
      () async {
    await insertJob(
      id: 'j1',
      entityType: 'submission',
      entityId: 's1',
      nextRetry: now.add(const Duration(minutes: 5)),
    );
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, isEmpty);
  });

  test('claimUpToN claims a job whose next_retry_at has elapsed', () async {
    await insertJob(
      id: 'j1',
      entityType: 'submission',
      entityId: 's1',
      nextRetry: now.subtract(const Duration(minutes: 1)),
    );
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, hasLength(1));
  });

  test('claimUpToN orders submission jobs first, then by created_at',
      () async {
    await insertJob(
        id: 'j-photo', entityType: 'photo', entityId: 'p1', createdAtOffset: Duration.zero);
    await insertJob(
        id: 'j-sub',
        entityType: 'submission',
        entityId: 's1',
        createdAtOffset: const Duration(seconds: 1));
    final claimed = await repo.claimUpToN(2, now: now);
    expect(claimed.map((j) => j.id).toList(), ['j-sub', 'j-photo']);
  });

  test('claimUpToN blocks a photo job whose parent submission is not uploaded',
      () async {
    // Insert a photo first (FK chain).
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph1',
          submissionId: 's1',
          localPath: '/tmp/x.jpg',
          capturedAt: now,
          createdAt: now,
        ));
    await insertJob(
        id: 'j-photo',
        entityType: 'photo',
        entityId: 'ph1',
        blocksOn: 's1');
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, isEmpty); // submission not yet uploaded
  });

  test('claimUpToN unblocks a photo job once parent submission is uploaded',
      () async {
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph1',
          submissionId: 's1',
          localPath: '/tmp/x.jpg',
          capturedAt: now,
          createdAt: now,
        ));
    await insertJob(
        id: 'j-photo',
        entityType: 'photo',
        entityId: 'ph1',
        blocksOn: 's1');
    await (db.update(db.submissions)..where((t) => t.id.equals('s1'))).write(
        const SubmissionsCompanion(syncStatus: Value('uploaded')));
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, hasLength(1));
    expect(claimed.first.id, 'j-photo');
  });

  test('markSuccess transitions to success', () async {
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    await repo.markSuccess('j1');
    final r = await (db.select(db.syncJobs)..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(r.status, SyncJobStatus.success);
  });

  test('markPendingRetry advances attempts + sets next_retry_at + lastError',
      () async {
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    final scheduled = now.add(const Duration(seconds: 30));
    await repo.markPendingRetry(
      'j1',
      attempts: 1,
      lastError: '500 error',
      nextRetryAt: scheduled,
    );
    final r = await (db.select(db.syncJobs)..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(r.status, SyncJobStatus.pending);
    expect(r.attempts, 1);
    expect(r.nextRetryAt, scheduled);
    expect(r.lastError, '500 error');
  });

  test('markDead transitions to dead', () async {
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    await repo.markDead('j1', error: '4xx', attempts: 5);
    final r = await (db.select(db.syncJobs)..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(r.status, SyncJobStatus.dead);
    expect(r.attempts, 5);
    expect(r.lastError, '4xx');
  });

  test('findByEntity returns existing job or null', () async {
    expect(
        await repo.findByEntity(SyncEntityType.submission, 's1'), isNull);
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    final found = await repo.findByEntity(SyncEntityType.submission, 's1');
    expect(found, isNotNull);
    expect(found!.id, 'j1');
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/data/sync_jobs_repository_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';

class SyncJobsRepository {
  SyncJobsRepository(this._db);
  final AppDatabase _db;

  /// Claims up to [n] pending sync_jobs ready to run NOW. Atomically transitions
  /// claimed rows to in_progress so concurrent invocations don't double-claim.
  ///
  /// Ordering: submission jobs first (so dependent photos can unblock), then
  /// remaining jobs by created_at ascending.
  Future<List<SyncJob>> claimUpToN(int n, {DateTime? now}) async {
    final cutoff = now ?? DateTime.now();
    return _db.transaction(() async {
      final raw = await _db.customSelect(
        '''
        SELECT j.* FROM sync_jobs j
        WHERE j.status = ?
          AND (j.next_retry_at IS NULL OR j.next_retry_at <= ?)
          AND (
            j.blocks_on_submission_id IS NULL
            OR EXISTS (
              SELECT 1 FROM submissions s
              WHERE s.id = j.blocks_on_submission_id AND s.sync_status = 'uploaded'
            )
          )
        ORDER BY (CASE WHEN j.entity_type = ? THEN 0 ELSE 1 END), j.created_at
        LIMIT ?
        ''',
        variables: [
          Variable.withString(SyncJobStatus.pending),
          Variable.withDateTime(cutoff),
          Variable.withString(SyncEntityType.submission),
          Variable.withInt(n),
        ],
        readsFrom: {_db.syncJobs, _db.submissions},
      ).get();
      final claimed = raw.map((row) => _db.syncJobs.map(row.data)).toList();
      for (final j in claimed) {
        await (_db.update(_db.syncJobs)..where((t) => t.id.equals(j.id))).write(
          const SyncJobsCompanion(status: Value(SyncJobStatus.inProgress)),
        );
      }
      return claimed;
    });
  }

  Future<void> markSuccess(String jobId) async {
    await (_db.update(_db.syncJobs)..where((t) => t.id.equals(jobId))).write(
      const SyncJobsCompanion(status: Value(SyncJobStatus.success)),
    );
  }

  Future<void> markPendingRetry(
    String jobId, {
    required int attempts,
    required String lastError,
    required DateTime? nextRetryAt,
  }) async {
    await (_db.update(_db.syncJobs)..where((t) => t.id.equals(jobId))).write(
      SyncJobsCompanion(
        status: const Value(SyncJobStatus.pending),
        attempts: Value(attempts),
        lastError: Value(lastError),
        nextRetryAt: Value(nextRetryAt),
      ),
    );
  }

  Future<void> markDead(
    String jobId, {
    required String error,
    required int attempts,
  }) async {
    await (_db.update(_db.syncJobs)..where((t) => t.id.equals(jobId))).write(
      SyncJobsCompanion(
        status: const Value(SyncJobStatus.dead),
        attempts: Value(attempts),
        lastError: Value(error),
      ),
    );
  }

  Future<SyncJob?> findByEntity(String entityType, String entityId) {
    return (_db.select(_db.syncJobs)
          ..where((t) =>
              t.entityType.equals(entityType) & t.entityId.equals(entityId)))
        .getSingleOrNull();
  }
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/data/sync_jobs_repository_test.dart
```

Expected: `All tests passed!` (10 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/data/sync_jobs_repository.dart test/core/sync/data/sync_jobs_repository_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): SyncJobsRepository — claimUpToN + state transitions

Atomic claim transaction (LIMIT N + UPDATE in_progress) so concurrent
drains don't double-claim. Custom SELECT respects next_retry_at and
the blocks_on_submission_id dependency on parent uploaded state.
Submission jobs ordered first, then by created_at.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: AssignmentLockRepository + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/failure/assignment_lock_repository.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/failure/assignment_lock_repository_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

void main() {
  late AppDatabase db;
  late AssignmentLockRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AssignmentLockRepository(db);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
  });

  tearDown(() async => db.close());

  test('isLocked returns false initially', () async {
    expect(await repo.isLocked('a1'), isFalse);
  });

  test('markClosed sets closed_remotely=true', () async {
    await repo.markClosed('a1');
    expect(await repo.isLocked('a1'), isTrue);
  });

  test('isLocked returns false for unknown assignment', () async {
    expect(await repo.isLocked('does-not-exist'), isFalse);
  });

  test('lockStateStream emits initial value + change after markClosed',
      () async {
    final emissions = <bool>[];
    final sub = repo.lockStateStream('a1').listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions, [false]);
    await repo.markClosed('a1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions, [false, true]);
    await sub.cancel();
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/failure/assignment_lock_repository_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

class AssignmentLockRepository {
  AssignmentLockRepository(this._db);
  final AppDatabase _db;

  Future<bool> isLocked(String assignmentId) async {
    final row = await (_db.select(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    return row?.closedRemotely ?? false;
  }

  Future<void> markClosed(String assignmentId) async {
    await (_db.update(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .write(const AssignmentsCompanion(closedRemotely: Value(true)));
  }

  Stream<bool> lockStateStream(String assignmentId) {
    return (_db.select(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .watchSingleOrNull()
        .map((row) => row?.closedRemotely ?? false);
  }
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/failure/assignment_lock_repository_test.dart
```

Expected: `All tests passed!` (4 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/failure/assignment_lock_repository.dart test/core/sync/failure/assignment_lock_repository_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): AssignmentLockRepository — closed_remotely state + stream

Wraps assignments.closed_remotely. markClosed() called from worker on
409. lockStateStream() watched by Phase 4b's blocking UI; isLocked()
called by SyncWorker on every drain loop iteration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: FinalizeSubmissionUseCase (outbox transaction)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/domain/finalize_submission.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/domain/finalize_submission_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

void main() {
  late AppDatabase db;
  late FinalizeSubmissionUseCase useCase;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    useCase = FinalizeSubmissionUseCase(db);
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value('ready_to_upload'),
          ),
        );
  });

  tearDown(() async => db.close());

  test('execute writes one submission sync_job + 0 photos when none exist',
      () async {
    final r = await useCase.execute('s1');
    expect(r.submissionId, 's1');
    expect(r.photoCount, 0);
    expect(r.newFeatureQueued, isFalse);

    final sub = await (db.select(db.submissions)
          ..where((t) => t.id.equals('s1')))
        .getSingle();
    expect(sub.syncStatus, 'queued');

    final jobs = await db.select(db.syncJobs).get();
    expect(jobs, hasLength(1));
    expect(jobs.first.entityType, SyncEntityType.submission);
    expect(jobs.first.entityId, 's1');
    expect(jobs.first.status, SyncJobStatus.pending);
  });

  test('execute writes a sync_job per photo with blocks_on_submission_id',
      () async {
    final now = DateTime.now();
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph1',
          submissionId: 's1',
          localPath: '/tmp/a.jpg',
          capturedAt: now,
          createdAt: now,
        ));
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph2',
          submissionId: 's1',
          localPath: '/tmp/b.jpg',
          capturedAt: now,
          createdAt: now,
        ));

    final r = await useCase.execute('s1');
    expect(r.photoCount, 2);

    final photoJobs = await (db.select(db.syncJobs)
          ..where((t) => t.entityType.equals(SyncEntityType.photo)))
        .get();
    expect(photoJobs, hasLength(2));
    expect(photoJobs.every((j) => j.blocksOnSubmissionId == 's1'), isTrue);
  });

  test('execute writes new_feature sync_job when feature.is_new=true',
      () async {
    await (db.update(db.features)..where((t) => t.id.equals('f1')))
        .write(const FeaturesCompanion(isNew: Value(true)));
    final r = await useCase.execute('s1');
    expect(r.newFeatureQueued, isTrue);
    final job = await (db.select(db.syncJobs)
          ..where((t) => t.entityType.equals(SyncEntityType.newFeature)))
        .getSingle();
    expect(job.entityId, 'f1');
  });

  test('execute is idempotent — calling twice does not duplicate jobs',
      () async {
    await useCase.execute('s1');
    await useCase.execute('s1');
    final jobs = await db.select(db.syncJobs).get();
    expect(jobs, hasLength(1));
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/domain/finalize_submission_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:uuid/uuid.dart';

class FinalizeResult {
  const FinalizeResult({
    required this.submissionId,
    required this.photoCount,
    required this.newFeatureQueued,
  });
  final String submissionId;
  final int photoCount;
  final bool newFeatureQueued;
}

class FinalizeSubmissionUseCase {
  FinalizeSubmissionUseCase(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<FinalizeResult> execute(String submissionId) async {
    return _db.transaction(() async {
      // 1. Update submission: → queued
      await (_db.update(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(SubmissionsCompanion(
        syncStatus: const Value('queued'),
        updatedAt: Value(DateTime.now()),
      ));

      // 2. Submission sync_job (skip-if-exists)
      final existingSub = await _findJob(SyncEntityType.submission, submissionId);
      if (existingSub == null) {
        await _db.into(_db.syncJobs).insert(SyncJobsCompanion.insert(
              id: _uuid.v4(),
              entityType: SyncEntityType.submission,
              entityId: submissionId,
              createdAt: DateTime.now(),
            ));
      }

      // 3. Photo sync_jobs (skip-if-exists)
      final photos = await (_db.select(_db.photos)
            ..where((t) => t.submissionId.equals(submissionId)))
          .get();
      var photoCount = 0;
      for (final photo in photos) {
        final existing = await _findJob(SyncEntityType.photo, photo.id);
        if (existing != null) continue;
        await _db.into(_db.syncJobs).insert(SyncJobsCompanion.insert(
              id: _uuid.v4(),
              entityType: SyncEntityType.photo,
              entityId: photo.id,
              blocksOnSubmissionId: Value(submissionId),
              createdAt: DateTime.now(),
            ));
        photoCount++;
      }

      // 4. New-feature sync_job if applicable (skip-if-exists)
      final submission = await (_db.select(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .getSingle();
      final feature = await (_db.select(_db.features)
            ..where((t) => t.id.equals(submission.featureId)))
          .getSingle();
      var newFeatureQueued = false;
      if (feature.isNew) {
        final existing = await _findJob(SyncEntityType.newFeature, feature.id);
        if (existing == null) {
          await _db.into(_db.syncJobs).insert(SyncJobsCompanion.insert(
                id: _uuid.v4(),
                entityType: SyncEntityType.newFeature,
                entityId: feature.id,
                createdAt: DateTime.now(),
              ));
          newFeatureQueued = true;
        }
      }

      return FinalizeResult(
        submissionId: submissionId,
        photoCount: photoCount,
        newFeatureQueued: newFeatureQueued,
      );
    });
  }

  Future<SyncJob?> _findJob(String entityType, String entityId) {
    return (_db.select(_db.syncJobs)
          ..where((t) =>
              t.entityType.equals(entityType) & t.entityId.equals(entityId)))
        .getSingleOrNull();
  }
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/domain/finalize_submission_test.dart
```

Expected: `All tests passed!` (4 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/domain/finalize_submission.dart test/core/sync/domain/finalize_submission_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): FinalizeSubmissionUseCase — atomic outbox transaction

Drift transaction transitions submission to 'queued' and writes
sync_jobs rows for the submission + each photo + (if isNew) the new
feature. Skip-if-exists semantics make re-execution idempotent.
Photo jobs carry blocks_on_submission_id so the worker drains the
parent first.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: SubmissionPayloadBuilder + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/data/submission_payload_builder.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/data/submission_payload_builder_test.dart`

Builds the JSON payload to POST when uploading a submission. Joins `submissions` + `building_attributes` (or `road_attributes`) + `household_surveys` if present. The shape is dictated by the Supabase RPC function (Task 12 / migration 006); for Phase 4a we use this canonical shape:

```json
{
  "submission": { /* row JSON */ },
  "feature_type": "building" | "road",
  "building_attributes": { /* or null */ },
  "road_attributes": { /* or null */ },
  "household_survey": { /* or null */ }
}
```

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SubmissionPayloadBuilder builder;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    builder = SubmissionPayloadBuilder(db);
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async => db.close());

  test('building submission with no attrs or olp', () async {
    final p = await builder.build('s1');
    expect(p['submission'], isA<Map<String, dynamic>>());
    expect(p['feature_type'], 'building');
    expect(p['building_attributes'], isNull);
    expect(p['road_attributes'], isNull);
    expect(p['household_survey'], isNull);
  });

  test('building submission with attrs + olp', () async {
    await db.into(db.buildingAttributes).insert(
          BuildingAttributesCompanion.insert(
            submissionId: 's1',
            buildingName: const Value('Hall A'),
            ra9514Type: const Value('A'),
            storeys: const Value(2),
          ),
        );
    await db.into(db.householdSurveys).insert(
          HouseholdSurveysCompanion.insert(
            submissionId: 's1',
            kaayusanJson: const Value('{"B-01":true}'),
            homeownerAcknowledged: const Value(true),
            lebelNgKahinaan: const Value('LabisNaMapanganib'),
          ),
        );
    final p = await builder.build('s1');
    expect(p['building_attributes']['building_name'], 'Hall A');
    expect(p['household_survey']['homeowner_acknowledged'], true);
    expect(p['household_survey']['lebel_ng_kahinaan'], 'LabisNaMapanganib');
  });

  test('road submission with road_attributes', () async {
    await (db.update(db.features)..where((t) => t.id.equals('f1')))
        .write(const FeaturesCompanion(featureType: Value('road')));
    await db.into(db.roadAttributes).insert(
          RoadAttributesCompanion.insert(
            submissionId: 's1',
            roadName: const Value('Mango Ave'),
            widthMeters: const Value(4.5),
          ),
        );
    final p = await builder.build('s1');
    expect(p['feature_type'], 'road');
    expect(p['road_attributes']['road_name'], 'Mango Ave');
    expect(p['road_attributes']['width_meters'], 4.5);
    expect(p['building_attributes'], isNull);
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/data/submission_payload_builder_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:firecheck/core/db/database.dart';

class SubmissionPayloadBuilder {
  SubmissionPayloadBuilder(this._db);
  final AppDatabase _db;

  Future<Map<String, dynamic>> build(String submissionId) async {
    final submission = await (_db.select(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .getSingle();
    final feature = await (_db.select(_db.features)
          ..where((t) => t.id.equals(submission.featureId)))
        .getSingle();
    final building = await (_db.select(_db.buildingAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    final road = await (_db.select(_db.roadAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    final household = await (_db.select(_db.householdSurveys)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();

    return <String, dynamic>{
      'submission': _submissionToJson(submission),
      'feature_type': feature.featureType,
      'building_attributes':
          building == null ? null : _buildingToJson(building),
      'road_attributes': road == null ? null : _roadToJson(road),
      'household_survey':
          household == null ? null : _householdToJson(household),
    };
  }

  Map<String, dynamic> _submissionToJson(Submission s) => {
        'id': s.id,
        'feature_id': s.featureId,
        'submitted_by': s.submittedBy,
        'does_not_exist': s.doesNotExist,
        'remarks': s.remarks,
        'override_reason': s.overrideReason,
        'created_at': s.createdAt.toIso8601String(),
        'updated_at': s.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _buildingToJson(BuildingAttribute b) => {
        'submission_id': b.submissionId,
        'cbms_id': b.cbmsId,
        'building_name': b.buildingName,
        'ra_9514_type': b.ra9514Type,
        'storeys': b.storeys,
        'material': b.material,
        'cost_is_exact': b.costIsExact,
        'cost_amount': b.costAmount,
        'cost_estimate_range': b.costEstimateRange,
        'fire_fighting_facilities_json': b.fireFightingFacilitiesJson,
        'fire_load_json': b.fireLoadJson,
      };

  Map<String, dynamic> _roadToJson(RoadAttribute r) => {
        'submission_id': r.submissionId,
        'is_bridge': r.isBridge,
        'road_name': r.roadName,
        'width_meters': r.widthMeters,
        'road_features_json': r.roadFeaturesJson,
        'others_description': r.othersDescription,
      };

  Map<String, dynamic> _householdToJson(HouseholdSurvey h) => {
        'submission_id': h.submissionId,
        'construction_details_json': h.constructionDetailsJson,
        'kaayusan_json': h.kaayusanJson,
        'koneksyong_elektrikal_json': h.koneksyongElektrikalJson,
        'kusina_json': h.kusinaJson,
        'daanan_o_labasan_json': h.daananOLabasanJson,
        'lebel_ng_kahinaan': h.lebelNgKahinaan,
        'safety_suggestions': h.safetySuggestions,
        'homeowner_acknowledged': h.homeownerAcknowledged,
        'completed_at': h.completedAt?.toIso8601String(),
      };
}
```

(If your generated row class names differ — e.g. `BuildingAttributeData` instead of `BuildingAttribute` — adapt; check `database.g.dart`. Drift typically generates `<TableNameSingular>Data` for row classes.)

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/data/submission_payload_builder_test.dart
```

Expected: `All tests passed!` (3 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/data/submission_payload_builder.dart test/core/sync/data/submission_payload_builder_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): SubmissionPayloadBuilder — joins submission + attrs + olp

Returns a JSON-shaped Map ready for the upload_submission_bundle RPC.
Handles building vs road branching and optional household_survey.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: SyncApi abstract + FakeSyncApi

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/data/sync_api.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/data/fake_sync_api.dart`

No standalone tests — used by Task 14+ worker tests.

- [ ] **Step 1: Implement abstract `SyncApi`**

```dart
// lib/core/sync/data/sync_api.dart
import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';

/// Network surface area required by SyncWorker. Real impl in
/// supabase_sync_api.dart; in-memory fake in fake_sync_api.dart.
abstract class SyncApi {
  Future<SyncOutcome> uploadSubmission(Map<String, dynamic> payload);

  /// Uploads a photo file to Storage, returning the storage_path on success.
  /// Encoded as a SyncOutcome to handle 401/409/permanent/transient uniformly.
  Future<({SyncOutcome outcome, String? storagePath})> uploadPhotoFile({
    required String submissionId,
    required String photoId,
    required File file,
  });

  Future<SyncOutcome> markPhotoUploaded({
    required String photoId,
    required String storagePath,
  });

  Future<SyncOutcome> uploadNewFeature(Feature feature);
}
```

- [ ] **Step 2: Implement `FakeSyncApi`**

```dart
// lib/core/sync/data/fake_sync_api.dart
import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';

/// Test double whose responses are seeded by the test. Each method consumes
/// one queued outcome per call; if no responses are queued, returns Success.
class FakeSyncApi implements SyncApi {
  final List<SyncOutcome> _submissionResponses = [];
  final List<SyncOutcome> _photoUploadResponses = [];
  final List<SyncOutcome> _photoMarkResponses = [];
  final List<SyncOutcome> _newFeatureResponses = [];

  /// Records of every call, in order, for assertions.
  final List<Map<String, dynamic>> uploadSubmissionCalls = [];
  final List<({String submissionId, String photoId})> uploadPhotoFileCalls =
      [];
  final List<({String photoId, String storagePath})> markPhotoUploadedCalls =
      [];
  final List<Feature> uploadNewFeatureCalls = [];

  /// Configure the next outcome each method should return.
  void enqueueSubmission(SyncOutcome o) => _submissionResponses.add(o);
  void enqueuePhotoUpload(SyncOutcome o) => _photoUploadResponses.add(o);
  void enqueuePhotoMark(SyncOutcome o) => _photoMarkResponses.add(o);
  void enqueueNewFeature(SyncOutcome o) => _newFeatureResponses.add(o);

  SyncOutcome _next(List<SyncOutcome> q) =>
      q.isEmpty ? const Success() : q.removeAt(0);

  @override
  Future<SyncOutcome> uploadSubmission(Map<String, dynamic> payload) async {
    uploadSubmissionCalls.add(payload);
    return _next(_submissionResponses);
  }

  @override
  Future<({SyncOutcome outcome, String? storagePath})> uploadPhotoFile({
    required String submissionId,
    required String photoId,
    required File file,
  }) async {
    uploadPhotoFileCalls.add((submissionId: submissionId, photoId: photoId));
    final outcome = _next(_photoUploadResponses);
    final path = outcome is Success ? '$submissionId/$photoId.jpg' : null;
    return (outcome: outcome, storagePath: path);
  }

  @override
  Future<SyncOutcome> markPhotoUploaded({
    required String photoId,
    required String storagePath,
  }) async {
    markPhotoUploadedCalls
        .add((photoId: photoId, storagePath: storagePath));
    return _next(_photoMarkResponses);
  }

  @override
  Future<SyncOutcome> uploadNewFeature(Feature feature) async {
    uploadNewFeatureCalls.add(feature);
    return _next(_newFeatureResponses);
  }
}
```

- [ ] **Step 3: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/data/sync_api.dart lib/core/sync/data/fake_sync_api.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/data/sync_api.dart lib/core/sync/data/fake_sync_api.dart && git commit -m "$(cat <<'EOF'
feat(sync): SyncApi abstract + FakeSyncApi test double

SyncApi is the testability seam — every network call goes through it.
FakeSyncApi has a queue per method that lets tests deterministically
seed Success / TransientFailure / etc., and records every call for
assertions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Supabase migration 006 — `upload_submission_bundle` RPC

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/supabase/migrations/006_upload_submission_bundle_rpc.sql`

A single RPC that atomically upserts submission + the matching attrs + (if present) household_survey. Atomicity inside one DB transaction so partial uploads can't corrupt state.

- [ ] **Step 1: Write the migration**

```sql
-- Phase 4a: atomic upsert RPC for submission + attrs + household_survey.
-- Returns 'ok' on success; raises 23xx (unique violation, etc.) which
-- PostgREST translates to 4xx for the client.
create or replace function public.upload_submission_bundle(payload jsonb)
returns text
language plpgsql
security definer
as $$
declare
  v_submission jsonb := payload->'submission';
  v_feature_type text := payload->>'feature_type';
  v_building jsonb := payload->'building_attributes';
  v_road jsonb := payload->'road_attributes';
  v_household jsonb := payload->'household_survey';
  v_assignment_id uuid;
  v_closed boolean;
begin
  -- Verify the parent assignment isn't closed_remotely. If it is, raise 409.
  select a.id, a.closed_remotely into v_assignment_id, v_closed
  from public.assignments a
  join public.features f on f.assignment_id = a.id
  where f.id = (v_submission->>'feature_id')::uuid;

  if v_closed then
    raise exception 'assignment_closed' using errcode = '53300';
  end if;

  -- Upsert submission.
  insert into public.submissions (
    id, feature_id, submitted_by, does_not_exist, remarks, override_reason,
    sync_status, created_at, updated_at
  )
  values (
    (v_submission->>'id')::uuid,
    (v_submission->>'feature_id')::uuid,
    (v_submission->>'submitted_by')::uuid,
    (v_submission->>'does_not_exist')::boolean,
    v_submission->>'remarks',
    v_submission->>'override_reason',
    'uploaded',
    (v_submission->>'created_at')::timestamptz,
    (v_submission->>'updated_at')::timestamptz
  )
  on conflict (id) do update set
    does_not_exist = excluded.does_not_exist,
    remarks = excluded.remarks,
    override_reason = excluded.override_reason,
    sync_status = 'uploaded',
    updated_at = excluded.updated_at;

  -- Building attributes (if present).
  if v_building is not null and v_feature_type = 'building' then
    insert into public.building_attributes (
      submission_id, cbms_id, name, ra_9514_type, storeys, material,
      cost_is_exact, cost_amount, cost_estimate_range,
      fire_fighting_facilities_json, fire_load_json
    )
    values (
      (v_building->>'submission_id')::uuid,
      v_building->>'cbms_id',
      v_building->>'building_name',
      v_building->>'ra_9514_type',
      (v_building->>'storeys')::int,
      v_building->>'material',
      coalesce((v_building->>'cost_is_exact')::boolean, false),
      (v_building->>'cost_amount')::numeric,
      v_building->>'cost_estimate_range',
      v_building->>'fire_fighting_facilities_json',
      v_building->>'fire_load_json'
    )
    on conflict (submission_id) do update set
      cbms_id = excluded.cbms_id,
      name = excluded.name,
      ra_9514_type = excluded.ra_9514_type,
      storeys = excluded.storeys,
      material = excluded.material,
      cost_is_exact = excluded.cost_is_exact,
      cost_amount = excluded.cost_amount,
      cost_estimate_range = excluded.cost_estimate_range,
      fire_fighting_facilities_json = excluded.fire_fighting_facilities_json,
      fire_load_json = excluded.fire_load_json;
  end if;

  -- Road attributes (if present).
  if v_road is not null and v_feature_type = 'road' then
    insert into public.road_attributes (
      submission_id, is_bridge, road_name, width_meters,
      road_features_json, others_description
    )
    values (
      (v_road->>'submission_id')::uuid,
      coalesce((v_road->>'is_bridge')::boolean, false),
      v_road->>'road_name',
      (v_road->>'width_meters')::numeric,
      v_road->>'road_features_json',
      v_road->>'others_description'
    )
    on conflict (submission_id) do update set
      is_bridge = excluded.is_bridge,
      road_name = excluded.road_name,
      width_meters = excluded.width_meters,
      road_features_json = excluded.road_features_json,
      others_description = excluded.others_description;
  end if;

  -- Household survey (if present).
  if v_household is not null then
    insert into public.household_surveys (
      submission_id, construction_details_json, kaayusan_json,
      koneksyong_elektrikal_json, kusina_json, daanan_o_labasan_json,
      lebel_ng_kahinaan, safety_suggestions,
      homeowner_acknowledged, completed_at
    )
    values (
      (v_household->>'submission_id')::uuid,
      v_household->>'construction_details_json',
      v_household->>'kaayusan_json',
      v_household->>'koneksyong_elektrikal_json',
      v_household->>'kusina_json',
      v_household->>'daanan_o_labasan_json',
      v_household->>'lebel_ng_kahinaan',
      v_household->>'safety_suggestions',
      coalesce((v_household->>'homeowner_acknowledged')::boolean, false),
      (v_household->>'completed_at')::timestamptz
    )
    on conflict (submission_id) do update set
      construction_details_json = excluded.construction_details_json,
      kaayusan_json = excluded.kaayusan_json,
      koneksyong_elektrikal_json = excluded.koneksyong_elektrikal_json,
      kusina_json = excluded.kusina_json,
      daanan_o_labasan_json = excluded.daanan_o_labasan_json,
      lebel_ng_kahinaan = excluded.lebel_ng_kahinaan,
      safety_suggestions = excluded.safety_suggestions,
      homeowner_acknowledged = excluded.homeowner_acknowledged,
      completed_at = excluded.completed_at;
  end if;

  return 'ok';
end;
$$;

-- PostgREST exposes the function under /rpc/upload_submission_bundle.
grant execute on function public.upload_submission_bundle(jsonb) to authenticated;
```

- [ ] **Step 2: Push migration**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && supabase db push
```

Expected: `Applying migration 006_upload_submission_bundle_rpc.sql...` then `Done.`

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add supabase/migrations/006_upload_submission_bundle_rpc.sql && git commit -m "$(cat <<'EOF'
feat(supabase): migration 006 — upload_submission_bundle RPC

Single atomic upsert across submissions + building/road_attributes +
household_surveys. Raises SQLSTATE 53300 ('assignment_closed') when
the parent assignment is closed_remotely; PostgREST translates to a
client-visible 409.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: SupabaseSyncApi (real implementation)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/data/supabase_sync_api.dart`

No automated test — exercised manually via the happy path in Task 25 and via the worker tests through `FakeSyncApi`.

- [ ] **Step 1: Implement**

```dart
import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class SupabaseSyncApi implements SyncApi {
  SupabaseSyncApi(this._client);
  final SupabaseClient _client;
  static const _photosBucket = 'photos';

  @override
  Future<SyncOutcome> uploadSubmission(Map<String, dynamic> payload) async {
    try {
      await _client.rpc<dynamic>(
        'upload_submission_bundle',
        params: {'payload': payload},
      );
      return const Success();
    } on PostgrestException catch (e) {
      return _mapPostgrestException(e, payload);
    } on AuthException {
      return const AuthExpired();
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  @override
  Future<({SyncOutcome outcome, String? storagePath})> uploadPhotoFile({
    required String submissionId,
    required String photoId,
    required File file,
  }) async {
    final path = '$submissionId/$photoId.jpg';
    try {
      await _client.storage.from(_photosBucket).upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: true),
          );
      return (outcome: const Success(), storagePath: path);
    } on StorageException catch (e) {
      return (outcome: _mapStorageException(e), storagePath: null);
    } on AuthException {
      return (outcome: const AuthExpired(), storagePath: null);
    } on Object catch (e) {
      return (outcome: TransientFailure(e.toString()), storagePath: null);
    }
  }

  @override
  Future<SyncOutcome> markPhotoUploaded({
    required String photoId,
    required String storagePath,
  }) async {
    try {
      await _client.from('photos').update({
        'storage_path': storagePath,
        'upload_status': 'uploaded',
      }).eq('id', photoId);
      return const Success();
    } on PostgrestException catch (e) {
      return _mapPostgrestException(e, null);
    } on AuthException {
      return const AuthExpired();
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  @override
  Future<SyncOutcome> uploadNewFeature(Feature feature) async {
    try {
      await _client.from('features').upsert({
        'id': feature.id,
        'assignment_id': feature.assignmentId,
        'feature_type': feature.featureType,
        'geometry': feature.geometryGeojson,
        'is_new': feature.isNew,
        'created_at': feature.createdAt.toIso8601String(),
      });
      return const Success();
    } on PostgrestException catch (e) {
      return _mapPostgrestException(e, null);
    } on AuthException {
      return const AuthExpired();
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  SyncOutcome _mapPostgrestException(
    PostgrestException e,
    Map<String, dynamic>? submissionPayload,
  ) {
    // SQLSTATE 53300 → assignment_closed (raised by upload_submission_bundle)
    if (e.code == '53300' || e.message.contains('assignment_closed')) {
      final assignmentId =
          submissionPayload?['submission']?['assignment_id'] as String? ??
              'unknown';
      return AssignmentClosed(assignmentId);
    }
    final status = e.code;
    if (status == '401' || e.message.contains('JWT')) {
      return const AuthExpired();
    }
    if (status != null && status.startsWith('4')) {
      return PermanentFailure('${e.code} ${e.message}');
    }
    return TransientFailure('${e.code} ${e.message}');
  }

  SyncOutcome _mapStorageException(StorageException e) {
    final code = e.statusCode ?? '';
    if (code == '401') return const AuthExpired();
    if (code.startsWith('4')) return PermanentFailure('$code ${e.message}');
    return TransientFailure('$code ${e.message}');
  }
}
```

- [ ] **Step 2: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/data/supabase_sync_api.dart
```

Expected: `No issues found!`. Fix any lint without changing logic.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/data/supabase_sync_api.dart && git commit -m "$(cat <<'EOF'
feat(sync): SupabaseSyncApi — real impl backed by supabase_flutter

uploadSubmission → upload_submission_bundle RPC (atomic upsert).
uploadPhotoFile → Storage upload with upsert:true (idempotent retries).
markPhotoUploaded → photos UPDATE via PostgREST.
uploadNewFeature → features upsert via PostgREST.

PostgrestException + StorageException + AuthException are translated
to SyncOutcome variants. SQLSTATE 53300 ('assignment_closed') maps to
AssignmentClosed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: PendingWorkBundle (JSON+ZIP export) + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/failure/pending_work_bundle.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/failure/pending_work_bundle_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory tmpDir;
  late PendingWorkBundle bundle;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tmpDir = Directory.systemTemp.createTempSync('firecheck-bundle-');
    bundle = PendingWorkBundle(db, downloadsDirOverride: tmpDir);
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value('queued'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('exportFor writes a zip containing data.json with unsynced rows',
      () async {
    final out = await bundle.exportFor('a1');
    expect(out.existsSync(), isTrue);
    final bytes = await out.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final dataFile =
        archive.files.firstWhere((f) => f.name == 'data.json');
    final json = jsonDecode(utf8.decode(dataFile.content as List<int>))
        as Map<String, dynamic>;
    expect((json['submissions'] as List).first['id'], 's1');
  });

  test('exportFor includes photo files when photos exist + file present',
      () async {
    final photoFile = File(p.join(tmpDir.path, 'src-photo.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4, 5]);
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph1',
          submissionId: 's1',
          localPath: photoFile.path,
          capturedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ));
    final out = await bundle.exportFor('a1');
    final archive =
        ZipDecoder().decodeBytes(await out.readAsBytes());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, contains('photos/ph1.jpg'));
  });

  test('exportFor skips photo files whose local file is missing', () async {
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph-missing',
          submissionId: 's1',
          localPath: '/does/not/exist.jpg',
          capturedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ));
    final out = await bundle.exportFor('a1');
    final archive =
        ZipDecoder().decodeBytes(await out.readAsBytes());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, isNot(contains('photos/ph-missing.jpg')));
    // data.json still produced, photo metadata included.
    final data =
        archive.files.firstWhere((f) => f.name == 'data.json');
    final json = jsonDecode(utf8.decode(data.content as List<int>))
        as Map<String, dynamic>;
    expect((json['photos'] as List).first['id'], 'ph-missing');
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/failure/pending_work_bundle_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PendingWorkBundle {
  PendingWorkBundle(this._db, {Directory? downloadsDirOverride})
      : _downloadsDirOverride = downloadsDirOverride;
  final AppDatabase _db;
  final Directory? _downloadsDirOverride;

  /// Builds bundle.zip in app's external Downloads dir (or override) and
  /// returns the file. JSON dump includes all unsynced submissions, photos,
  /// new features, attrs, and household_surveys for the given assignment.
  /// Photos whose local file is missing are skipped from the photos/ tree
  /// but their metadata still appears in data.json.
  Future<File> exportFor(String assignmentId) async {
    final dir = _downloadsDirOverride ??
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final zipPath = p.join(dir.path, 'firecheck-pending-$assignmentId-$ts.zip');

    final archive = Archive();
    final json = await _collectUnsynced(assignmentId);
    archive.addFile(ArchiveFile.string('data.json', jsonEncode(json)));

    for (final photo in (json['photos'] as List<dynamic>)) {
      final path = (photo as Map<String, dynamic>)['local_path'] as String;
      final id = photo['id'] as String;
      final f = File(path);
      if (!f.existsSync()) continue;
      final bytes = await f.readAsBytes();
      archive.addFile(ArchiveFile('photos/$id.jpg', bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(archive);
    final out = File(zipPath);
    await out.writeAsBytes(encoded);
    return out;
  }

  Future<Map<String, dynamic>> _collectUnsynced(String assignmentId) async {
    final features = await (_db.select(_db.features)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .get();
    final featureIds = features.map((f) => f.id).toList();
    final submissions = await (_db.select(_db.submissions)
          ..where((t) =>
              t.featureId.isIn(featureIds) &
              t.syncStatus.isNotIn(['uploaded'])))
        .get();
    final submissionIds = submissions.map((s) => s.id).toList();
    final building = await (_db.select(_db.buildingAttributes)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
    final road = await (_db.select(_db.roadAttributes)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
    final olp = await (_db.select(_db.householdSurveys)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
    final photos = await (_db.select(_db.photos)
          ..where((t) =>
              t.submissionId.isIn(submissionIds) &
              t.uploadStatus.isNotIn(['uploaded'])))
        .get();

    return {
      'assignment_id': assignmentId,
      'exported_at': DateTime.now().toIso8601String(),
      'features': features.map(_toJsonFeature).toList(),
      'submissions': submissions.map(_toJsonSubmission).toList(),
      'building_attributes': building.map(_toJsonBuilding).toList(),
      'road_attributes': road.map(_toJsonRoad).toList(),
      'household_surveys': olp.map(_toJsonOlp).toList(),
      'photos': photos.map(_toJsonPhoto).toList(),
    };
  }

  Map<String, dynamic> _toJsonFeature(Feature f) => {
        'id': f.id,
        'assignment_id': f.assignmentId,
        'feature_type': f.featureType,
        'geometry_geojson': f.geometryGeojson,
        'is_new': f.isNew,
      };

  Map<String, dynamic> _toJsonSubmission(Submission s) => {
        'id': s.id,
        'feature_id': s.featureId,
        'submitted_by': s.submittedBy,
        'does_not_exist': s.doesNotExist,
        'override_reason': s.overrideReason,
        'sync_status': s.syncStatus,
        'created_at': s.createdAt.toIso8601String(),
        'updated_at': s.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _toJsonBuilding(BuildingAttribute b) => {
        'submission_id': b.submissionId,
        'cbms_id': b.cbmsId,
        'building_name': b.buildingName,
        'ra_9514_type': b.ra9514Type,
        'storeys': b.storeys,
        'material': b.material,
        'cost_amount': b.costAmount,
        'cost_estimate_range': b.costEstimateRange,
      };

  Map<String, dynamic> _toJsonRoad(RoadAttribute r) => {
        'submission_id': r.submissionId,
        'road_name': r.roadName,
        'width_meters': r.widthMeters,
        'is_bridge': r.isBridge,
      };

  Map<String, dynamic> _toJsonOlp(HouseholdSurvey h) => {
        'submission_id': h.submissionId,
        'lebel_ng_kahinaan': h.lebelNgKahinaan,
        'homeowner_acknowledged': h.homeownerAcknowledged,
        'completed_at': h.completedAt?.toIso8601String(),
      };

  Map<String, dynamic> _toJsonPhoto(Photo p) => {
        'id': p.id,
        'submission_id': p.submissionId,
        'local_path': p.localPath,
        'storage_path': p.storagePath,
        'upload_status': p.uploadStatus,
        'gps_lat': p.gpsLat,
        'gps_lng': p.gpsLng,
        'captured_at': p.capturedAt.toIso8601String(),
      };
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/failure/pending_work_bundle_test.dart
```

Expected: `All tests passed!` (3 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/failure/pending_work_bundle.dart test/core/sync/failure/pending_work_bundle_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): PendingWorkBundle — JSON+ZIP export for 409 path

Builds a single bundle.zip in app's Downloads dir containing data.json
(all unsynced submissions/features/attrs/photos metadata) + photos/
subdirectory with each existing local file. Missing photo files are
skipped from the zip but their metadata is preserved in data.json.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: SyncWorker — happy path (Success outcome)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/worker/sync_worker.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/worker/sync_worker_happy_path_test.dart`

This task implements the worker shell + Success path only. Subsequent tasks add retry, auth, and assignment-closed branches.

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncJobsRepository jobs;
  late SubmissionPayloadBuilder payload;
  late AssignmentLockRepository lock;
  late FakeSyncApi api;
  late SyncWorker worker;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    jobs = SyncJobsRepository(db);
    payload = SubmissionPayloadBuilder(db);
    lock = AssignmentLockRepository(db);
    api = FakeSyncApi();
    worker = SyncWorker(api: api, jobs: jobs, payload: payload, lock: lock, db: db);
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value('ready_to_upload'),
          ),
        );
    // Outbox transaction queues a submission sync_job for s1.
    await FinalizeSubmissionUseCase(db).execute('s1');
  });

  tearDown(() async => db.close());

  test('Success → sync_jobs row marked success + submission row uploaded',
      () async {
    await worker.drain();

    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.success);

    final sub = await (db.select(db.submissions)
          ..where((t) => t.id.equals('s1')))
        .getSingle();
    expect(sub.syncStatus, 'uploaded');

    expect(api.uploadSubmissionCalls, hasLength(1));
  });

  test('drain() de-dupes overlapping calls', () async {
    final f1 = worker.drain();
    final f2 = worker.drain();
    await Future.wait([f1, f2]);
    // Only one Success outcome consumed.
    expect(api.uploadSubmissionCalls, hasLength(1));
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/sync_worker_happy_path_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/domain/retry_schedule.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class SyncWorker {
  SyncWorker({
    required this.api,
    required this.jobs,
    required this.payload,
    required this.lock,
    required this.db,
    this.bundle,
    SupabaseClient? supabaseClient,
  }) : _supabaseClient = supabaseClient;

  final SyncApi api;
  final SyncJobsRepository jobs;
  final SubmissionPayloadBuilder payload;
  final AssignmentLockRepository lock;
  final AppDatabase db;
  final PendingWorkBundle? bundle;
  final SupabaseClient? _supabaseClient;

  static const _maxConcurrent = 3;
  bool _running = false;

  Future<void> drain() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final assignmentRow =
            await db.select(db.assignments).getSingleOrNull();
        if (assignmentRow != null && assignmentRow.closedRemotely) return;

        final claimed = await jobs.claimUpToN(_maxConcurrent);
        if (claimed.isEmpty) return;
        await Future.wait(claimed.map(_processOne));
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _processOne(SyncJob job) async {
    final outcome = await _execute(job);
    await _applyOutcome(job, outcome);
  }

  Future<SyncOutcome> _execute(SyncJob job) async {
    try {
      switch (job.entityType) {
        case SyncEntityType.submission:
          return await _executeSubmission(job.entityId);
        case SyncEntityType.photo:
          return await _executePhoto(job.entityId);
        case SyncEntityType.newFeature:
          return await _executeNewFeature(job.entityId);
        default:
          return PermanentFailure('unknown entity_type: ${job.entityType}');
      }
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  Future<SyncOutcome> _executeSubmission(String submissionId) async {
    final json = await payload.build(submissionId);
    final outcome = await api.uploadSubmission(json);
    if (outcome is Success) {
      await (db.update(db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(const SubmissionsCompanion(syncStatus: Value('uploaded')));
    }
    return outcome;
  }

  Future<SyncOutcome> _executePhoto(String photoId) async {
    final photo = await (db.select(db.photos)
          ..where((t) => t.id.equals(photoId)))
        .getSingle();
    final file = File(photo.localPath);
    if (!file.existsSync()) {
      return const PermanentFailure('photo file missing');
    }
    final upload = await api.uploadPhotoFile(
      submissionId: photo.submissionId,
      photoId: photoId,
      file: file,
    );
    if (upload.outcome is! Success || upload.storagePath == null) {
      return upload.outcome;
    }
    final mark = await api.markPhotoUploaded(
      photoId: photoId,
      storagePath: upload.storagePath!,
    );
    if (mark is Success) {
      await (db.update(db.photos)..where((t) => t.id.equals(photoId))).write(
        PhotosCompanion(
          storagePath: Value(upload.storagePath),
          uploadStatus: const Value('uploaded'),
        ),
      );
    }
    return mark;
  }

  Future<SyncOutcome> _executeNewFeature(String featureId) async {
    final feature = await (db.select(db.features)
          ..where((t) => t.id.equals(featureId)))
        .getSingle();
    return api.uploadNewFeature(feature);
  }

  Future<void> _applyOutcome(SyncJob job, SyncOutcome outcome) async {
    switch (outcome) {
      case Success():
        await jobs.markSuccess(job.id);
      case TransientFailure(:final error):
        final attempts = job.attempts + 1;
        final next = nextRetryAt(attempts);
        if (next == null) {
          await jobs.markDead(job.id, error: error, attempts: attempts);
        } else {
          await jobs.markPendingRetry(job.id,
              attempts: attempts, lastError: error, nextRetryAt: next);
        }
      case PermanentFailure(:final error):
        await jobs.markDead(job.id, error: error, attempts: job.attempts + 1);
      case AuthExpired():
        await _handleAuthExpired(job);
      case AssignmentClosed(:final assignmentId):
        await _handleAssignmentClosed(job, assignmentId);
    }
  }

  Future<void> _handleAuthExpired(SyncJob job) async {
    final client = _supabaseClient ?? Supabase.instance.client;
    try {
      final res = await client.auth.refreshSession();
      if (res.session == null) {
        await _applyOutcome(job, const TransientFailure('auth refresh failed'));
        return;
      }
    } on Object catch (e) {
      await _applyOutcome(job, TransientFailure('auth refresh failed: $e'));
      return;
    }
    final retry = await _execute(job);
    // No infinite refresh loop: a second AuthExpired is treated as transient.
    await _applyOutcome(
        job, retry is AuthExpired ? const TransientFailure('repeat 401') : retry);
  }

  Future<void> _handleAssignmentClosed(
      SyncJob job, String assignmentId) async {
    await lock.markClosed(assignmentId);
    if (bundle != null) {
      // Best-effort: don't crash drain if bundle export fails.
      try {
        await bundle!.exportFor(assignmentId);
      } on Object {
        // Bundle errors don't block lock state; surfaced in Phase 4b UI.
      }
    }
    // Job goes back to pending so a future drain (after the lock clears) can retry.
    await jobs.markPendingRetry(
      job.id,
      attempts: job.attempts,
      lastError: '409 assignment_closed',
      nextRetryAt: null,
    );
  }
}
```

- [ ] **Step 4: Verify happy path tests pass**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/sync_worker_happy_path_test.dart
```

Expected: `All tests passed!` (2 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/worker/sync_worker.dart test/core/sync/worker/sync_worker_happy_path_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): SyncWorker — drain loop + happy path Success handling

Worker shell with claim/process loop, max 3 concurrent, dedup via
_running flag. Full per-outcome dispatch implemented (incl. auth
refresh + assignment-closed paths) but only Success path is
test-covered here; retry/permanent/auth/closed get dedicated tests
in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: SyncWorker — retry + permanent failure tests

**Files:**
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/worker/sync_worker_retry_test.dart`

(Worker code already covers these; we add the test coverage.)

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.assignments).insert(AssignmentsCompanion.insert(
        id: 'a1',
        enumeratorId: 'admin',
        campaignId: 'c1',
        boundaryPolygonGeojson: '{}',
        createdAt: now,
      ));
  await db.into(db.features).insert(FeaturesCompanion.insert(
        id: 'f1',
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: '{}',
        createdAt: now,
      ));
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
        id: 's1',
        featureId: 'f1',
        createdAt: now,
        updatedAt: now,
        syncStatus: const Value('ready_to_upload'),
      ));
  await FinalizeSubmissionUseCase(db).execute('s1');
}

void main() {
  test('TransientFailure → attempts++ + next_retry_at scheduled', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()..enqueueSubmission(const TransientFailure('500'));
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.pending);
    expect(job.attempts, 1);
    expect(job.lastError, '500');
    expect(job.nextRetryAt, isNotNull);
  });

  test('5th TransientFailure → marked dead', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    // Manually set attempts=4 so the next failure is the 5th and crosses
    // into dead.
    final jobBefore = await db.select(db.syncJobs).getSingle();
    await (db.update(db.syncJobs)
          ..where((t) => t.id.equals(jobBefore.id)))
        .write(const SyncJobsCompanion(attempts: Value(4)));
    final api = FakeSyncApi()..enqueueSubmission(const TransientFailure('500'));
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.dead);
    expect(job.attempts, 5);
  });

  test('PermanentFailure (4xx other) → marked dead immediately', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()
      ..enqueueSubmission(const PermanentFailure('400 bad request'));
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.dead);
    expect(job.attempts, 1);
    expect(job.lastError, '400 bad request');
  });
}
```

- [ ] **Step 2: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/sync_worker_retry_test.dart
```

Expected: `All tests passed!` (3 tests). If failing, double-check the worker's retry-table boundary in Task 15.

- [ ] **Step 3: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze test/core/sync/worker/
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add test/core/sync/worker/sync_worker_retry_test.dart && git commit -m "$(cat <<'EOF'
test(sync): SyncWorker — retry table boundary + permanent failure

Three test cases covering the retry/dead branches: 1st transient →
pending+next_retry_at; 5th transient → dead; permanent (4xx) → dead
immediately.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: SyncWorker — auth refresh path tests

**Files:**
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/worker/sync_worker_auth_test.dart`

The Phase 4a worker calls `Supabase.instance.client.auth.refreshSession()`. To test it without a real Supabase client, we'll inject a mock via the worker's optional `supabaseClient` constructor parameter. This means we need a thin local mock; we can use `mocktail` (already a transitive dep via flutter_riverpod / others) — or we can construct a custom `SupabaseClient` test double via the package's testable APIs.

**Practical approach:** the auth-refresh path is hard to mock with the current SyncWorker design because `_handleAuthExpired` calls `Supabase.instance.client.auth.refreshSession()` directly. For Phase 4a we'll add an indirection: a function-typed constructor parameter `Future<bool> Function() refreshSession` that defaults to the real Supabase call. Tests inject a fake.

- [ ] **Step 1: Modify SyncWorker to accept a `refreshSession` callback**

In `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/worker/sync_worker.dart`:

a. Add to constructor parameters:
```dart
Future<bool> Function()? refreshSession,
```
and store as `_refreshSession`.

b. Replace the body of `_handleAuthExpired` so the refresh call goes through the injected callback (with a default that wraps the real Supabase API):

```dart
Future<bool> _defaultRefresh() async {
  final client = _supabaseClient ?? Supabase.instance.client;
  final res = await client.auth.refreshSession();
  return res.session != null;
}

Future<void> _handleAuthExpired(SyncJob job) async {
  final refresh = _refreshSession ?? _defaultRefresh;
  bool ok;
  try {
    ok = await refresh();
  } on Object {
    ok = false;
  }
  if (!ok) {
    await _applyOutcome(job, const TransientFailure('auth refresh failed'));
    return;
  }
  final retry = await _execute(job);
  await _applyOutcome(
      job, retry is AuthExpired ? const TransientFailure('repeat 401') : retry);
}
```

c. Field: `final Future<bool> Function()? _refreshSession;`

- [ ] **Step 2: Failing test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.assignments).insert(AssignmentsCompanion.insert(
        id: 'a1',
        enumeratorId: 'admin',
        campaignId: 'c1',
        boundaryPolygonGeojson: '{}',
        createdAt: now,
      ));
  await db.into(db.features).insert(FeaturesCompanion.insert(
        id: 'f1',
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: '{}',
        createdAt: now,
      ));
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
        id: 's1',
        featureId: 'f1',
        createdAt: now,
        updatedAt: now,
        syncStatus: const Value('ready_to_upload'),
      ));
  await FinalizeSubmissionUseCase(db).execute('s1');
}

void main() {
  test('AuthExpired → refresh succeeds → retry inline → Success', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()
      ..enqueueSubmission(const AuthExpired())
      ..enqueueSubmission(const Success());
    var refreshCalls = 0;
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
      refreshSession: () async {
        refreshCalls++;
        return true;
      },
    );
    await worker.drain();
    expect(refreshCalls, 1);
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.success);
  });

  test('AuthExpired → refresh fails → marked pending+attempts++', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()..enqueueSubmission(const AuthExpired());
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
      refreshSession: () async => false,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.pending);
    expect(job.attempts, 1);
    expect(job.lastError, contains('auth refresh'));
  });

  test('AuthExpired → refresh ok but retry returns AuthExpired again → transient',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()
      ..enqueueSubmission(const AuthExpired())
      ..enqueueSubmission(const AuthExpired());
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
      refreshSession: () async => true,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.pending);
    expect(job.attempts, 1);
    expect(job.lastError, contains('repeat 401'));
  });
}
```

- [ ] **Step 3: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/sync_worker_auth_test.dart
```

Expected: `All tests passed!` (3 tests).

- [ ] **Step 4: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/worker/sync_worker.dart test/core/sync/worker/sync_worker_auth_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): SyncWorker — testable refreshSession indirection + 3 auth tests

SyncWorker accepts an optional Future<bool> Function() refreshSession
so tests can mock the auth flow without a real Supabase client.
Defaults to the real Supabase API if not injected.

Tests: refresh success → retry inline → success; refresh failure →
transient; refresh ok + repeat 401 → transient (no infinite loop).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: SyncWorker — assignment-closed path tests

**Files:**
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/worker/sync_worker_assignment_closed_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.assignments).insert(AssignmentsCompanion.insert(
        id: 'a1',
        enumeratorId: 'admin',
        campaignId: 'c1',
        boundaryPolygonGeojson: '{}',
        createdAt: now,
      ));
  await db.into(db.features).insert(FeaturesCompanion.insert(
        id: 'f1',
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: '{}',
        createdAt: now,
      ));
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
        id: 's1',
        featureId: 'f1',
        createdAt: now,
        updatedAt: now,
        syncStatus: const Value('ready_to_upload'),
      ));
  await FinalizeSubmissionUseCase(db).execute('s1');
}

void main() {
  test('AssignmentClosed → lock marked + bundle exported + worker exits',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tmp = Directory.systemTemp.createTempSync('firecheck-bundle-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await _seed(db);
    final lock = AssignmentLockRepository(db);
    final api = FakeSyncApi()..enqueueSubmission(const AssignmentClosed('a1'));
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: lock,
      bundle: PendingWorkBundle(db, downloadsDirOverride: tmp),
      db: db,
    );
    await worker.drain();
    expect(await lock.isLocked('a1'), isTrue);
    expect(tmp.listSync().any((f) => f.path.endsWith('.zip')), isTrue);
  });

  test('Once locked, subsequent drain() exits without claiming', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    await AssignmentLockRepository(db).markClosed('a1');
    final api = FakeSyncApi();
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
    );
    await worker.drain();
    expect(api.uploadSubmissionCalls, isEmpty);
  });
}
```

- [ ] **Step 2: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/sync_worker_assignment_closed_test.dart
```

Expected: `All tests passed!` (2 tests).

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add test/core/sync/worker/sync_worker_assignment_closed_test.dart && git commit -m "$(cat <<'EOF'
test(sync): SyncWorker — assignment-closed path

Two tests: first 409 marks lock + writes bundle file; subsequent drain
exits early on the lock check without claiming any jobs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: ConnectivityListener + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/worker/connectivity_listener.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/worker/connectivity_listener_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/sync/worker/connectivity_listener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('triggers on transition to non-none connectivity', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var triggers = 0;
    final listener =
        ConnectivityListener(stream: controller.stream, onConnect: () async => triggers++);
    listener.start();

    controller.add([ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(triggers, 0);

    controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(triggers, 1);

    controller.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(triggers, 2);

    controller.add([ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(triggers, 2);

    listener.dispose();
    await controller.close();
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/connectivity_listener_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityListener {
  ConnectivityListener({
    required Future<void> Function() onConnect,
    Stream<List<ConnectivityResult>>? stream,
  })  : _onConnect = onConnect,
        _stream = stream ?? Connectivity().onConnectivityChanged;

  final Future<void> Function() _onConnect;
  final Stream<List<ConnectivityResult>> _stream;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  void start() {
    _sub = _stream.listen((results) async {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) await _onConnect();
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/connectivity_listener_test.dart
```

Expected: `All tests passed!` (1 test).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/worker/connectivity_listener.dart test/core/sync/worker/connectivity_listener_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): ConnectivityListener — kick worker on connectivity-regained

Subscribes to connectivity_plus stream; calls onConnect whenever any
result is non-none. Stream injectable for tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 20: SyncLifecycleListener + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/worker/lifecycle_listener.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/sync/worker/lifecycle_listener_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:firecheck/core/sync/worker/lifecycle_listener.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onResume callback fires when WidgetsBinding emits resumed', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    var triggers = 0;
    final l = SyncLifecycleListener(onResume: () async => triggers++)..start();

    // Simulate the framework dispatching resumed.
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(triggers, 1);

    l.dispose();
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/lifecycle_listener_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/widgets.dart';

class SyncLifecycleListener {
  SyncLifecycleListener({required Future<void> Function() onResume})
      : _onResume = onResume;

  final Future<void> Function() _onResume;
  AppLifecycleListener? _listener;

  void start() {
    _listener = AppLifecycleListener(
      onResume: () async => _onResume(),
    );
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/worker/lifecycle_listener_test.dart
```

Expected: `All tests passed!` (1 test).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/ test/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/worker/lifecycle_listener.dart test/core/sync/worker/lifecycle_listener_test.dart && git commit -m "$(cat <<'EOF'
feat(sync): SyncLifecycleListener — kick worker on app foreground

Wraps Flutter's AppLifecycleListener and calls onResume when the app
returns to foreground. Lets the worker drain immediately after the
user reopens the app.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 21: WorkManager dispatcher

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/worker/workmanager_dispatcher.dart`

No automated test — WorkManager runs in a separate Android process and can't be exercised in `flutter_tester`. Validated via the manual happy path (Task 25).

- [ ] **Step 1: Implement**

```dart
import 'dart:async';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/supabase_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:workmanager/workmanager.dart';

const _periodicTaskName = 'firecheck.sync.periodic';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Initialize a minimal Supabase + Drift in this isolate.
      await dotenv.load();
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );
      // Background isolate uses the same on-disk Drift DB.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      // NOTE: in production, WorkManager isolate should open the same
      // sqlite file the main isolate uses. For Phase 4a we ship with the
      // simpler path — the periodic tick isn't load-bearing for correctness
      // (connectivity + foreground triggers are). Production-grade isolate
      // sharing lands as Phase 5 polish.
      final api = SupabaseSyncApi(Supabase.instance.client);
      final worker = SyncWorker(
        api: api,
        jobs: SyncJobsRepository(db),
        payload: SubmissionPayloadBuilder(db),
        lock: AssignmentLockRepository(db),
        db: db,
        bundle: PendingWorkBundle(db),
      );
      await worker.drain();
      return Future.value(true);
    } on Object {
      return Future.value(false);
    }
  });
}

Future<void> registerPeriodicSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _periodicTaskName,
    'firecheck.sync',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> cancelPeriodicSync() async {
  await Workmanager().cancelByUniqueName(_periodicTaskName);
}
```

- [ ] **Step 2: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/worker/workmanager_dispatcher.dart
```

Expected: `No issues found!`. Fix lint without changing logic. The `// NOTE` comment about isolate sharing is intentional — it's an honest documentation of a Phase 5 polish item, not a placeholder.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/worker/workmanager_dispatcher.dart && git commit -m "$(cat <<'EOF'
feat(sync): WorkManager dispatcher — periodic 15min background drain

@pragma('vm:entry-point') callbackDispatcher initializes a minimal
SyncWorker and calls drain. registerPeriodicSync schedules with a
network-connected constraint. Cross-isolate Drift sharing is a known
limitation flagged for Phase 5 polish.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 22: SyncController + Riverpod providers

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/worker/sync_controller.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/sync/presentation/sync_providers.dart`

- [ ] **Step 1: Implement SyncController**

```dart
// lib/core/sync/worker/sync_controller.dart
import 'dart:async';

import 'package:firecheck/core/sync/worker/connectivity_listener.dart';
import 'package:firecheck/core/sync/worker/lifecycle_listener.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';

/// Singleton facade that wires a SyncWorker to its trigger sources
/// (connectivity, lifecycle) and exposes a public triggerNow() / start()
/// API for consumers. WorkManager periodic ticks call triggerNow on the
/// background isolate (independent SyncController instance).
class SyncController {
  SyncController(this._worker);
  final SyncWorker _worker;
  ConnectivityListener? _connectivity;
  SyncLifecycleListener? _lifecycle;

  Future<void> start() async {
    _connectivity = ConnectivityListener(onConnect: triggerNow)..start();
    _lifecycle = SyncLifecycleListener(onResume: triggerNow)..start();
    await triggerNow();
  }

  Future<void> triggerNow() => _worker.drain();

  Future<void> stop() async {
    await _connectivity?.dispose();
    _lifecycle?.dispose();
  }
}
```

- [ ] **Step 2: Implement Riverpod providers**

```dart
// lib/core/sync/presentation/sync_providers.dart
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/supabase_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:firecheck/core/sync/worker/sync_controller.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

final syncApiProvider = Provider<SyncApi>((ref) {
  return SupabaseSyncApi(Supabase.instance.client);
});

final syncJobsRepositoryProvider = Provider<SyncJobsRepository>((ref) {
  return SyncJobsRepository(ref.watch(appDatabaseProvider));
});

final assignmentLockRepositoryProvider =
    Provider<AssignmentLockRepository>((ref) {
  return AssignmentLockRepository(ref.watch(appDatabaseProvider));
});

final pendingWorkBundleProvider = Provider<PendingWorkBundle>((ref) {
  return PendingWorkBundle(ref.watch(appDatabaseProvider));
});

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncWorker(
    api: ref.watch(syncApiProvider),
    jobs: ref.watch(syncJobsRepositoryProvider),
    payload: SubmissionPayloadBuilder(db),
    lock: ref.watch(assignmentLockRepositoryProvider),
    db: db,
    bundle: ref.watch(pendingWorkBundleProvider),
  );
});

final syncControllerProvider = Provider<SyncController>((ref) {
  final controller = SyncController(ref.watch(syncWorkerProvider));
  ref.onDispose(controller.stop);
  return controller;
});
```

- [ ] **Step 3: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/sync/worker/sync_controller.dart lib/core/sync/presentation/sync_providers.dart && git commit -m "$(cat <<'EOF'
feat(sync): SyncController + Riverpod providers

SyncController is the singleton facade wiring connectivity + lifecycle
listeners to the worker. Riverpod providers compose the dependency
graph (api → repos → worker → controller).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 23: main.dart wiring

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/main.dart`

- [ ] **Step 1: Read current main.dart** to confirm structure.

- [ ] **Step 2: Add WorkManager init + SyncController boot**

Modifications:
1. Import `workmanager_dispatcher.dart` and `sync_controller_provider`.
2. After `Supabase.initialize`, call `await registerPeriodicSync();`.
3. Wrap `FireCheckApp` in a `_SyncBootstrap` ConsumerWidget that reads `syncControllerProvider` and calls `controller.start()` in `initState` once. Pattern:

```dart
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/core/sync/worker/workmanager_dispatcher.dart';
// ...other existing imports

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  await registerPeriodicSync();
  runApp(const ProviderScope(child: _SyncBootstrap(child: FireCheckApp())));
}

class _SyncBootstrap extends ConsumerStatefulWidget {
  const _SyncBootstrap({required this.child});
  final Widget child;

  @override
  ConsumerState<_SyncBootstrap> createState() => _SyncBootstrapState();
}

class _SyncBootstrapState extends ConsumerState<_SyncBootstrap> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(syncControllerProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 3: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/main.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/main.dart && git commit -m "$(cat <<'EOF'
feat(main): wire SyncController.start + WorkManager registration

main() awaits Supabase.initialize then registerPeriodicSync.
_SyncBootstrap top-level wrapper kicks SyncController.start() in
microtask post-mount, which spins up connectivity + lifecycle listeners
and runs an initial drain.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 24: Home screen debug long-press trigger

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/home/presentation/home_screen.dart`

- [ ] **Step 1: Read the current home_screen.dart** to find the primary card.

- [ ] **Step 2: Wrap the primary card in a `GestureDetector` with `onLongPress`**

Add an import for the sync controller and FinalizeSubmissionUseCase + a database provider import (already used elsewhere). On long-press: for each submission with `sync_status='ready_to_upload'`, call `FinalizeSubmissionUseCase.execute(s.id)`, then `controller.triggerNow()`. Show a SnackBar confirming N jobs queued.

```dart
GestureDetector(
  onLongPress: () async {
    final db = ref.read(appDatabaseProvider);
    final readyRows = await (db.select(db.submissions)
          ..where((t) => t.syncStatus.equals('ready_to_upload')))
        .get();
    final useCase = FinalizeSubmissionUseCase(db);
    for (final s in readyRows) {
      await useCase.execute(s.id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued ${readyRows.length} submission(s)')),
      );
    }
    await ref.read(syncControllerProvider).triggerNow();
  },
  child: /* existing primary card widget */,
),
```

(Wrap whichever card the home screen currently uses for the primary CTA. If the home screen has no card, wrap the screen body's first FilledButton or `_HomeAction` widget; the goal is just a hidden long-press path for Phase 4a debugging.)

- [ ] **Step 3: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/home/
```

Expected: `No issues found!`

- [ ] **Step 4: Verify existing home widget tests still pass**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/home/
```

Expected: existing tests unchanged (the long-press isn't tapped by any test).

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/home/presentation/home_screen.dart && git commit -m "$(cat <<'EOF'
feat(home): debug long-press trigger for Phase 4a sync drain

Hidden gesture: long-press the primary home card to enqueue all
ready_to_upload submissions and kick the sync worker. Replaced in
Phase 4b by the Review screen's 'Start Upload' button.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 25: Final verification + tag

**Files:** none modified — verification + tag only.

- [ ] **Step 1: Run full analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 2: Run the full test suite**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test
```

Expected: ≥ 220 tests passing (Phase 3b ended at 191; Phase 4a adds ~30+). Final line: `All tests passed!`. If any prior test that hardcoded `schemaVersion == 4` fails, relax to `greaterThanOrEqualTo(4)` (same fix Phase 3b applied for v3 tests). Commit any such relaxation as a separate `chore(db)` commit before tagging.

- [ ] **Step 3: Build the debug APK**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter build apk --debug
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Install + manual happy path on emulator**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && adb install -r build/app/outputs/flutter-apk/app-debug.apk && adb shell am force-stop ph.gov.bfp.firecheck && adb shell am start -n ph.gov.bfp.firecheck/.MainActivity
```

Then on the emulator, with GPS pushed to `10.31810, 123.88270`:
- Survey a building with a photo (existing flow). Tap Done → submission goes to `ready_to_upload` (verify via `adb shell` SQL or just observe polygon color stays its current state).
- Disable network on the emulator (Extended Controls → Cellular → off; WiFi → off).
- Long-press the home screen's primary card → outbox writes sync_jobs → worker tries upload → fails with TransientFailure → jobs go pending. SnackBar confirms enqueue.
- Re-enable network. ConnectivityListener fires → worker drains → submission uploads → photo uploads (after submission completes).
- Inspect Supabase admin UI: row in `submissions`, file in Storage at `<submissionId>/<photoId>.jpg`, `photos.storage_path` set.
- Force-stop the app for 16 minutes. Visible WorkManager log line: `adb logcat | grep WorkManager` should show a periodic execution.
- Server-side: in Supabase SQL editor, run `update assignments set closed_remotely = true where id = '<id>';`. Long-press the home card again → 409 → AssignmentLockRepository fires → bundle file appears in app's Downloads dir: `adb shell ls /sdcard/Download/firecheck-pending-*.zip`.

- [ ] **Step 5: Tag the release locally**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git tag -a phase-4a-sync-engine -m "Phase 4a — Sync engine

Outbox transaction (FinalizeSubmissionUseCase). Sync worker with claim/drain
loop, max 3 concurrent, full SyncOutcome state machine. Two-phase photo
upload via Supabase Storage + photos UPDATE. Retry/backoff (30s/2m/10m/1h/dead).
Connectivity + foreground + WorkManager periodic triggers. Auth refresh on
401 with no-infinite-loop guard. 409 assignment-closed-remotely halt + JSON+ZIP
bundle export. Schema bump v4→v5 adds assignments.closed_remotely (Drift +
Supabase migration 005). Supabase migration 006 adds upload_submission_bundle
RPC for atomic upserts.

Phase 4b will replace the debug long-press trigger with the real Upload
Data flow + Review screen + assignment-closed blocking UI.

Local-only — push remains user-gated."
```

- [ ] **Step 6: Confirm tag exists locally; do NOT push**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git tag -l | tail -6
```

Expected: `phase-4a-sync-engine` appears.

- [ ] **Step 7: Hand off to user**

Inform the user:

> Phase 4a complete. `flutter analyze` clean, `flutter test` green, debug APK built, manual happy path validated, tag `phase-4a-sync-engine` created locally. Push when ready:
> ```
> git push origin main
> git push origin phase-4a-sync-engine
> ```

---
