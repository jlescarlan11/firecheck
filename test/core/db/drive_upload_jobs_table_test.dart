import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drive_upload_jobs table is accessible and accepts inserts', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.driveUploadJobs, isNotNull);

    final id = await db.into(db.driveUploadJobs).insertReturning(
          DriveUploadJobsCompanion.insert(
            id: '1',
            assignmentId: 'a-001',
            filePath: '/photos/p1.jpg',
            fileType: 'photo',
            fileName: 'p1.jpg',
            fileSizeBytes: 1024,
            capturedAt: DateTime(2026, 5, 2),
            createdAt: DateTime(2026, 5, 2),
          ),
        );

    expect(id.status, 'pending');
    expect(id.retryCount, 0);
    expect(id.resumableUri, isNull);
  });
}
