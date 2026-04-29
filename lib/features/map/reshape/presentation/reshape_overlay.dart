import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/reshape/presentation/midpoint_handle.dart';
import 'package:firecheck/features/map/reshape/presentation/reshape_providers.dart';
import 'package:firecheck/features/map/reshape/presentation/reshape_remove_confirm_dialog.dart';
import 'package:firecheck/features/map/reshape/presentation/vertex_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReshapeOverlay extends ConsumerWidget {
  const ReshapeOverlay({required this.projection, super.key});
  final MapProjection projection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reshapeModeControllerProvider);
    if (!state.isActive) return const SizedBox.shrink();
    final notifier = ref.read(reshapeModeControllerProvider.notifier);
    final ring = state.workingRings[0];

    final children = <Widget>[];

    for (var i = 0; i < ring.length; i++) {
      final v = ring[i];
      final p = projection.screenPointFromLngLat(v.lng, v.lat);
      children.add(Positioned(
        left: p.dx - 22,
        top: p.dy - 22,
        child: GestureDetector(
          key: Key('reshape.vertex.$i'),
          onPanUpdate: (d) {
            // Read live vertex position from state, not the build-time `p`.
            // onPanUpdate fires multiple times per gesture; `d.delta` is the
            // per-event delta, so adding it to a stale anchor under-tracks
            // the finger.
            final cur = ref.read(reshapeModeControllerProvider).workingRings[0];
            if (i >= cur.length) return;
            final cv = cur[i];
            final screen = projection.screenPointFromLngLat(cv.lng, cv.lat);
            final next = screen + d.delta;
            final nextLngLat = projection.lngLatFromScreenPoint(next);
            notifier.moveVertex(0, i, nextLngLat);
          },
          onLongPress: () async {
            final confirm = await showReshapeRemoveConfirm(
              context,
              currentRingLength: ring.length,
            );
            if (confirm) notifier.removeVertex(0, i);
          },
          child: const VertexHandle(),
        ),
      ),);
    }

    for (var i = 0; i < ring.length; i++) {
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
          key: Key('reshape.midpoint.$i'),
          onPanStart: (d) {
            // A2 gesture: insert immediately, then drag with same gesture.
            notifier.addVertex(0, insertAt, (lng: mLng, lat: mLat));
          },
          onPanUpdate: (d) {
            final cur = ref.read(reshapeModeControllerProvider).workingRings[0];
            if (insertAt >= cur.length) return;
            final v = cur[insertAt];
            final screen = projection.screenPointFromLngLat(v.lng, v.lat);
            final next = screen + d.delta;
            final nextLngLat = projection.lngLatFromScreenPoint(next);
            notifier.moveVertex(0, insertAt, nextLngLat);
          },
          child: const MidpointHandle(),
        ),
      ),);
    }

    return Stack(children: children);
  }
}
