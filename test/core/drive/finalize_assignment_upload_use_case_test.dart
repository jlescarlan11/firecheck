import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/finalize_assignment_upload_use_case.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ignore: subtype_of_sealed_class
class _StubSupabase implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No supabase calls allowed in this test');
}

class _RecordingAuditRepo extends DriveUploadAuditRepository {
  _RecordingAuditRepo() : super(_StubSupabase());
  final List<Map<String, Object?>> recordCalls = [];

  @override
  Future<AuditProbeResult> listForAssignment(String assignmentId) async =>
      const AuditProbeAvailable([]);

  @override
  Future<void> record({
    required String assignmentId,
    required String uploadedBy,
    required String driveFolderPath,
    required String driveFolderUrl,
    required int fileCount,
  }) async {
    recordCalls.add({
      'assignmentId': assignmentId,
      'uploadedBy': uploadedBy,
      'driveFolderPath': driveFolderPath,
      'driveFolderUrl': driveFolderUrl,
      'fileCount': fileCount,
    });
  }
}

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seedAssignment(AppDatabase db, {required String id, String? name}) async {
  await db.into(db.assignments).insert(
        AssignmentsCompanion.insert(
          id: id,
          enumeratorId: 'enum-1',
          campaignId: 'camp-1',
          boundaryPolygonGeojson: '{"type":"Polygon","coordinates":[]}',
          name: Value(name),
          createdAt: DateTime(2026, 5, 20),
        ),
      );
}

Future<void> _seedJob(
  DriveUploadRepository repo, {
  required String id,
  required String assignmentId,
  required String status,
  String? driveFileId,
}) async {
  await repo.insertJob(
    id: id,
    assignmentId: assignmentId,
    filePath: '/tmp/$id.bin',
    fileType: DriveFileType.shapefile,
    fileName: '$id.shp',
    fileSizeBytes: 100,
    capturedAt: DateTime(2026, 5, 20),
  );
  if (status == DriveUploadJobStatus.completed) {
    await repo.markCompleted(id, driveFileId: driveFileId ?? 'drive-$id');
  } else if (status == DriveUploadJobStatus.failed) {
    await repo.markFailed(
      id,
      reason: 'network',
      retryCount: 1,
      nextRetryAt: DateTime(2026, 5, 20),
    );
  } else if (status == DriveUploadJobStatus.dead) {
    await repo.markDead(id, reason: 'too many retries');
  }
}

void main() {
  group('FinalizeAssignmentUploadUseCase', () {
    test('returns Empty when no jobs exist', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);
      final assignmentRepo = AssignmentRepository(db: db);
      final audit = _RecordingAuditRepo();
      final useCase = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: assignmentRepo,
        auditRepo: audit,
      );

      final outcome = await useCase.execute(assignmentId: 'a-1');

      expect(outcome, isA<DriveUploadEmpty>());
      expect(audit.recordCalls, isEmpty);
    });

    test('returns Incomplete when any job failed', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);
      final audit = _RecordingAuditRepo();
      final useCase = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: AssignmentRepository(db: db),
        auditRepo: audit,
      );
      await _seedAssignment(db, id: 'a-1', name: 'cebu');
      await _seedJob(repo, id: 'j1', assignmentId: 'a-1', status: DriveUploadJobStatus.completed);
      await _seedJob(repo, id: 'j2', assignmentId: 'a-1', status: DriveUploadJobStatus.failed);

      final outcome = await useCase.execute(
        assignmentId: 'a-1',
        uploaderId: 'user-1',
      );

      expect(outcome, isA<DriveUploadIncomplete>());
      final inc = outcome as DriveUploadIncomplete;
      expect(inc.completedCount, 1);
      expect(inc.failedCount, 1);
      expect(audit.recordCalls, isEmpty);
    });

    test('returns Succeeded, writes assignment + audit when all complete', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);
      final assignmentRepo = AssignmentRepository(db: db);
      final audit = _RecordingAuditRepo();
      final useCase = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: assignmentRepo,
        auditRepo: audit,
        now: () => DateTime.utc(2026, 5, 20, 10),
      );
      await _seedAssignment(db, id: 'a-1', name: 'cebu');
      await _seedJob(repo, id: 'j1', assignmentId: 'a-1', status: DriveUploadJobStatus.completed);
      await _seedJob(repo, id: 'j2', assignmentId: 'a-1', status: DriveUploadJobStatus.completed);

      final outcome = await useCase.execute(
        assignmentId: 'a-1',
        uploaderId: 'user-1',
      );

      expect(outcome, isA<DriveUploadSucceeded>());
      final ok = outcome as DriveUploadSucceeded;
      expect(ok.folderPath, 'firecheck/cebu/');
      expect(ok.completedCount, 2);
      expect(ok.confirmedAt, DateTime.utc(2026, 5, 20, 10));

      final persisted = await assignmentRepo.getDriveUploadResult('a-1');
      expect(persisted?.folderPath, 'firecheck/cebu/');
      expect(persisted?.confirmedAt.isAtSameMomentAs(DateTime.utc(2026, 5, 20, 10)),
          isTrue);

      expect(audit.recordCalls, hasLength(1));
      expect(audit.recordCalls.first['uploadedBy'], 'user-1');
      expect(audit.recordCalls.first['driveFolderPath'], 'firecheck/cebu/');
      expect(audit.recordCalls.first['fileCount'], 2);
    });

    test('omits audit record when uploaderId is null', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);
      final audit = _RecordingAuditRepo();
      final useCase = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: AssignmentRepository(db: db),
        auditRepo: audit,
      );
      await _seedAssignment(db, id: 'a-1', name: 'cebu');
      await _seedJob(repo, id: 'j1', assignmentId: 'a-1', status: DriveUploadJobStatus.completed);

      final outcome = await useCase.execute(assignmentId: 'a-1');

      expect(outcome, isA<DriveUploadSucceeded>());
      expect(audit.recordCalls, isEmpty);
    });

    test('falls back to assignment id when name is null', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);
      final assignmentRepo = AssignmentRepository(db: db);
      final audit = _RecordingAuditRepo();
      final useCase = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: assignmentRepo,
        auditRepo: audit,
        now: () => DateTime.utc(2026, 5, 20, 10),
      );
      // UUID-named / legacy assignment: name column is null.
      await _seedAssignment(db, id: 'a-uuid');
      await _seedJob(repo, id: 'j1', assignmentId: 'a-uuid', status: DriveUploadJobStatus.completed);

      final outcome = await useCase.execute(assignmentId: 'a-uuid', uploaderId: 'user-1');

      expect(outcome, isA<DriveUploadSucceeded>());
      expect((outcome as DriveUploadSucceeded).folderPath, 'firecheck/a-uuid/');
      expect(audit.recordCalls.single['driveFolderPath'], 'firecheck/a-uuid/');
    });

    test('persists worker-shaped path when enumeratorIdentifier is provided', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);
      final assignmentRepo = AssignmentRepository(db: db);
      final audit = _RecordingAuditRepo();
      final useCase = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: assignmentRepo,
        auditRepo: audit,
        now: () => DateTime.utc(2026, 5, 20, 10),
        enumeratorIdentifier: () => 'alice@example.com',
      );
      await _seedAssignment(db, id: 'a-1', name: 'cebu');
      await _seedJob(repo, id: 'j1', assignmentId: 'a-1', status: DriveUploadJobStatus.completed);

      final outcome = await useCase.execute(assignmentId: 'a-1', uploaderId: 'user-1');

      expect(outcome, isA<DriveUploadSucceeded>());
      expect(
        (outcome as DriveUploadSucceeded).folderPath,
        'firecheck/output/alice@example.com/cebu/',
      );
      expect(
        audit.recordCalls.single['driveFolderPath'],
        'firecheck/output/alice@example.com/cebu/',
      );
    });

    test('falls back to unknown-enumerator when identifier returns null', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);
      final assignmentRepo = AssignmentRepository(db: db);
      final audit = _RecordingAuditRepo();
      final useCase = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: assignmentRepo,
        auditRepo: audit,
        now: () => DateTime.utc(2026, 5, 20, 10),
        enumeratorIdentifier: () => null,
      );
      await _seedAssignment(db, id: 'a-1', name: 'cebu');
      await _seedJob(repo, id: 'j1', assignmentId: 'a-1', status: DriveUploadJobStatus.completed);

      final outcome = await useCase.execute(assignmentId: 'a-1');

      expect(
        (outcome as DriveUploadSucceeded).folderPath,
        'firecheck/output/unknown-enumerator/cebu/',
      );
    });

    test('executePending finalizes only assignments without confirmation', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);
      final assignmentRepo = AssignmentRepository(db: db);
      final audit = _RecordingAuditRepo();
      final useCase = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: assignmentRepo,
        auditRepo: audit,
        now: () => DateTime.utc(2026, 5, 20, 10),
      );
      await _seedAssignment(db, id: 'a-1', name: 'cebu');
      await _seedAssignment(db, id: 'a-2', name: 'manila');
      await _seedJob(repo, id: 'j1', assignmentId: 'a-1', status: DriveUploadJobStatus.completed);
      await _seedJob(repo, id: 'j2', assignmentId: 'a-2', status: DriveUploadJobStatus.completed);
      // a-2 is already confirmed — should be skipped.
      await assignmentRepo.setDriveUploadResult(
        assignmentId: 'a-2',
        driveFolderPath: 'firecheck/manila/',
        driveFolderUrl: '',
        driveUploadConfirmedAt: DateTime.utc(2026, 5, 19),
      );

      final outcomes = await useCase.executePending(uploaderId: 'user-1');

      expect(outcomes, hasLength(1));
      expect(outcomes.first, isA<DriveUploadSucceeded>());
      expect((outcomes.first as DriveUploadSucceeded).assignmentId, 'a-1');
    });
  });
}
