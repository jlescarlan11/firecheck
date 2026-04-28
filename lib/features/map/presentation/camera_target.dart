import 'package:flutter/foundation.dart';

/// A camera-fly request from the screen to the renderer.
///
/// Equality is on [requestId] only so two taps producing identical
/// coordinates still trigger a fresh fly: the renderer's didUpdateWidget
/// detects "different requestId" → flyTo. This is intentional — without it,
/// repeat taps at the same position would be no-ops.
@immutable
class CameraTarget {
  const CameraTarget({
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.requestId,
  });

  final double lat;
  final double lng;
  final double zoom;
  final int requestId;

  @override
  bool operator ==(Object other) =>
      other is CameraTarget && other.requestId == requestId;

  @override
  int get hashCode => requestId.hashCode;
}
