import 'dart:async';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/remote_attributions_pull_service.dart';
import 'package:firecheck/core/sync/worker/connectivity_listener.dart';
import 'package:firecheck/core/sync/worker/lifecycle_listener.dart';
import 'package:flutter/foundation.dart';

/// Drives the non-realtime pull paths for the remote attribution cache.
///
///   - On `start()` (cold-open of an assignment): full pull.
///   - On connectivity restore: delta pull (falls back to full if stale).
///   - On app resume: delta pull.
///
/// Runs alongside `RealtimeSyncController`; the two share the same cache
/// so order doesn't matter — the upsert is idempotent.
class RemoteCacheController {
  RemoteCacheController({
    required RemoteAttributionsPullService pullService,
    required AppDatabase db,
  })  : _pullService = pullService,
        _db = db;

  final RemoteAttributionsPullService _pullService;
  final AppDatabase _db;

  ConnectivityListener? _connectivity;
  SyncLifecycleListener? _lifecycle;
  bool _started = false;

  /// Performs the initial cold-open full-pull for whatever assignment is
  /// currently selected, then wires connectivity + lifecycle listeners so
  /// subsequent reconnects/resumes trigger a delta pull.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _pullForCurrentAssignment(full: true);
    _connectivity = ConnectivityListener(onConnect: _onReconnect)..start();
    _lifecycle = SyncLifecycleListener(onResume: _onResume)..start();
  }

  Future<void> stop() async {
    await _connectivity?.dispose();
    _lifecycle?.dispose();
    _started = false;
  }

  /// Forces a full pull regardless of cursor state (e.g. user pulled-to-refresh).
  Future<void> forceRefresh() async {
    await _pullForCurrentAssignment(full: true);
  }

  Future<void> _onReconnect() async {
    await _pullForCurrentAssignment(full: false);
  }

  Future<void> _onResume() async {
    await _pullForCurrentAssignment(full: false);
  }

  Future<void> _pullForCurrentAssignment({required bool full}) async {
    // Deterministic selection — matches AssignmentRepository.getCurrentAssignment()
    // ("newest by createdAt") so badges/cache reference the same assignment
    // the rest of the app considers "current".
    final rows = await (_db.select(_db.assignments)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .get();
    final assignment = rows.firstOrNull;
    if (assignment == null) return;
    try {
      final result = full
          ? await _pullService.pullAll(assignment.id)
          : await _pullService.pullDelta(assignment.id);
      debugPrint(
        '[RemoteCacheController] pull (full=$full) '
        'a=${result.attributionsCount} f=${result.newFeaturesCount}',
      );
    } on Object catch (e) {
      // Pull failures are non-fatal — next reconnect / resume retries.
      debugPrint('[RemoteCacheController] pull failed: $e');
    }
  }
}
