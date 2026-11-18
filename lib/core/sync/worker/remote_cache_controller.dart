import 'dart:async';

import 'package:firecheck/features/assignment/data/assignment_repository.dart';
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
    this.userId,
  })  : _pullService = pullService,
        _db = db;

  final RemoteAttributionsPullService _pullService;
  final AppDatabase _db;
  final String? userId;

  ConnectivityListener? _connectivity;
  SyncLifecycleListener? _lifecycle;
  bool _started = false;
  Timer? _timer;

  /// Performs the initial cold-open full-pull for whatever assignment is
  /// currently selected, then wires connectivity + lifecycle listeners so
  /// subsequent reconnects/resumes trigger a delta pull.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _pullForCurrentAssignment(full: true);
    if (!_started) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _onReconnect());
    _connectivity = ConnectivityListener(onConnect: _onReconnect)..start();
    _lifecycle = SyncLifecycleListener(onResume: _onResume)..start();
  }

  Future<void> stop() async {
    _timer?.cancel();
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
    final assignment = await AssignmentRepository(db: _db, userId: userId)
        .getCurrentAssignment();
    if (assignment == null) return;
    try {
      final result = full
          ? await _pullService.pullAll(assignment.id)
          : await _pullService.pullDelta(assignment.id);
      _lastErrorMessage = null;
      debugPrint(
        '[RemoteCacheController] pull (full=$full) '
        'a=${result.attributionsCount} f=${result.newFeaturesCount}',
      );
    } on Object catch (e) {
      // Pull failures are non-fatal — next reconnect / resume retries.
      // Dedupe identical messages so a persistent postgrest schema-cache
      // miss (PGRST202) doesn't spam the log on every reconnect.
      final msg = e.toString();
      if (msg != _lastErrorMessage) {
        _lastErrorMessage = msg;
        debugPrint('[RemoteCacheController] pull failed: $e');
      }
    }
  }

  String? _lastErrorMessage;
}
