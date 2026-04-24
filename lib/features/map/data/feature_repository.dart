import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

class FeatureRepository {
  FeatureRepository(this._db);
  final AppDatabase _db;

  Stream<List<Feature>> watchFeaturesForAssignment(String assignmentId) {
    return (_db.select(_db.features)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .watch();
  }

  Future<Feature?> getFeature(String id) {
    return (_db.select(_db.features)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Recompute the feature's color-coded status from its submissions.
  ///   any submission with syncStatus='ready_to_upload' or further → 'complete'
  ///   any draft with an attribute row OR doesNotExist=true → 'in_progress'
  ///   else → 'unfilled'
  Future<void> markFeatureStatus(String featureId) async {
    final submissions = await (_db.select(_db.submissions)
          ..where((t) => t.featureId.equals(featureId)))
        .get();

    var status = 'unfilled';

    final anyComplete = submissions.any(
      (s) =>
          s.syncStatus == 'ready_to_upload' ||
          s.syncStatus == 'queued' ||
          s.syncStatus == 'uploaded',
    );
    if (anyComplete) {
      status = 'complete';
    } else if (submissions.isNotEmpty) {
      final attrIds = submissions.map((s) => s.id).toList();
      final attrs = await (_db.select(_db.buildingAttributes)
            ..where((t) => t.submissionId.isIn(attrIds)))
          .get();
      final anyInProgress =
          attrs.isNotEmpty || submissions.any((s) => s.doesNotExist);
      if (anyInProgress) status = 'in_progress';
    }

    await (_db.update(_db.features)..where((t) => t.id.equals(featureId)))
        .write(FeaturesCompanion(status: Value(status)));
  }
}
