import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';

typedef TriggerSync = Future<void> Function();

class StartUploadResult {
  const StartUploadResult({required this.finalizedCount});
  final int finalizedCount;
}

class StartUploadUseCase {
  StartUploadUseCase({
    required this.db,
    required this.finalize,
    required this.triggerNow,
  });
  final AppDatabase db;
  final FinalizeSubmissionUseCase finalize;
  final TriggerSync triggerNow;

  /// Finalizes every `ready_to_upload` submission belonging to this
  /// assignment, then triggers the sync worker. Idempotent — already-
  /// queued or already-uploaded submissions are skipped.
  Future<StartUploadResult> execute(String assignmentId) async {
    final ready = await (db.select(db.submissions).join([
      innerJoin(db.features, db.features.id.equalsExp(db.submissions.featureId)),
    ])
          ..where(
            db.features.assignmentId.equals(assignmentId) &
                db.submissions.syncStatus.equals('ready_to_upload'),
          ))
        .map((row) => row.readTable(db.submissions))
        .get();

    for (final s in ready) {
      await finalize.execute(s.id);
    }
    await triggerNow();
    return StartUploadResult(finalizedCount: ready.length);
  }
}
