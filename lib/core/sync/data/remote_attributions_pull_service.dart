import 'package:firecheck/core/sync/data/shared_map_sync.dart';
import 'package:firecheck/core/sync/data/remote_attributions_cache_repository.dart';
import 'package:firecheck/core/sync/data/remote_cache_api.dart';
import 'package:flutter/foundation.dart';

/// Drives the two non-realtime pull paths for the remote attribution cache:
///
///   pullAll(assignmentId)    — cold-open / first-time-on-assignment full pull.
///                              Cursor is null so the server returns everything;
///                              cursor is then set to max(updated_at) of the
///                              response.
///   pullDelta(assignmentId)  — on-reconnect delta pull using the stored cursor.
///                              Includes already-superseded rows so badges
///                              disappear correctly.
///
/// Both paths feed the same upsert in `RemoteAttributionsCacheRepository`, so
/// merge semantics are identical (and identical to the realtime path).
///
/// Stale-cache rule: if the cursor is older than `staleAge` (default 24h) we
/// force a full pull rather than a delta, matching the spec's "Cache
/// divergence after crash" handling.
class RemoteAttributionsPullService {
  RemoteAttributionsPullService({
    this.sharedSync,
    required RemoteCacheApi api,
    required RemoteAttributionsCacheRepository cache,
    Duration staleAge = const Duration(hours: 24),
    DateTime Function()? now,
  })  : _api = api,
        _cache = cache,
        _staleAge = staleAge,
        _now = now ?? DateTime.now;

  final SharedMapSync? sharedSync;
  final RemoteCacheApi _api;
  final RemoteAttributionsCacheRepository _cache;
  final Duration _staleAge;
  final DateTime Function() _now;

  /// Full pull for [assignmentId]. Cursor reset to max(updated_at) of the
  /// returned rows. Safe to call repeatedly — upserts are idempotent.
  Future<PullResult> pullAll(String assignmentId) async {
    return _pull(assignmentId, kind: PullKind.full);
  }

  /// Delta pull using the stored cursor. Falls back to a full pull if the
  /// cursor is missing or older than `staleAge`.
  Future<PullResult> pullDelta(String assignmentId) async {
    final cursor = await _cache.getCursor(assignmentId);
    final attribSince = cursor?.attributionsLastSyncAt;
    final newFeatSince = cursor?.newFeaturesLastSyncAt;

    final stale = (attribSince == null && newFeatSince == null) ||
        _isStale(attribSince) ||
        _isStale(newFeatSince);

    if (stale) return pullAll(assignmentId);

    return _pull(
      assignmentId,
      sinceAttributions: attribSince,
      sinceNewFeatures: newFeatSince,
      kind: PullKind.delta,
    );
  }

  bool _isStale(DateTime? cursor) {
    if (cursor == null) return false;
    return _now().difference(cursor) > _staleAge;
  }

  Future<PullResult> _pull(
    String assignmentId, {
    required PullKind kind,
    DateTime? sinceAttributions,
    DateTime? sinceNewFeatures,
  }) async {
    if (await sharedSync?.pull(assignmentId) == true) {
      return PullResult(
          kind: kind,
          attributionsCount: 0,
          newFeaturesCount: 0,
          attributionsCursor: null,
          newFeaturesCursor: null);
    }
    // Awaiting via Future.wait — not sequential awaits — so a thrown error
    // in the first call still leaves the second future awaited. Sequential
    // `await`s would orphan the second future and surface as an uncaught
    // async exception outside our try/catch on transient network failures.
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _api.fetchAttributions(assignmentId, since: sinceAttributions),
      _api.fetchNewFeatures(assignmentId, since: sinceNewFeatures),
    ]);
    final attributions = results[0];
    final newFeatures = results[1];

    final attribCursor = _maxUpdatedAt(attributions) ?? sinceAttributions;
    final newFeatCursor = _maxUpdatedAt(newFeatures) ?? sinceNewFeatures;

    await _cache.applyPull(
      assignmentId,
      attributions: attributions,
      newFeatures: newFeatures,
      attributionsCursor: attribCursor,
      newFeaturesCursor: newFeatCursor,
    );

    debugPrint(
      '[RemotePull] $kind assignment=$assignmentId '
      'attributions=${attributions.length} newFeatures=${newFeatures.length}',
    );

    return PullResult(
      kind: kind,
      attributionsCount: attributions.length,
      newFeaturesCount: newFeatures.length,
      attributionsCursor: attribCursor,
      newFeaturesCursor: newFeatCursor,
    );
  }

  DateTime? _maxUpdatedAt(List<Map<String, dynamic>> rows) {
    DateTime? max;
    for (final row in rows) {
      final raw = row['updated_at'];
      if (raw == null) continue;
      final dt = raw is DateTime ? raw : DateTime.parse(raw as String).toUtc();
      if (max == null || dt.isAfter(max)) max = dt;
    }
    return max;
  }
}

/// Distinguishes a full cold-open pull from an incremental delta pull.
/// Exposed on [PullResult] for diagnostics + tests.
enum PullKind { full, delta }

class PullResult {
  PullResult({
    required this.kind,
    required this.attributionsCount,
    required this.newFeaturesCount,
    required this.attributionsCursor,
    required this.newFeaturesCursor,
  });

  final PullKind kind;
  final int attributionsCount;
  final int newFeaturesCount;
  final DateTime? attributionsCursor;
  final DateTime? newFeaturesCursor;

  bool get isFullPull => kind == PullKind.full;
  bool get isDelta => kind == PullKind.delta;
}
