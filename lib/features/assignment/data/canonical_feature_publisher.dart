// lib/features/assignment/data/canonical_feature_publisher.dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class CanonicalFeaturePublisher {
  /// Publishes the canonical shapefile features for [assignmentId] to the
  /// remote DB so subsequent attribution uploads can satisfy the
  /// features → assignments membership join. Idempotent: subsequent
  /// calls with the same data are no-ops via ON CONFLICT DO NOTHING.
  Future<void> publish(String assignmentId);
}

class SupabaseCanonicalFeaturePublisher implements CanonicalFeaturePublisher {
  SupabaseCanonicalFeaturePublisher({
    required SupabaseClient client,
    required AppDatabase db,
  })  : _client = client,
        _db = db;

  final SupabaseClient _client;
  final AppDatabase _db;

  @override
  Future<void> publish(String assignmentId) async {
    final rows = await (_db.select(_db.features)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .get();
    if (rows.isEmpty) return;

    final payload = rows
        .map((f) => {
              'id': f.id,
              'feature_type': f.featureType,
              'geometry_geojson': f.geometryGeojson,
            })
        .toList();

    try {
      await _client.rpc('bulk_upsert_features', params: {
        'p_assignment_id': assignmentId,
        'p_features': payload,
      });
    } catch (_) {
      // Non-fatal — the user can still see the map. The next
      // attribution upload will surface a clearer error if features
      // never made it server-side.
    }
  }
}

class NoopCanonicalFeaturePublisher implements CanonicalFeaturePublisher {
  const NoopCanonicalFeaturePublisher();

  @override
  Future<void> publish(String _) async {}
}
