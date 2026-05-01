import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class AssignmentRepository {
  AssignmentRepository({this.client, required this.db});
  final SupabaseClient? client;
  final AppDatabase db;

  /// Writes an assignment + its features + any ra_9514_types rows in a single
  /// Drift transaction. Exposed separately so tests don't need to wire the
  /// full Supabase query builder chain.
  Future<void> upsertBundle({
    required Map<String, dynamic> assignment,
    required List<Map<String, dynamic>> features,
    required List<Map<String, dynamic>> ra9514Types,
  }) async {
    await db.transaction(() async {
      await db.into(db.assignments).insertOnConflictUpdate(
            AssignmentsCompanion.insert(
              id: assignment['id'] as String,
              enumeratorId: assignment['enumerator_id'] as String,
              campaignId: assignment['campaign_id'] as String,
              // Accept either the legacy `boundary_polygon` raw key (used by
              // tests with hand-crafted maps) or the computed-column key
              // `boundary_polygon_geojson` (used by the production fetch).
              boundaryPolygonGeojson: (assignment['boundary_polygon_geojson'] ??
                      assignment['boundary_polygon'] ??
                      '')
                  .toString(),
              downloadedAt: Value(DateTime.now()),
              status: Value((assignment['status'] ?? 'assigned') as String),
              createdAt: DateTime.parse(assignment['created_at'] as String),
            ),
          );

      for (final f in features) {
        await db.into(db.features).insertOnConflictUpdate(
              FeaturesCompanion.insert(
                id: f['id'] as String,
                assignmentId: f['assignment_id'] as String,
                featureType: f['feature_type'] as String,
                geometryGeojson:
                    (f['geometry_geojson'] ?? f['geometry'] ?? '').toString(),
                isNew: Value((f['is_new'] ?? false) as bool),
                createdAt: DateTime.parse(f['created_at'] as String),
              ),
            );
      }

      for (final t in ra9514Types) {
        await db.into(db.ra9514Types).insertOnConflictUpdate(
              Ra9514TypesCompanion.insert(
                code: t['code'] as String,
                labelEn: t['label_en'] as String,
                labelTl: t['label_tl'] as String,
                sortOrder: Value((t['sort_order'] ?? 0) as int),
              ),
            );
      }
    });
  }

  Future<String?> getDriveModifiedTime(String assignmentId) async {
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    return row?.driveModifiedTime;
  }

  Future<Assignment?> getCurrentAssignment() async {
    final rows = await (db.select(db.assignments)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .get();
    return rows.firstOrNull;
  }

  Stream<Assignment?> watchCurrentAssignment() {
    return (db.select(db.assignments)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .watchSingleOrNull();
  }
}
