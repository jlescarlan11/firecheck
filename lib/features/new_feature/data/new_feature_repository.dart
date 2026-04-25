import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:uuid/uuid.dart';

class NewFeatureRepository {
  NewFeatureRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

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
    return _db.into(_db.features).insertReturning(
          FeaturesCompanion.insert(
            id: _uuid.v4(),
            assignmentId: assignmentId,
            featureType: featureType,
            geometryGeojson: geom,
            isNew: const Value(true),
            createdAt: DateTime.now(),
          ),
        );
  }
}
