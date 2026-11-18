import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/remote_attributions_cache_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

typedef FetchSharedChanges = Future<Map<String, dynamic>> Function(
    String assignmentId, int after, int? through);

/// Realtime is only a wakeup: this durable feed is also pulled on resume,
/// reconnect and periodic ticks. A failed bundle never advances the cursor.
class SharedMapSync {
  SharedMapSync(
      {required this.db, required this.accountId, required this.fetch});
  final AppDatabase db;
  final String accountId;
  final FetchSharedChanges fetch;
  final Map<String, Future<bool>> _pulls = {};

  static FetchSharedChanges supabase(SupabaseClient client) {
    final account = client.auth.currentUser?.id;
    return (id, after, through) async {
      if (account == null || client.auth.currentUser?.id != account) {
        throw StateError('Account changed during shared map sync');
      }
      try {
        final raw =
            await client.rpc<dynamic>('get_shared_map_changes', params: {
          'p_assignment_id': id,
          'p_after_revision': after,
          'p_through_revision': through,
        });
        if (client.auth.currentUser?.id != account)
          throw StateError('Account changed during shared map sync');
        return Map<String, dynamic>.from(raw as Map<dynamic, dynamic>);
      } on PostgrestException catch (e) {
        // Compatibility with a server that has not installed the migration.
        // Permission/network/validation failures must never downgrade sync.
        if (e.code == 'PGRST202') return {'enabled': false};
        rethrow;
      }
    };
  }

  Future<bool> pull(String assignmentId) => _pulls.putIfAbsent(
        assignmentId,
        () => _pull(assignmentId).whenComplete(() {
          _pulls.remove(assignmentId);
        }),
      );

  Future<bool> _pull(String assignmentId) async {
    var cursor = await (db.select(db.sharedMapCursors)
          ..where((t) =>
              t.accountId.equals(accountId) &
              t.assignmentId.equals(assignmentId)))
        .getSingleOrNull();
    var after = cursor?.revision ?? 0;
    int? through;
    while (true) {
      final page = await fetch(assignmentId, after, through);
      if (page['enabled'] != true) {
        if (cursor != null)
          throw StateError('Shared map sync temporarily unavailable');
        return false;
      }
      final high = (page['through_revision'] as num).toInt();
      if (high < after || (through != null && high != through)) {
        throw StateError('Shared map high-water revision changed');
      }
      through = high;
      final bundles = page['bundles'] as List;
      for (final raw in bundles) {
        final bundle = Map<String, dynamic>.from(raw as Map<dynamic, dynamic>);
        final revision = (bundle['revision'] as num).toInt();
        if (revision != after + 1 || revision > high) {
          throw StateError('Shared map revision gap');
        }
        await applyBundle(assignmentId, revision,
            (bundle['features'] as List).cast<Map<dynamic, dynamic>>());
        after = revision;
      }
      if ((page['next_revision'] as num).toInt() != after) {
        throw StateError('Shared map cursor does not match applied bundles');
      }
      if (page['has_more'] != true) {
        if (after != high) throw StateError('Incomplete shared map page');
        // Remember capability even for an empty assignment.
        if (after == 0) await _saveCursor(assignmentId, 0);
        await reconcile(assignmentId);
        return true;
      }
      if (bundles.isEmpty) throw StateError('Empty shared map continuation');
    }
  }

  /// Installs a verified immutable package without clearing private work.
  Future<void> installSnapshot(Map<String, dynamic> snapshot) async {
    if (snapshot['schema_version'] != 1)
      throw const FormatException('Unsupported shared map package');
    final aid = snapshot['assignment_id'] as String;
    final revision = (snapshot['revision'] as num).toInt();
    final meta = Map<String, dynamic>.from(
        snapshot['assignment'] as Map<dynamic, dynamic>);
    if (meta['id'] != aid || revision < 0)
      throw const FormatException('Invalid shared map identity');
    await db.transaction(() async {
      final cursor = await (db.select(db.sharedMapCursors)
            ..where((t) =>
                t.accountId.equals(accountId) & t.assignmentId.equals(aid)))
          .getSingleOrNull();
      if (cursor != null && cursor.revision > revision) return;
      final old = await (db.select(db.assignments)
            ..where((t) => t.id.equals(aid)))
          .getSingleOrNull();
      await db
          .into(db.assignments)
          .insertOnConflictUpdate(AssignmentsCompanion.insert(
            id: aid,
            enumeratorId: old?.enumeratorId ?? accountId,
            campaignId: meta['campaign_id'] as String,
            boundaryPolygonGeojson: jsonEncode(meta['boundary']),
            boundarySource: const Value('server'),
            name: Value(meta['name'] as String?),
            downloadedAt: Value(DateTime.now()),
            createdAt: old?.createdAt ?? DateTime.now(),
          ));
      final incoming =
          (snapshot['features'] as List).cast<Map<dynamic, dynamic>>();
      final ids = incoming.map((r) => r['id'] as String).toSet();
      final previous = await (db.select(db.sharedMapFeatures)
            ..where((t) =>
                t.accountId.equals(accountId) & t.assignmentId.equals(aid)))
          .get();
      for (final f in previous.where((f) => !ids.contains(f.featureId))) {
        await _projectFeature(aid, {'id': f.featureId, 'deleted': true});
      }
      await (db.delete(db.sharedMapFeatures)
            ..where((t) =>
                t.accountId.equals(accountId) & t.assignmentId.equals(aid)))
          .go();
      for (final raw in incoming) {
        final row = Map<String, dynamic>.from(raw);
        if (row['assignment_id'] != aid)
          throw const FormatException('Wrong assignment in snapshot');
        await db.into(db.sharedMapFeatures).insert(
            SharedMapFeaturesCompanion.insert(
                accountId: accountId,
                assignmentId: aid,
                featureId: row['id'] as String,
                revision: revision,
                payloadJson: jsonEncode(row)));
        if (await _projectFeature(aid, row))
          await _projected(aid, row['id'] as String);
      }
      await _saveCursor(aid, revision);
    });
  }

  Future<void> _saveCursor(String assignmentId, int revision) =>
      db.into(db.sharedMapCursors).insertOnConflictUpdate(
            SharedMapCursorsCompanion.insert(
                accountId: accountId,
                assignmentId: assignmentId,
                revision: Value(revision)),
          );

  Future<void> applyBundle(String assignmentId, int revision,
      List<Map<dynamic, dynamic>> features) async {
    await db.transaction(() async {
      final current = await (db.select(db.sharedMapCursors)
            ..where((t) =>
                t.accountId.equals(accountId) &
                t.assignmentId.equals(assignmentId)))
          .getSingleOrNull();
      if ((current?.revision ?? 0) >= revision) return;
      if (revision != (current?.revision ?? 0) + 1) {
        throw StateError('Shared map revision gap');
      }
      for (final raw in features) {
        final row = Map<String, dynamic>.from(raw);
        if (row['assignment_id'] != assignmentId) {
          throw StateError('Shared map assignment mismatch');
        }
        final id = row['id'] as String;
        await db.into(db.sharedMapFeatures).insertOnConflictUpdate(
              SharedMapFeaturesCompanion.insert(
                  accountId: accountId,
                  assignmentId: assignmentId,
                  featureId: id,
                  revision: revision,
                  payloadJson: jsonEncode(row),
                  pendingProjection: const Value(true)),
            );
        if (await _projectFeature(assignmentId, row))
          await _projected(assignmentId, id);
      }
      await _saveCursor(assignmentId, revision);
    });
  }

  Future<bool> _projectFeature(
      String assignmentId, Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final old = await (db.select(db.features)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (old != null && old.assignmentId != assignmentId) {
      throw StateError('Shared feature belongs to another assignment');
    }
    final cache = RemoteAttributionsCacheRepository(db);
    final observations = (row['submissions'] as List? ?? [])
        .cast<Map<dynamic, dynamic>>()
        .map((s) => _observationRow(s, assignmentId, id))
        .toList(growable: false);
    // Replacement per feature handles supersedes and physical deletions too.
    await (db.delete(db.remoteAttributionsCache)
          ..where((t) =>
              t.assignmentId.equals(assignmentId) & t.featureId.equals(id)))
        .go();
    await (db.delete(db.remoteNewFeaturesCache)
          ..where((t) => t.assignmentId.equals(assignmentId) & t.id.equals(id)))
        .go();
    final removed = row['deleted'] == true || row['pending_dedup'] == true;
    if (!removed) {
      await cache.upsertAttributionsBatch(observations);
    }
    final dirty = await (db.select(db.submissions)
          ..where((t) =>
              t.featureId.equals(id) &
              t.syncStatus.isNotIn(['uploaded', 'withdrawn']))
          ..limit(1))
        .getSingleOrNull();
    final geometry = await (db.select(db.featureGeometryRevisions)
          ..where((t) =>
              t.featureId.equals(id) &
              t.syncStatus.isNotIn(['uploaded', 'discarded']))
          ..limit(1))
        .getSingleOrNull();
    // Keep pending geometry and drafts exactly as they were. The mirror above
    // retains the new base so a later conflict is visible and recoverable.
    if (dirty != null || geometry != null) return false;
    if (removed) {
      await (db.update(db.features)
            ..where(
                (t) => t.id.equals(id) & t.assignmentId.equals(assignmentId)))
          .write(FeaturesCompanion(mergedIntoId: Value(id)));
      return true;
    }
    await db.into(db.features).insertOnConflictUpdate(FeaturesCompanion.insert(
          id: id,
          assignmentId: assignmentId,
          featureType: row['feature_type'] as String,
          geometryGeojson: jsonEncode(row['geometry_geojson']),
          isNew: Value(row['is_new'] == true),
          createdAt: DateTime.parse(row['created_at'] as String),
          status: Value(observations.any((s) =>
                  (s['attribute_values'] as Map?)?['does_not_exist'] == true)
              ? 'demolished'
              : observations.isEmpty
                  ? 'unfilled'
                  : 'complete'),
          splitFromId: Value(row['split_from_id'] as String?),
          mergedIntoId: Value(row['merged_into_id'] as String?),
        ));
    return true;
  }

  Map<String, dynamic> _observationRow(
    Map<dynamic, dynamic> observation,
    String assignmentId,
    String featureId,
  ) {
    for (final alias in ['assignment_id', '__assignment_id']) {
      if (observation.containsKey(alias) &&
          observation[alias] != assignmentId) {
        throw StateError('Shared observation belongs to another assignment');
      }
    }
    if (observation.containsKey('feature_id') &&
        observation['feature_id'] != featureId) {
      throw StateError('Shared observation belongs to another feature');
    }
    return {
      ...Map<String, dynamic>.from(observation),
      '__assignment_id': assignmentId,
      'feature_id': featureId,
    };
  }

  Future<void> _projected(String assignmentId, String id) async {
    await (db.update(db.sharedMapFeatures)
          ..where((t) =>
              t.accountId.equals(accountId) &
              t.assignmentId.equals(assignmentId) &
              t.featureId.equals(id)))
        .write(
            const SharedMapFeaturesCompanion(pendingProjection: Value(false)));
  }

  Future<void> reconcile(String assignmentId) async {
    await db.transaction(() async {
      final pending = await (db.select(db.sharedMapFeatures)
            ..where((t) =>
                t.accountId.equals(accountId) &
                t.assignmentId.equals(assignmentId) &
                t.pendingProjection.equals(true)))
          .get();
      for (final row in pending) {
        if (await _projectFeature(assignmentId,
            jsonDecode(row.payloadJson) as Map<String, dynamic>)) {
          await _projected(assignmentId, row.featureId);
        }
      }
    });
  }
}
