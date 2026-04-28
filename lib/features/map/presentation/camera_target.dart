import 'package:flutter/foundation.dart';

/// Animation style for a camera command.
///
/// `fly` — Mapbox `flyTo` (~750 ms); a cinematic zoom-out-and-in arc, used
/// for cross-screen jumps like recenter-to-GPS.
/// `ease` — Mapbox `easeTo` (~250 ms); a smooth direct interpolation, used
/// for ±1 zoom steps from the explicit zoom buttons.
enum CameraAnimation { fly, ease }

/// A camera-fly request from the screen to the renderer.
///
/// Equality is on [requestId] only so two taps producing identical
/// coordinates still trigger a fresh fly: the renderer's didUpdateWidget
/// detects "different requestId" → flyTo. This is intentional — without it,
/// repeat taps at the same position would be no-ops.
///
/// [animation] is renderer metadata, not identity — two targets with the
/// same `requestId` but different `animation` values are still equal.
@immutable
class CameraTarget {
  const CameraTarget({
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.requestId,
    this.animation = CameraAnimation.fly,
  });

  final double lat;
  final double lng;
  final double zoom;
  final int requestId;
  final CameraAnimation animation;

  @override
  bool operator ==(Object other) =>
      other is CameraTarget && other.requestId == requestId;

  @override
  int get hashCode => requestId.hashCode;
}
