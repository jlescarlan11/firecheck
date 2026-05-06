import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:flutter/foundation.dart';

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
    // --- diagnostic block: remove once root cause is identified ---
    final allJobs = await db.select(db.syncJobs).get();
    debugPrint('[StartUpload][diag] sync_jobs total: ${allJobs.length}');
    for (final j in allJobs.take(10)) {
      debugPrint(
        '[StartUpload][diag] job id=${j.id} entityType=${j.entityType} '
        'entityId=${j.entityId} status=${j.status} attempts=${j.attempts} '
        'lastError=${j.lastError} nextRetryAt=${j.nextRetryAt} '
        'createdAt=${j.createdAt} blocksOnSubmissionId=${j.blocksOnSubmissionId}',
      );
    }
    final allSubs = await (db.select(db.submissions).join([
      innerJoin(
        db.features,
        db.features.id.equalsExp(db.submissions.featureId),
      ),
    ])
          ..where(db.features.assignmentId.equals(assignmentId)))
        .map((row) => row.readTable(db.submissions))
        .get();
    debugPrint(
      '[StartUpload][diag] submissions for $assignmentId: ${allSubs.length}',
    );
    for (final s in allSubs.take(10)) {
      debugPrint('[StartUpload][diag] sub id=${s.id} syncStatus=${s.syncStatus}');
    }
    final allFeatures = await (db.select(db.features)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .get();
    debugPrint(
      '[StartUpload][diag] features for $assignmentId: ${allFeatures.length}',
    );
    // --- end diagnostic block ---

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
