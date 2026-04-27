import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
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
      ),);
  await db.into(db.features).insert(FeaturesCompanion.insert(
        id: 'f1',
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: '{}',
        createdAt: now,
      ),);
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
        id: 's1',
        featureId: 'f1',
        createdAt: now,
        updatedAt: now,
        syncStatus: const Value('ready_to_upload'),
      ),);
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
