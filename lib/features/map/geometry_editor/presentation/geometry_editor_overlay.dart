import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/midpoint_handle.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/reshape_remove_confirm_dialog.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/vertex_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GeometryEditorOverlay extends ConsumerWidget {
  const GeometryEditorOverlay({required this.projection, super.key});
  final MapProjection projection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(geometryEditorControllerProvider);
    if (!state.isActive) return const SizedBox.shrink();
    final notifier = ref.read(geometryEditorControllerProvider.notifier);

    final children = <Widget>[];

    // Live preview of the in-progress geometry. Draws connecting lines
    // between vertices (and the closing edge for closed shapes) using the
    // same projection the vertex handles use. Drawn BEFORE the body-drag
    // area and handles so it appears underneath them.
    children.add(
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _SketchPreviewPainter(
              rings: state.workingRings,
              isClosed: state.isClosed,
              projection: projection,
            ),
          ),
        ),
      ),
    );

    // For closed shapes (polygons), draw an invisible body-drag area covering
    // the outer ring's bounding rect. Pan on this area translates the entire
    // shape (US-11). It's drawn FIRST so vertex/midpoint handles render on
    // top — Flutter hit-tests in reverse z-order, so the smaller handle hit
    // areas win, and only pans on empty interior fall through to the body.
    if (state.isClosed && state.workingRings.isNotEmpty) {
      final outer = state.workingRings[0];
      if (outer.length >= 3) {
        var minX = double.infinity;
        var minY = double.infinity;
        var maxX = double.negativeInfinity;
        var maxY = double.negativeInfinity;
        for (final v in outer) {
          final p = projection.screenPointFromLngLat(v.lng, v.lat);
          if (p.dx < minX) minX = p.dx;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dy > maxY) maxY = p.dy;
        }
        children.add(Positioned(
          left: minX,
          top: minY,
          width: maxX - minX,
          height: maxY - minY,
          child: GestureDetector(
            key: const Key('reshape.body'),
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (d) {
              // Translate the working geometry by the screen-delta converted
              // to lng/lat. Use the centroid as the projection anchor so the
              // delta is locally accurate across both small and large extents.
              final centerLng = (minX + maxX) / 2;
              final centerLat = (minY + maxY) / 2;
              final origin = projection.lngLatFromScreenPoint(
                Offset(centerLng, centerLat),
              );
              final moved = projection.lngLatFromScreenPoint(
                Offset(centerLng + d.delta.dx, centerLat + d.delta.dy),
              );
              notifier.translateAll(
                moved.lng - origin.lng,
                moved.lat - origin.lat,
              );
            },
            child: const SizedBox.expand(),
          ),
        ),);
      }
    }

    for (var ringIdx = 0; ringIdx < state.workingRings.length; ringIdx++) {
      final ring = state.workingRings[ringIdx];
      final wraps = state.isClosed;

      for (var i = 0; i < ring.length; i++) {
        final v = ring[i];
        final p = projection.screenPointFromLngLat(v.lng, v.lat);
        children.add(Positioned(
          left: p.dx - 22,
          top: p.dy - 22,
          child: GestureDetector(
            key: Key('reshape.vertex.$ringIdx.$i'),
            onPanUpdate: (d) {
              final cur = ref
                  .read(geometryEditorControllerProvider)
                  .workingRings[ringIdx];
              if (i >= cur.length) return;
              final cv = cur[i];
              final screen = projection.screenPointFromLngLat(cv.lng, cv.lat);
              final next = screen + d.delta;
              final nextLngLat = projection.lngLatFromScreenPoint(next);
              notifier.moveVertex(ringIdx, i, nextLngLat);
            },
            onLongPress: () async {
              final confirm = await showReshapeRemoveConfirm(
                context,
                currentRingLength: ring.length,
              );
              if (confirm) notifier.removeVertex(ringIdx, i);
            },
            child: const VertexHandle(),
          ),
        ),);
      }

      // For closed shapes the midpoint wraps last→first; for open polylines
      // it only sits between successive vertices.
      final segmentCount = wraps ? ring.length : ring.length - 1;
      for (var i = 0; i < segmentCount; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        final mLng = (a.lng + b.lng) / 2;
        final mLat = (a.lat + b.lat) / 2;
        final p = projection.screenPointFromLngLat(mLng, mLat);
        final insertAt = i + 1;
        children.add(Positioned(
          left: p.dx - 22,
          top: p.dy - 22,
          child: GestureDetector(
            key: Key('reshape.midpoint.$ringIdx.$i'),
            onPanStart: (d) {
              // A2 gesture: insert immediately, then drag with same gesture.
              notifier.addVertex(ringIdx, insertAt, (lng: mLng, lat: mLat));
            },
            onPanUpdate: (d) {
              final cur = ref
                  .read(geometryEditorControllerProvider)
                  .workingRings[ringIdx];
              if (insertAt >= cur.length) return;
              final v = cur[insertAt];
              final screen = projection.screenPointFromLngLat(v.lng, v.lat);
              final next = screen + d.delta;
              final nextLngLat = projection.lngLatFromScreenPoint(next);
              notifier.moveVertex(ringIdx, insertAt, nextLngLat);
            },
            child: const MidpointHandle(),
          ),
        ),);
      }
    }

    return Stack(children: children);
  }
}

/// Paints the live geometry of an in-progress sketch (or active reshape):
/// connecting lines between vertices, plus a translucent fill for closed
/// shapes with at least 3 vertices.
class _SketchPreviewPainter extends CustomPainter {
  _SketchPreviewPainter({
    required this.rings,
    required this.isClosed,
    required this.projection,
  });

  final List<List<LngLat>> rings;
  final bool isClosed;
  final MapProjection projection;

  static const _color = Color(0xFF3182CE);

  @override
  void paint(Canvas canvas, Size size) {
    if (rings.isEmpty) return;
    final stroke = Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = _color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    for (final ring in rings) {
      if (ring.length < 2) continue;
      final path = Path();
      final first = projection.screenPointFromLngLat(ring[0].lng, ring[0].lat);
      path.moveTo(first.dx, first.dy);
      for (var i = 1; i < ring.length; i++) {
        final p = projection.screenPointFromLngLat(ring[i].lng, ring[i].lat);
        path.lineTo(p.dx, p.dy);
      }
      if (isClosed && ring.length >= 3) {
        path.close();
        canvas.drawPath(path, fill);
      }
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPreviewPainter old) {
    if (old.isClosed != isClosed) return true;
    if (old.projection != projection) return true;
    if (old.rings.length != rings.length) return true;
    for (var r = 0; r < rings.length; r++) {
      if (old.rings[r].length != rings[r].length) return true;
      for (var i = 0; i < rings[r].length; i++) {
        if (old.rings[r][i] != rings[r][i]) return true;
      }
    }
    return false;
  }
}
