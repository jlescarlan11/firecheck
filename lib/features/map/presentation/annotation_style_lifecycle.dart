/// Serializes native annotation initialization across style reloads. Geometry
/// callbacks read current widget state when executed, rather than queue-time
/// snapshots. A failed initialization does not poison later reloads.
class AnnotationStyleLifecycle<MapHandle> {
  AnnotationStyleLifecycle({
    required this.isCurrent,
    required this.initialize,
    required this.replayWorkingGeometry,
  });

  final bool Function(MapHandle map) isCurrent;
  final Future<void> Function(MapHandle map) initialize;
  final Future<void> Function() replayWorkingGeometry;
  Future<void> _pending = Future.value();

  Future<void> reload(MapHandle map) {
    final next = _pending.then((_) async {
      if (!isCurrent(map)) return;
      await initialize(map);
      if (!isCurrent(map)) return;
      await replayWorkingGeometry();
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}
