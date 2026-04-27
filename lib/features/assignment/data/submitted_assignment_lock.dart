import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';

class SubmittedAssignmentLock {
  SubmittedAssignmentLock(this._db);
  final AppDatabase _db;

  /// Watches sync_jobs + assignments for the assignment. Whenever the set
  /// of non-terminal jobs (any of {pending, in_progress, dead}) reaches
  /// zero AND the assignment hasn't been stamped, stamps
  /// `assignments.submitted_at = DateTime.now()`. Idempotent.
  ///
  /// Counts submission, photo, AND new_feature jobs (a stuck photo or
  /// new-feature job must NOT silently allow stamping).
  Stream<void> watchAndStamp(String assignmentId) {
    late StreamController<void> controller;
    StreamSubscription<dynamic>? subJ;
    StreamSubscription<dynamic>? subA;

    void onEvent(_) {
      _shouldStampNow(assignmentId).then((stamp) async {
        if (stamp) {
          await (_db.update(_db.assignments)
                ..where((t) => t.id.equals(assignmentId)))
              .write(AssignmentsCompanion(submittedAt: Value(DateTime.now())));
        }
        if (!controller.isClosed) controller.add(null);
      });
    }

    controller = StreamController<void>(
      onListen: () {
        subJ = _db.select(_db.syncJobs).watch().listen(onEvent);
        subA = _db.select(_db.assignments).watch().listen(onEvent);
      },
      onCancel: () async {
        await subJ?.cancel();
        await subA?.cancel();
        await controller.close();
      },
    );

    return controller.stream;
  }

  Future<bool> _shouldStampNow(String assignmentId) async {
    final assignment = await (_db.select(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    if (assignment == null || assignment.submittedAt != null) return false;
    // Bug 12 (caught during the first manual happy path): the prior version
    // only required "no non-terminal jobs". An assignment that has had no
    // Start Upload tap yet has zero sync_jobs at all — vacuously satisfying
    // that condition — so submitted_at would stamp the moment a draft was
    // saved. We now also require AT LEAST ONE success job to exist, so the
    // lock fires only after the worker has actually drained an upload.
    final counts = await _db.customSelect(
      '''
      SELECT
        SUM(CASE WHEN j.status IN ('pending', 'in_progress', 'dead') THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN j.status = 'success' THEN 1 ELSE 0 END) as success
      FROM sync_jobs j
      WHERE
        (j.entity_type = 'submission' AND j.entity_id IN (
          SELECT s.id FROM submissions s
          JOIN features f ON f.id = s.feature_id
          WHERE f.assignment_id = ?
        ))
        OR (j.entity_type = 'photo' AND j.entity_id IN (
          SELECT p.id FROM photos p
          JOIN submissions s ON s.id = p.submission_id
          JOIN features f ON f.id = s.feature_id
          WHERE f.assignment_id = ?
        ))
        OR (j.entity_type = 'new_feature' AND j.entity_id IN (
          SELECT id FROM features WHERE assignment_id = ?
        ))
      ''',
      variables: [
        Variable.withString(assignmentId),
        Variable.withString(assignmentId),
        Variable.withString(assignmentId),
      ],
    ).getSingle();
    final active = counts.read<int?>('active') ?? 0;
    final success = counts.read<int?>('success') ?? 0;
    return active == 0 && success > 0;
  }
}
