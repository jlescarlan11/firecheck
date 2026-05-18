import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/realtime_subscriber.dart';
import 'package:firecheck/core/sync/data/remote_attributions_cache_repository.dart';
import 'package:firecheck/core/sync/data/remote_attributions_pull_service.dart';
import 'package:firecheck/core/sync/data/remote_cache_api.dart';
import 'package:firecheck/core/sync/domain/realtime_connection_state.dart';
import 'package:firecheck/core/sync/worker/realtime_sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake subscriber the test drives manually: trigger join success/failure,
/// emit events on demand, observe close calls.
class _FakeSubscriber implements RealtimeSubscriber {
  _FakeSubscriber({this.autoJoin = true});

  /// If true, the next subscribe completes the `joined` future with `true`
  /// on the same microtask. Tests that want to assert the reconnecting →
  /// online transition use this. Set to false to test reconnecting-then-
  /// error paths.
  bool autoJoin;

  final List<_FakeSubscription> subs = [];

  int subscribeCalls = 0;

  @override
  Future<RealtimeSubscription> subscribe() async {
    subscribeCalls++;
    final s = _FakeSubscription();
    subs.add(s);
    if (autoJoin) {
      // Complete on a microtask so awaiters of `joined` get scheduled.
      Future.microtask(() => s.completeJoin(true));
    }
    return s;
  }
}

class _FakeSubscription implements RealtimeSubscription {
  final StreamController<void> _eventsCtl = StreamController.broadcast();
  final Completer<bool> _joined = Completer<bool>();
  bool closed = false;

  void emit() => _eventsCtl.add(null);

  void completeJoin(bool ok) {
    if (!_joined.isCompleted) _joined.complete(ok);
  }

  @override
  Stream<void> get events => _eventsCtl.stream;

  @override
  Future<bool> get joined => _joined.future;

  @override
  Future<void> close() async {
    closed = true;
    if (!_joined.isCompleted) _joined.complete(false);
    await _eventsCtl.close();
  }
}

class _RecordingApi implements RemoteCacheApi {
  int attribCalls = 0;
  int newFeatCalls = 0;
  DateTime? lastAttribSince;

  @override
  Future<List<Map<String, dynamic>>> fetchAttributions(
    String assignmentId, {
    DateTime? since,
  }) async {
    attribCalls++;
    lastAttribSince = since;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNewFeatures(
    String assignmentId, {
    DateTime? since,
  }) async {
    newFeatCalls++;
    return const [];
  }
}

Future<void> _pump([int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late AppDatabase db;
  late RemoteAttributionsCacheRepository cache;
  late _RecordingApi api;
  late RemoteAttributionsPullService pull;
  late _FakeSubscriber subscriber;
  late RealtimeSyncController controller;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = RemoteAttributionsCacheRepository(db);
    api = _RecordingApi();
    pull = RemoteAttributionsPullService(api: api, cache: cache);
    subscriber = _FakeSubscriber();
    controller = RealtimeSyncController(
      subscriber: subscriber,
      pullService: pull,
      db: db,
      eventDebounce: const Duration(milliseconds: 10),
      backgroundUnsubscribeAfter: const Duration(milliseconds: 30),
    );

    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'me',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime(2026, 5, 18),
          ),
        );
  });

  tearDown(() async {
    await controller.stop();
    await db.close();
  });

  test('start: offline → reconnecting → online when join succeeds',
      () async {
    final transitions = <RealtimeConnectionState>[];
    controller.states.listen(transitions.add);

    expect(controller.state, RealtimeConnectionState.offline);
    await controller.start();
    await _pump();

    expect(controller.state, RealtimeConnectionState.online);
    expect(
      transitions,
      [
        RealtimeConnectionState.reconnecting,
        RealtimeConnectionState.online,
      ],
    );

    expect(api.attribCalls, 1,
        reason: 'pre-subscribe delta pull runs before opening the channel');
    expect(subscriber.subscribeCalls, 1);
  });

  test('start returns to offline when channel fails to join', () async {
    subscriber.autoJoin = false;
    final transitions = <RealtimeConnectionState>[];
    controller.states.listen(transitions.add);

    final fut = controller.start();
    await _pump();
    // Now force the join future to resolve as false.
    subscriber.subs.single.completeJoin(false);
    await fut;
    await _pump();

    expect(controller.state, RealtimeConnectionState.offline);
    expect(
      transitions,
      [
        RealtimeConnectionState.reconnecting,
        RealtimeConnectionState.offline,
      ],
    );
  });

  test('events fire debounced delta pulls', () async {
    await controller.start();
    await _pump();
    expect(api.attribCalls, 1);

    // Burst of events arrives within the debounce window — only one
    // additional pull should fire.
    subscriber.subs.single.emit();
    subscriber.subs.single.emit();
    subscriber.subs.single.emit();

    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(api.attribCalls, 2,
        reason: 'three events within debounce coalesce into one pull');
  });

  test('onNetworkLost drops subscription and goes offline', () async {
    await controller.start();
    await _pump();

    final firstSub = subscriber.subs.single;
    await controller.onNetworkLost();

    expect(controller.state, RealtimeConnectionState.offline);
    expect(firstSub.closed, isTrue);
  });

  test('onNetworkRestored from offline triggers reconnect', () async {
    await controller.start();
    await _pump();
    await controller.onNetworkLost();
    await _pump();
    expect(controller.state, RealtimeConnectionState.offline);

    await controller.onNetworkRestored();
    await _pump();

    expect(controller.state, RealtimeConnectionState.online);
    expect(subscriber.subscribeCalls, 2);
  });

  test('onNetworkRestored is a no-op when already online', () async {
    await controller.start();
    await _pump();
    expect(controller.state, RealtimeConnectionState.online);

    await controller.onNetworkRestored();
    await _pump();

    expect(subscriber.subscribeCalls, 1,
        reason: 'no fresh subscribe when already online');
  });

  test('backgrounded → resumed before grace expires keeps subscription',
      () async {
    await controller.start();
    await _pump();
    final sub = subscriber.subs.single;

    controller.onAppBackgrounded();
    expect(controller.state, RealtimeConnectionState.backgrounded);

    // Resume well within the 30ms grace window.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await controller.onAppResumed();
    await _pump();

    expect(controller.state, RealtimeConnectionState.online);
    expect(sub.closed, isFalse,
        reason: 'subscription survives a short background interval');
    expect(subscriber.subscribeCalls, 1);
    expect(api.attribCalls, greaterThanOrEqualTo(2),
        reason: 'resume should fire a catch-up delta pull');
  });

  test('backgrounded → grace expires → offline (subscription dropped)',
      () async {
    await controller.start();
    await _pump();
    final sub = subscriber.subs.single;

    controller.onAppBackgrounded();
    expect(controller.state, RealtimeConnectionState.backgrounded);

    // Wait past the 30ms grace.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state, RealtimeConnectionState.offline);
    expect(sub.closed, isTrue);
  });

  test('resume after grace-expired offline reconnects from scratch',
      () async {
    await controller.start();
    await _pump();

    controller.onAppBackgrounded();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.state, RealtimeConnectionState.offline);

    await controller.onAppResumed();
    await _pump();

    expect(controller.state, RealtimeConnectionState.online);
    expect(subscriber.subscribeCalls, 2);
  });

  test('stop tears down cleanly', () async {
    await controller.start();
    await _pump();
    final sub = subscriber.subs.single;

    await controller.stop();

    expect(controller.state, RealtimeConnectionState.offline);
    expect(sub.closed, isTrue);
  });

  test('start with no assignment stays offline (no subscribe)', () async {
    await db.delete(db.assignments).go();
    await controller.start();
    await _pump();

    expect(controller.state, RealtimeConnectionState.offline);
    expect(subscriber.subscribeCalls, 0);
  });
}
