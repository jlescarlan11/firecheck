import 'dart:convert';

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
  }

  /// Legacy single-Point seeder. Slated for deletion once the long-press
  /// creation path is removed (see plan Task 10).
  Future<Feature> createNewFeature({
    required String assignmentId,
    required String featureType,
    required double lat,
    required double lng,
  }) {
    final geom = jsonEncode({
      'type': 'Point',
      'coordinates': [lng, lat],
    });
    return createFeature(
      assignmentId: assignmentId,
      featureType: featureType,
      geometryGeojson: geom,
    );
  }
}
