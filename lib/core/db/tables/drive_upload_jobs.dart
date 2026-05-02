import 'package:drift/drift.dart';

@TableIndex(name: 'drive_upload_jobs_status_idx', columns: {#status, #nextRetryAt})
@TableIndex(name: 'drive_upload_jobs_assignment_idx', columns: {#assignmentId})
class DriveUploadJobs extends Table {
  TextColumn get id => text()();
  TextColumn get assignmentId => text()();
  TextColumn get filePath => text()();
  TextColumn get fileType => text()(); // 'photo' | 'shapefile'
  TextColumn get fileName => text()();
  IntColumn get fileSizeBytes => integer()();
  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending|uploading|completed|failed|dead
  TextColumn get resumableUri => text().nullable()();
  TextColumn get driveFileId => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get failureReason => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
