import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class AssignmentRepository {
  AssignmentRepository({required this.client, required this.db});
  final SupabaseClient client;
  final AppDatabase db;

  /// One-shot fetch of the current enumerator's active assignment (and all
  /// its features + any ra_9514_types rows). Writes everything to Drift in
  /// a single transaction.
  Future<void> fetchAndUpsertCurrent() async {
    try {
      // Geometry columns are PostGIS `geography` and PostgREST serializes
      // them as EWKB hex by default. We add computed-column functions
      // (boundary_polygon_geojson, geometry_geojson) in migration 002 that
      // wrap ST_AsGeoJSON, and select those instead so the client gets
      // GeoJSON text directly.
      final assignmentRows = await client
          .from('assignments')
          .select(
            'id, enumerator_id, campaign_id, '
            'boundary_polygon_geojson, '
            'downloaded_at, submitted_at, status, created_at',
          )
          .order('created_at', ascending: false)
          .limit(1);

      if (assignmentRows.isEmpty) {
        // Failure is a sealed domain error class surfaced to callers the
        // same way exceptions flow. See Phase 0 auth_repository for the
        // established pattern.
        // ignore: only_throw_errors
        throw const ServerRejectedFailure(
          'No assignments assigned to you yet.',
          404,
        );
      }

      final assignment = assignmentRows.first;
      final assignmentId = assignment['id'] as String;

      final features = await client
          .from('features')
          .select(
            'id, assignment_id, feature_type, '
            'geometry_geojson, '
            'is_new, created_at',
          )
          .eq('assignment_id', assignmentId);

      final ra9514Rows = await client.from('ra_9514_types').select();

      await upsertBundle(
        assignment: assignment,
        features: List<Map<String, dynamic>>.from(features),
        ra9514Types: List<Map<String, dynamic>>.from(ra9514Rows),
      );
    } on PostgrestException catch (e) {
      if (e.code == '401') {
        // Failure is a sealed domain error class surfaced to callers the
        // same way exceptions flow. See Phase 0 auth_repository for the
        // established pattern.
        // ignore: only_throw_errors
        throw AuthFailure(e.message);
      }
      // Failure is a sealed domain error class surfaced to callers the
      // same way exceptions flow. See Phase 0 auth_repository for the
      // established pattern.
      // ignore: only_throw_errors
      throw ServerRejectedFailure(
        e.message,
        int.tryParse(e.code ?? '0') ?? 500,
      );
    }
  }

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
