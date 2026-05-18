import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// Abstraction over a Supabase realtime channel so the realtime sync
/// controller can be unit-tested without standing up a real socket. Tests
/// provide a fake subscriber that emits events programmatically.
///
/// Each `subscribe` call returns a [RealtimeSubscription] that:
///   - exposes a `Stream<void> events` — one tick per realtime payload,
///   - exposes a `Future<bool> joined` — resolves once the channel reports
///     `subscribed`, or false on `channelError` / `timedOut`,
///   - has a `close()` that closes the channel and completes any pending
///     joined-future as false.
abstract class RealtimeSubscriber {
  Future<RealtimeSubscription> subscribe();
}

abstract class RealtimeSubscription {
  Stream<void> get events;

  /// Resolves true on channel `subscribed`, false on `channelError` /
  /// `timedOut` / explicit close. Never throws.
  Future<bool> get joined;

  Future<void> close();
}

/// Subscribes to inserts/updates/deletes on `public.submissions` and
/// `public.features` filtered by RLS membership. The client side does
/// **not** apply an `assignment_id` filter at the channel level — the
/// `filter:` mechanism in Supabase realtime only supports a single-column
/// equality, and `submissions` doesn't carry `assignment_id` directly.
/// Instead the spec specifies "client-side filter on assignment_id" — we
/// do that one level up by triggering a delta pull that itself scopes to
/// the active assignment.
class SupabaseRealtimeSubscriber implements RealtimeSubscriber {
  SupabaseRealtimeSubscriber(this._client, {String channelTag = 'multi_user_sync'})
      : _channelTag = channelTag;

  final SupabaseClient _client;
  final String _channelTag;

  @override
  Future<RealtimeSubscription> subscribe() async {
    final eventsCtl = StreamController<void>.broadcast();
    final joined = Completer<bool>();

    void onAnyChange(PostgresChangePayload payload) {
      eventsCtl.add(null);
    }

    final channel = _client.channel(_channelTag);

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'submissions',
          callback: onAnyChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'features',
          callback: onAnyChange,
        )
        .subscribe((status, error) {
      debugPrint('[Realtime] channel status=$status err=$error');
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          if (!joined.isCompleted) joined.complete(true);
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          if (!joined.isCompleted) joined.complete(false);
      }
    });

    return _SupabaseSubscription(
      channel: channel,
      eventsCtl: eventsCtl,
      joined: joined,
    );
  }
}

class _SupabaseSubscription implements RealtimeSubscription {
  _SupabaseSubscription({
    required RealtimeChannel channel,
    required StreamController<void> eventsCtl,
    required Completer<bool> joined,
  })  : _channel = channel,
        _eventsCtl = eventsCtl,
        _joined = joined;

  final RealtimeChannel _channel;
  final StreamController<void> _eventsCtl;
  final Completer<bool> _joined;
  bool _closed = false;

  @override
  Stream<void> get events => _eventsCtl.stream;

  @override
  Future<bool> get joined => _joined.future;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_joined.isCompleted) _joined.complete(false);
    try {
      await _channel.unsubscribe();
    } on Object catch (e) {
      debugPrint('[Realtime] unsubscribe failed: $e');
    }
    await _eventsCtl.close();
  }
}
