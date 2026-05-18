/// State machine for the realtime sync subscription, per the spec's
/// "Connection state machine" section:
///
/// ```text
/// offline → reconnecting → online → backgrounded → offline
/// ```
///
/// Transitions:
///   - `offline → reconnecting`: network restored OR controller started.
///   - `reconnecting → online`: delta pull completed AND channel reported
///     `subscribed`. Subscription is opened **after** the delta pull, so
///     realtime events can't land before the cache has caught up.
///   - `online → backgrounded`: app moved to background. Subscription is
///     kept open for `backgroundUnsubscribeAfter` (default 2 min) to keep
///     the cache live for quick foreground returns.
///   - `backgrounded → offline`: grace window elapsed; subscription closed.
///   - `backgrounded → reconnecting`: app resumed before grace elapsed.
///   - any state `→ offline`: network lost, error, or explicit stop.
enum RealtimeConnectionState {
  offline,
  reconnecting,
  online,
  backgrounded,
}
