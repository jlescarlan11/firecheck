import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

const polygon =
    '{"type":"Polygon","coordinates":[[[123,10],[123.001,10],[123.001,10.001],[123,10]]]}';
Future<Assignment> seedComparison(AppDatabase db) async {
  final now = DateTime.utc(2026);
  await db.into(db.assignments).insert(
        AssignmentsCompanion.insert(
          id: 'a',
          enumeratorId: 'u',
          campaignId: 'c',
          boundaryPolygonGeojson: polygon,
          downloadedAt: Value(now),
          createdAt: now,
        ),
      );
  await db.into(db.assignmentSelections).insert(
        AssignmentSelectionsCompanion.insert(
          userId: 'u',
          assignmentId: 'a',
          selectedAt: now,
        ),
      );
  for (final id in ['mine', 'existing']) {
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: id,
            assignmentId: 'a',
            featureType: 'building',
            geometryGeojson: polygon,
            pendingDedupOf: Value(id == 'mine' ? 'existing' : null),
            createdAt: now,
          ),
        );
  }
  return db.select(db.assignments).getSingle();
}
