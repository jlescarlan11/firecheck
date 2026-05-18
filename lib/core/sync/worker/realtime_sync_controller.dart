import 'dart:async';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/realtime_subscriber.dart';
import 'package:firecheck/core/sync/data/remote_attributions_pull_service.dart';
import 'package:firecheck/core/sync/domain/realtime_connection_state.dart';
import 'package:flutter/foundation.dart';

/// Phase 3 of multi-user attribution sync.
///
/// Owns the `offline → reconnecting → online → backgrounded → offline`
/// state machine and the realtime subscription that drives it. Realtime
/// events trigger a debounced delta pull through [RemoteAttributionsPullService]
/// so cache writes go through the same upsert path as cold-open and
/// reconnect pulls (the spec's `cacheUpsertFromServerRows` invariant).
///
/// The controller deliberately does **not** parse realtime payloads — the
/// Supabase realtime row for `public.submissions` doesn't include the
/// joined typed-attribute child rows we need for the cache's
/// `attribute_values` field, and `public.features` events deliver
/// PostGIS WKB that's not trivially decodable on the client. Treating
/// every event as "something changed, refetch the delta" trades a few
/// hundred ms of latency for one well-tested code path.
///
/// The controller does **not** itself run the cold-open full pull — that
/// happens via the phase-2 `RemoteCacheController`. Phase 3 layers
/// realtime on top of the existing pull infrastructure.
class RealtimeSyncController {
  RealtimeSyncController({
    required RealtimeSubscriber subscriber,
    required RemoteAttributionsPullService pullService,
    required AppDatabase db,
    Duration backgroundUnsubscribeAfter = const Duration(minutes: 2),
    Duration eventDebounce = const Duration(milliseconds: 250),
  })  : _subscriber = subscriber,
        _pullService = pullService,
        _db = db,
        _backgroundUnsubscribeAfter = backgroundUnsubscribeAfter,
        _eventDebounce = eventDebounce;

  final RealtimeSubscriber _subscriber;
  final RemoteAttributionsPullService _pullService;
  final AppDatabase _db;
  final Duration _backgroundUnsubscribeAfter;
  final Duration _eventDebounce;

  final StreamController<RealtimeConnectionState> _stateCtl =
      StreamController.broadcast();

  RealtimeConnectionState _state = RealtimeConnectionState.offline;
  RealtimeSubscription? _subscription;
  StreamSubscription<void>? _eventsSub;
  Timer? _debounceTimer;
  Timer? _backgroundGraceTimer;
  bool _disposed = false;
  // Used to ignore late-arriving subscription completions from a previous
  // connect attempt that's already been superseded.
  int _connectGeneration = 0;

  /// Current state. Initial value is [RealtimeConnectionState.offline].
  RealtimeConnectionState get state => _state;

  /// Broadcasts transitions in order. Replays nothing on subscribe — use
  /// [state] for the current value.
  Stream<RealtimeConnectionState> get states => _stateCtl.stream;

  /// Triggered each time a realtime event was just consumed (after debounce).
  /// Tests use this; production code reads the cache directly.
  final StreamController<void> _onPullCtl = StreamController.broadcast();
  Stream<void> get onDeltaPulled => _onPullCtl.stream;

  /// Begin: starts in offline, attempts an immediate connect.
  Future<void> start() async {
    if (_disposed) return;
    await _connect();
  }

  /// Tear down — closes subscription, cancels timers, transitions to offline.
  Future<void> stop() async {
    if (_disposed) return;
    _disposed = true;
    _connectGeneration++;
    _debounceTimer?.cancel();
    _backgroundGraceTimer?.cancel();
    await _eventsSub?.cancel();
    await _subscription?.close();
    _subscription = null;
    _transitionTo(RealtimeConnectionState.offline);
    await _stateCtl.close();
    await _onPullCtl.close();
  }

  /// Called by the connectivity listener when the network is restored.
  Future<void> onNetworkRestored() async {
    if (_disposed) return;
    if (_state == RealtimeConnectionState.online ||
        _state == RealtimeConnectionState.reconnecting) {
      return;
    }
    await _connect();
  }

  /// Called by the connectivity listener when the network is lost.
  Future<void> onNetworkLost() async {
    if (_disposed) return;
    await _teardownSubscription();
    _transitionTo(RealtimeConnectionState.offline);
  }

  /// Called by the lifecycle listener when the app moves to background.
  void onAppBackgrounded() {
    if (_disposed) return;
    if (_state != RealtimeConnectionState.online) return;
    _transitionTo(RealtimeConnectionState.backgrounded);
    _backgroundGraceTimer?.cancel();
    _backgroundGraceTimer = Timer(_backgroundUnsubscribeAfter, () async {
      if (_disposed) return;
      if (_state != RealtimeConnectionState.backgrounded) return;
      // Grace window elapsed — drop the subscription. Next foreground
      // (or network-restore) reconnects.
      await _teardownSubscription();
      _transitionTo(RealtimeConnectionState.offline);
    });
  }

  /// Called by the lifecycle listener when the app returns to foreground.
  Future<void> onAppResumed() async {
    if (_disposed) return;
    _backgroundGraceTimer?.cancel();
    _backgroundGraceTimer = null;

    if (_state == RealtimeConnectionState.backgrounded &&
        _subscription != null) {
      // Subscription still alive — fire a catch-up delta pull and go online.
      // We don't have to renegotiate the socket; the channel ride-alongs.
      await _runDeltaPull();
      _transitionTo(RealtimeConnectionState.online);
      return;
    }

    // Subscription has been torn down (grace expired) or never existed.
    await _connect();
  }

  // ----- internals -------------------------------------------------------

  Future<void> _connect() async {
    if (_disposed) return;
    final assignmentId = await _currentAssignmentId();
    if (assignmentId == null) {
      _transitionTo(RealtimeConnectionState.offline);
      return;
    }

    _connectGeneration++;
    final myGen = _connectGeneration;

    _transitionTo(RealtimeConnectionState.reconnecting);

    // Per spec: subscription opens AFTER delta pull completes — otherwise
    // realtime events could land before the cache catches up.
    try {
      await _pullService.pullDelta(assignmentId);
    } on Object catch (e) {
      debugPrint('[Realtime] pre-subscribe delta pull failed: $e');
      // Keep going — events on the live channel will trigger their own pulls.
    }

    if (_disposed || myGen != _connectGeneration) return;

    await _teardownSubscription();
    final sub = await _subscriber.subscribe();
    _subscription = sub;

    _eventsSub = sub.events.listen((_) => _scheduleDeltaPull());

    final joined = await sub.joined;
    if (_disposed || myGen != _connectGeneration) {
      await sub.close();
      return;
    }

    if (joined) {
      _transitionTo(RealtimeConnectionState.online);
    } else {
      await _teardownSubscription();
      _transitionTo(RealtimeConnectionState.offline);
    }
  }

  Future<void> _teardownSubscription() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _subscription?.close();
    _subscription = null;
  }

  void _scheduleDeltaPull() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_eventDebounce, _runDeltaPull);
  }

  Future<void> _runDeltaPull() async {
    if (_disposed) return;
    final assignmentId = await _currentAssignmentId();
    if (assignmentId == null) return;
    try {
      await _pullService.pullDelta(assignmentId);
      if (!_onPullCtl.isClosed) _onPullCtl.add(null);
    } on Object catch (e) {
      debugPrint('[Realtime] delta pull failed: $e');
    }
  }

  Future<String?> _currentAssignmentId() async {
    final row =
        await (_db.select(_db.assignments)..limit(1)).getSingleOrNull();
    return row?.id;
  }

  void _transitionTo(RealtimeConnectionState next) {
    if (_state == next) return;
    debugPrint('[Realtime] ${_state.name} → ${next.name}');
    _state = next;
    if (!_stateCtl.isClosed) _stateCtl.add(next);
  }
}
