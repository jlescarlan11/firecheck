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
}
