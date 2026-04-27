import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/features/review/presentation/sub/start_upload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyTrigger {
  int count = 0;
  Future<void> call() async => count++;
}

void main() {
  late AppDatabase db;
  late _SpyTrigger trigger;
  late StartUploadUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    trigger = _SpyTrigger();
    useCase = StartUploadUseCase(
      db: db,
      finalize: FinalizeSubmissionUseCase(db),
      triggerNow: trigger.call,
    );
  });
  tearDown(() async => db.close());

  Future<void> _seedAssignment() async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f-1',
          assignmentId: 'a-1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
  }

  Future<void> _seedSubmission(String id, String status) async {
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: id,
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          syncStatus: Value(status),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ));
  }

  test('finalizes only ready_to_upload submissions, returns count', () async {
    await _seedAssignment();
    await _seedSubmission('s-ready', 'ready_to_upload');
    await _seedSubmission('s-draft', 'draft');
    await _seedSubmission('s-uploaded', 'uploaded');

    final result = await useCase.execute('a-1');
    expect(result.finalizedCount, 1);
    expect(trigger.count, 1);

    final ready = await (db.select(db.submissions)
          ..where((t) => t.id.equals('s-ready')))
        .getSingle();
    expect(ready.syncStatus, 'queued'); // FinalizeUseCase moves it to queued
  });

  test('idempotent — re-running with no remaining ready_to_upload returns 0', () async {
    await _seedAssignment();
    await _seedSubmission('s-1', 'ready_to_upload');
    await useCase.execute('a-1');
    final result = await useCase.execute('a-1');
    expect(result.finalizedCount, 0);
  });
}
