import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

/// Read/write surface for the local mirror of remote canonical state.
///
/// Inputs (rows from `fetch_remote_attributions` / `fetch_remote_new_features`
/// or from realtime payloads) all flow through [upsertAttribution] and
/// [upsertNewFeature], so merge semantics are identical regardless of
/// source. This matches the spec's `cacheUpsertFromServerRows` invariant.
class RemoteAttributionsCacheRepository {
  RemoteAttributionsCacheRepository(this._db);
  final AppDatabase _db;

  /// Upserts one server submission row into the cache. The shape matches
  /// what `fetch_remote_attributions` returns.
  Future<void> upsertAttribution(
    Map<String, dynamic> row, {
    DateTime? now,
  }) async {
    final cachedAt = now ?? DateTime.now();
    await _db
        .into(_db.remoteAttributionsCache)
        .insertOnConflictUpdate(_attributionRow(row, cachedAt));
  }

  /// Bulk variant for cold-open / delta pulls.
  Future<void> upsertAttributionsBatch(
    Iterable<Map<String, dynamic>> rows, {
    DateTime? now,
  }) async {
    final cachedAt = now ?? DateTime.now();
    final companions =
        rows.map((r) => _attributionRow(r, cachedAt)).toList(growable: false);
    if (companions.isEmpty) return;
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.remoteAttributionsCache, companions);
    });
  }

  Future<void> upsertNewFeature(
    Map<String, dynamic> row, {
    DateTime? now,
  }) async {
    final cachedAt = now ?? DateTime.now();
    await _db
        .into(_db.remoteNewFeaturesCache)
        .insertOnConflictUpdate(_newFeatureRow(row, cachedAt));
  }

  Future<void> upsertNewFeaturesBatch(
    Iterable<Map<String, dynamic>> rows, {
    DateTime? now,
  }) async {
    final cachedAt = now ?? DateTime.now();
    final companions =
        rows.map((r) => _newFeatureRow(r, cachedAt)).toList(growable: false);
    if (companions.isEmpty) return;
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.remoteNewFeaturesCache, companions);
    });
  }

  /// Commits a requested assignment's complete legacy pull as one unit.
  /// Validate both result sets before any cache or cursor can change.
  Future<void> applyPull(
    String assignmentId, {
    required Iterable<Map<String, dynamic>> attributions,
    required Iterable<Map<String, dynamic>> newFeatures,
    required DateTime? attributionsCursor,
    required DateTime? newFeaturesCursor,
  }) async {
    if (assignmentId.trim().isEmpty) {
      throw StateError('Missing requested assignment identity');
    }
    final cachedAt = DateTime.now();
    final attributionRows = attributions
        .map(
          (row) =>
              _attributionRow(_bindAssignment(row, assignmentId), cachedAt),
        )
        .toList(growable: false);
    final featureRows = newFeatures
        .map(
          (row) => _newFeatureRow(_bindAssignment(row, assignmentId), cachedAt),
        )
        .toList(growable: false);
    await _db.transaction(() async {
      await _db.batch((batch) {
        batch
          ..insertAllOnConflictUpdate(
            _db.remoteAttributionsCache,
            attributionRows,
          )
          ..insertAllOnConflictUpdate(
            _db.remoteNewFeaturesCache,
            featureRows,
          );
      });
      await setAttributionsCursor(assignmentId, attributionsCursor);
      await setNewFeaturesCursor(assignmentId, newFeaturesCursor);
    });
  }

  Map<String, dynamic> _bindAssignment(
    Map<String, dynamic> row,
    String assignmentId,
  ) {
    for (final alias in ['__assignment_id', 'assignment_id']) {
      final value = _optionalAssignmentId(row, alias);
      if (value != null && value != assignmentId) {
        throw StateError('Remote row belongs to another assignment');
      }
    }
    return {...row, '__assignment_id': assignmentId};
  }

  // -- Cursor management ------------------------------------------------

  Future<AssignmentSyncCursor?> getCursor(String assignmentId) {
    return (_db.select(_db.assignmentSyncCursors)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .getSingleOrNull();
  }

  Future<void> setAttributionsCursor(
    String assignmentId,
    DateTime? cursor,
  ) async {
    await _db.into(_db.assignmentSyncCursors).insertOnConflictUpdate(
          AssignmentSyncCursorsCompanion(
            assignmentId: Value(assignmentId),
            attributionsLastSyncAt: Value(cursor),
          ),
        );
  }

  Future<void> setNewFeaturesCursor(
    String assignmentId,
    DateTime? cursor,
  ) async {
    await _db.into(_db.assignmentSyncCursors).insertOnConflictUpdate(
          AssignmentSyncCursorsCompanion(
            assignmentId: Value(assignmentId),
            newFeaturesLastSyncAt: Value(cursor),
          ),
        );
  }

  // -- Reads ------------------------------------------------------------

  /// All currently-canonical remote attributions for an assignment.
  Future<List<RemoteAttributionsCacheData>> liveAttributionsFor(
    String assignmentId,
  ) {
    return (_db.select(_db.remoteAttributionsCache)
          ..where(
            (t) =>
                t.assignmentId.equals(assignmentId) & t.supersededAt.isNull(),
          ))
        .get();
  }

  Future<List<RemoteAttributionsCacheData>> attributionsForFeature(
    String featureId,
  ) {
    return (_db.select(_db.remoteAttributionsCache)
          ..where((t) => t.featureId.equals(featureId))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.submittedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  Future<List<RemoteNewFeaturesCacheData>> liveNewFeaturesFor(
    String assignmentId,
  ) {
    return (_db.select(_db.remoteNewFeaturesCache)
          ..where(
            (t) =>
                t.assignmentId.equals(assignmentId) & t.supersededAt.isNull(),
          ))
        .get();
  }

  /// Clears all cached state for the given assignment. Used on logout and
  /// on membership-revocation detection (spec §"Error Handling").
  Future<void> clearAssignment(String assignmentId) async {
    await _db.transaction(() async {
      await (_db.delete(_db.remoteAttributionsCache)
            ..where((t) => t.assignmentId.equals(assignmentId)))
          .go();
      await (_db.delete(_db.remoteNewFeaturesCache)
            ..where((t) => t.assignmentId.equals(assignmentId)))
          .go();
      await (_db.delete(_db.assignmentSyncCursors)
            ..where((t) => t.assignmentId.equals(assignmentId)))
          .go();
    });
  }

  // -- Row builders -----------------------------------------------------

  RemoteAttributionsCacheCompanion _attributionRow(
    Map<String, dynamic> row,
    DateTime cachedAt,
  ) {
    return RemoteAttributionsCacheCompanion(
      id: Value(row['id'] as String),
      assignmentId: Value(_assignmentIdFromRow(row)),
      featureId: Value(row['feature_id'] as String),
      featureType: Value(row['feature_type'] as String),
      attributeValuesJson: Value(
        jsonEncode(row['attribute_values'] ?? const <String, dynamic>{}),
      ),
      submittedBy: Value(row['submitted_by'] as String?),
      submittedAt: Value(_parseDate(row['submitted_at'])),
      supersededAt: Value(_parseNullableDate(row['superseded_at'])),
      supersededById: Value(row['superseded_by_id'] as String?),
      updatedAt: Value(_parseDate(row['updated_at'])),
      cachedAt: Value(cachedAt),
    );
  }

  RemoteNewFeaturesCacheCompanion _newFeatureRow(
    Map<String, dynamic> row,
    DateTime cachedAt,
  ) {
    return RemoteNewFeaturesCacheCompanion(
      id: Value(row['id'] as String),
      assignmentId: Value(_assignmentIdFromRow(row)),
      featureType: Value(row['feature_type'] as String),
      geometryGeojson: Value(_geojsonAsString(row['geometry_geojson'])),
      centroidLat: Value((row['centroid_lat'] as num).toDouble()),
      centroidLng: Value((row['centroid_lng'] as num).toDouble()),
      submittedBy: Value(row['submitted_by'] as String?),
      submittedAt: Value(_parseDate(row['submitted_at'])),
      possibleDuplicateOf: Value(row['possible_duplicate_of'] as String?),
      dedupReviewedAt: Value(_parseNullableDate(row['dedup_reviewed_at'])),
      supersededAt: Value(_parseNullableDate(row['superseded_at'])),
      supersededById: Value(row['superseded_by_id'] as String?),
      updatedAt: Value(_parseDate(row['updated_at'])),
      cachedAt: Value(cachedAt),
    );
  }

  /// `fetch_remote_attributions` doesn't include `assignment_id` on each row
  /// (the call already filters by it). Realtime payloads on `public.submissions`
  /// also don't have it directly. We accept it as a side-channel and stash
  /// it via an `__assignment_id` synthetic key when the caller knows it.
  /// When both aliases exist they must identify the same assignment.
  String _assignmentIdFromRow(Map<String, dynamic> row) {
    final explicit = _optionalAssignmentId(row, '__assignment_id');
    final inline = _optionalAssignmentId(row, 'assignment_id');
    if (explicit != null && inline != null && explicit != inline) {
      throw StateError('Conflicting attribution assignment identity');
    }
    final assignment = explicit ?? inline;
    if (assignment == null) {
      throw StateError('Attribution row missing assignment identity');
    }
    return assignment;
  }

  String? _optionalAssignmentId(Map<String, dynamic> row, String key) {
    if (!row.containsKey(key)) return null;
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw StateError('Invalid assignment identity in $key');
    }
    return value;
  }

  String _geojsonAsString(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    return jsonEncode(v);
  }

  DateTime _parseDate(Object? v) {
    if (v is DateTime) return v;
    return DateTime.parse(v! as String).toUtc();
  }

  DateTime? _parseNullableDate(Object? v) {
    if (v == null) return null;
    return _parseDate(v);
  }
}
