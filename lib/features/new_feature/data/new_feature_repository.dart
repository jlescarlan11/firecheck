import 'package:firecheck/features/assignment/data/assignment_geometry_guard.dart';
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:uuid/uuid.dart';

class NewFeatureRepository {
  NewFeatureRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Generic creator used by the sketch-on-create flow. The caller (the
  /// geometry editor) is responsible for serializing the right GeoJSON shape
  /// for [featureType].
  Future<Feature> createFeature({
    required String assignmentId,
    required String featureType,
    required String geometryGeojson,
  }) {
    return _db.transaction(() async {
      await validateAssignmentGeometry(_db, assignmentId, geometryGeojson);
      return _db.into(_db.features).insertReturning(
            FeaturesCompanion.insert(
              id: _uuid.v4(),
              assignmentId: assignmentId,
              featureType: featureType,
              geometryGeojson: geometryGeojson,
              isNew: const Value(true),
              createdAt: DateTime.now(),
            ),
          );
    });
  }
}
