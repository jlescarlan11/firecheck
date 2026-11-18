import 'package:firecheck/core/geo/comparison_geometry.dart';
import 'package:flutter/material.dart';

/// Serializes replacement on one style's outline manager. A new binding owns
/// its own queue so an old native-style operation cannot draw into the new one.
class BoundaryOutline {
  BoundaryOutline({required this.clear, required this.draw});
  final Future<void> Function() clear;
  final Future<void> Function(List<Offset> ring) draw;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  int _revision = 0;

  Future<void> replace(String source) {
    final revision = ++_revision;
    final next = _pending.then((_) async {
      if (_disposed || revision != _revision) return;
      await clear();
      if (_disposed || revision != _revision) return;
      final geometry = ComparisonGeometry.parse(source);
      if (geometry == null ||
          !{'Polygon', 'MultiPolygon'}.contains(geometry.type)) {
        return;
      }
      for (final ring in geometry.paths) {
        if (_disposed || revision != _revision) return;
        await draw(ring);
      }
    });
    _pending = next.catchError((Object _) {});
    return next;
  }

  void dispose() => _disposed = true;
}
