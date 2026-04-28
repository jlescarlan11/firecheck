import 'dart:async';
import 'dart:convert';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/presentation/camera_target.dart';
import 'package:flutter/material.dart';
// Hide Feature because the Drift-generated row class (imported above) shares
// the same name with `mapbox_maps_flutter`'s GeoJSON Feature wrapper.
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Feature;

/// Minimal surface the map screen actually needs. Lets tests substitute a
/// renderer that doesn't require a GL context.
// ignore: one_member_abstracts
abstract class MapRenderer {
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    void Function(double zoom, double lat, double lng)? onCameraChanged,
    bool addModeActive,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  });
}

/// Fake for widget tests — renders one tappable tile per feature instead of
/// a real map. Matches the real renderer's tap contract.
class FakeMapRenderer implements MapRenderer {
  void Function(double, double)? _lastOnLongPress;
  void Function(double, double, double)? _lastOnCameraChanged;
  CameraTarget? lastCameraTarget;
  CameraTarget? lastInitialCameraTarget;
  final List<CameraTarget> cameraTargetHistory = [];

  /// Test seam: simulates a long-press at the given coordinates. Invokes the
  /// most recently stored onLongPress callback; no-op if none was provided.
  Future<void> simulateLongPress(double lat, double lng) async {
    final cb = _lastOnLongPress;
    if (cb != null) cb(lat, lng);
  }

  /// Test seam: simulates a camera-change event from the underlying map.
  /// Invokes the most recently stored onCameraChanged callback; no-op if
  /// none was provided.
  Future<void> simulateCameraChanged(double zoom, double lat, double lng) async {
    final cb = _lastOnCameraChanged;
    if (cb != null) cb(zoom, lat, lng);
  }

  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    void Function(double zoom, double lat, double lng)? onCameraChanged,
    bool addModeActive = false,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  }) {
    _lastOnLongPress = onLongPress;
    _lastOnCameraChanged = onCameraChanged;
    lastInitialCameraTarget = initialCameraTarget;
    if (cameraTarget != null && cameraTarget != lastCameraTarget) {
      cameraTargetHistory.add(cameraTarget);
    }
    lastCameraTarget = cameraTarget;
    return ListView(
      shrinkWrap: true,
      children: [
        if (addModeActive)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('add-mode'),
          ),
        ...features.map((f) {
          return GestureDetector(
            key: Key('fake-map-feature-${f.id}'),
            onTap: () => onFeatureTap(f),
            child: Container(
              key: f.isNew
                  ? Key('fake-map-new-feature-${f.id}')
                  : Key('fake-map-poly-${f.id}'),
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.all(8),
              color: _colorForStatus(f.status),
              child: Text('feature ${f.id}'),
            ),
          );
        }),
      ],
    );
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case 'complete':
        return const Color(0x66276749);
      case 'in_progress':
        return const Color(0x66B7791F);
      default:
        return const Color(0x66C53030);
    }
  }
}

// MapboxMapRenderer is exercised via FakeMapRenderer in widget tests and via
// the manual happy path in plan Task 18. The Mapbox plugin does not render
// in flutter_tester.

/// Real renderer backed by `mapbox_maps_flutter` 2.22. Renders an actual map
/// with polygon annotation managers for features + boundary, a point
/// annotation manager for is_new=true features (blue pins), and a location
/// component pinned to GPS via [LocationSettings].
class MapboxMapRenderer implements MapRenderer {
  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    void Function(double zoom, double lat, double lng)? onCameraChanged,
    bool addModeActive = false,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  }) {
    return _MapboxMapView(
      features: features,
      boundaryGeojson: boundaryGeojson,
      onFeatureTap: onFeatureTap,
      onLongPress: onLongPress,
      onCameraChanged: onCameraChanged,
      addModeActive: addModeActive,
      cameraTarget: cameraTarget,
      initialCameraTarget: initialCameraTarget,
    );
  }
}

class _MapboxMapView extends StatefulWidget {
  const _MapboxMapView({
    required this.features,
    required this.boundaryGeojson,
    required this.onFeatureTap,
    this.onLongPress,
    this.onCameraChanged,
    this.addModeActive = false,
    this.cameraTarget,
    this.initialCameraTarget,
  });

  final List<Feature> features;
  final String boundaryGeojson;
  final void Function(Feature) onFeatureTap;
  final void Function(double lat, double lng)? onLongPress;
  final void Function(double zoom, double lat, double lng)? onCameraChanged;
  final bool addModeActive;
  final CameraTarget? cameraTarget;
  final CameraTarget? initialCameraTarget;

  @override
  State<_MapboxMapView> createState() => _MapboxMapViewState();
}

class _MapboxMapViewState extends State<_MapboxMapView> {
  PolygonAnnotationManager? _featureManager;
  PolygonAnnotationManager? _boundaryManager;
  PointAnnotationManager? _pointManager;
  MapboxMap? _mapboxMap;

  // Map annotation-id to feature. Populated as each polygon is created so
  // the tap listener can resolve the Drift row from the tapped annotation.
  final Map<String, Feature> _annotationToFeature = <String, Feature>{};

  @override
  Widget build(BuildContext context) {
    final initial = widget.initialCameraTarget;
    return MapWidget(
      cameraOptions: CameraOptions(
        center: initial != null
            ? Point(coordinates: Position(initial.lng, initial.lat))
            : Point(coordinates: Position(123.88270, 10.31810)),
        zoom: initial?.zoom ?? 15,
      ),
      // Without an explicit styleUri the map renders a black background
      // because no style is loaded. Streets v12 is the Phase 1 spec choice.
      styleUri: 'mapbox://styles/mapbox/streets-v12',
      onMapCreated: _onMapCreated,
      onLongTapListener: (MapContentGestureContext ctx) {
        if (widget.addModeActive && widget.onLongPress != null) {
          final pos = ctx.point.coordinates;
          widget.onLongPress!(pos.lat.toDouble(), pos.lng.toDouble());
        }
      },
      onCameraChangeListener: (CameraChangedEventData data) {
        final cb = widget.onCameraChanged;
        if (cb == null) return;
        final state = data.cameraState;
        cb(
          state.zoom,
          state.center.coordinates.lat.toDouble(),
          state.center.coordinates.lng.toDouble(),
        );
      },
    );
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _mapboxMap = map;
    // Enable the built-in GPS pin. Non-fatal — permission might not be
    // granted yet; in that case the puck simply doesn't appear.
    try {
      await map.location.updateSettings(
        LocationComponentSettings(enabled: true, pulsingEnabled: true),
      );
    } on Object {
      // Swallow — location is a nice-to-have here.
    }

    // Boundary manager FIRST so it sits BENEATH features in the layer stack.
    // Mapbox stacks annotation managers by creation order: later managers
    // render on top. Features must be on top so polygon taps hit them
    // (Bug 13 — caught manually). The boundary's polygon is fully
    // transparent, but Mapbox still hit-tests it; if it sat on top, every
    // tap inside the assignment area would land on the (listener-less)
    // boundary polygon and never reach the feature manager.
    _boundaryManager = await map.annotations.createPolygonAnnotationManager();
    _featureManager = await map.annotations.createPolygonAnnotationManager();
    // Point manager for is_new=true features (blue pins) — topmost.
    _pointManager = await map.annotations.createPointAnnotationManager();

    await _renderBoundary();
    await _renderFeatures();
    await _renderNewFeatures();

    // ignore: deprecated_member_use
    _featureManager!.addOnPolygonAnnotationClickListener(
      _FeatureClickHandler(
        annotationToFeature: _annotationToFeature,
        onTap: widget.onFeatureTap,
      ),
    );

    // Replay any cameraTarget that arrived BEFORE the map was ready. On
    // cold start the user can tap recenter while Mapbox is still booting:
    // _flyToCameraTarget would early-return on the null _mapboxMap, and
    // didUpdateWidget wouldn't fire again because the target is unchanged.
    // Without this replay, the first tap appears to do nothing.
    final pending = widget.cameraTarget;
    if (pending != null) {
      unawaited(_flyToCameraTarget(pending));
    }

    // Guarantee the screen has at least one zoom/center sample by the time
    // the user can interact. Without this, zoom-button taps in the first
    // few frames bail out (no _displayZoom yet) — see US-13 spec §5.
    final initialState = await map.getCameraState();
    widget.onCameraChanged?.call(
      initialState.zoom,
      initialState.center.coordinates.lat.toDouble(),
      initialState.center.coordinates.lng.toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant _MapboxMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the features list arrives AFTER _onMapCreated fires (provider
    // stream still loading on first map open), re-render polygons so the
    // annotation→feature map gets populated and taps register. Same logic
    // for boundary changes.
    final featuresChanged = oldWidget.features != widget.features;
    final boundaryChanged = oldWidget.boundaryGeojson != widget.boundaryGeojson;
    if (featuresChanged && _featureManager != null) {
      unawaited(_rerenderFeatures());
    }
    if (boundaryChanged && _boundaryManager != null) {
      unawaited(_rerenderBoundary());
    }
    final target = widget.cameraTarget;
    if (target != null && target != oldWidget.cameraTarget) {
      unawaited(_flyToCameraTarget(target));
    }
  }

  Future<void> _flyToCameraTarget(CameraTarget t) async {
    final map = _mapboxMap;
    if (map == null) return; // _onMapCreated hasn't run yet
    final opts = CameraOptions(
      center: Point(coordinates: Position(t.lng, t.lat)),
      zoom: t.zoom,
    );
    if (t.animation == CameraAnimation.ease) {
      await map.easeTo(opts, MapAnimationOptions(duration: 250));
    } else {
      await map.flyTo(opts, MapAnimationOptions(duration: 750));
    }
  }

  Future<void> _rerenderFeatures() async {
    final manager = _featureManager;
    if (manager == null) return;
    await manager.deleteAll();
    _annotationToFeature.clear();
    await _renderFeatures();
    final pointManager = _pointManager;
    if (pointManager != null) {
      await pointManager.deleteAll();
      await _renderNewFeatures();
    }
    // Re-attach the click listener AFTER annotations exist. Belt-and-
    // braces against the mapbox_maps_flutter 2.22 quirk where a listener
    // attached to an empty manager doesn't pick up annotations added
    // later. Bug 13.
    // ignore: deprecated_member_use
    manager.addOnPolygonAnnotationClickListener(
      _FeatureClickHandler(
        annotationToFeature: _annotationToFeature,
        onTap: widget.onFeatureTap,
      ),
    );
  }

  Future<void> _rerenderBoundary() async {
    final manager = _boundaryManager;
    if (manager == null) return;
    await manager.deleteAll();
    await _renderBoundary();
  }

  Future<void> _renderFeatures() async {
    final manager = _featureManager;
    if (manager == null) return;
    for (final f in widget.features) {
      // is_new features are rendered as point pins — skip them here so they
      // don't appear as polygons as well.
      if (f.isNew) continue;
      final polygon = _decodePolygon(f.geometryGeojson);
      if (polygon == null) continue;
      final created = await manager.create(
        PolygonAnnotationOptions(
          geometry: polygon,
          fillColor: _colorForStatus(f.status),
          fillOpacity: 0.4,
        ),
      );
      _annotationToFeature[created.id] = f;
    }
  }

  Future<void> _renderBoundary() async {
    final manager = _boundaryManager;
    if (manager == null) return;
    if (widget.boundaryGeojson.isEmpty) return;
    final polygon = _decodePolygon(widget.boundaryGeojson);
    if (polygon == null) return;
    await manager.create(
      PolygonAnnotationOptions(
        geometry: polygon,
        // Transparent fill — the boundary is invisible today. A dashed
        // orange outline requires a custom LineLayer and is deferred to a
        // later polish pass; PolygonAnnotationOptions doesn't expose a
        // dashed-stroke knob in mapbox_maps_flutter 2.22.
        fillColor: 0x00D97706,
        fillOpacity: 0,
      ),
    );
  }

  Future<void> _renderNewFeatures() async {
    final manager = _pointManager;
    if (manager == null) return;
    for (final f in widget.features) {
      if (!f.isNew) continue;
      final point = _decodePoint(f.geometryGeojson);
      if (point == null) continue;
      await manager.create(
        PointAnnotationOptions(
          geometry: point,
          iconColor: 0xFF3B82F6,
          iconSize: 1.2,
          iconImage: 'marker', // built-in default; if missing, the dot is invisible
        ),
      );
    }
  }

  Polygon? _decodePolygon(String geojson) {
    if (geojson.isEmpty) return null;
    try {
      final decoded = jsonDecode(geojson);
      if (decoded is! Map<String, Object?>) return null;
      final coordsNested = decoded['coordinates'];
      if (coordsNested is! List<Object?>) return null;
      final rings = <List<Position>>[];
      for (final ring in coordsNested) {
        if (ring is! List<Object?>) return null;
        final points = <Position>[];
        for (final p in ring) {
          if (p is! List<Object?>) return null;
          if (p.length < 2) return null;
          final lng = p[0];
          final lat = p[1];
          if (lng is! num || lat is! num) return null;
          points.add(Position(lng.toDouble(), lat.toDouble()));
        }
        rings.add(points);
      }
      return Polygon(coordinates: rings);
    } on Object {
      return null;
    }
  }

  Point? _decodePoint(String geojson) {
    try {
      final decoded = jsonDecode(geojson);
      if (decoded is! Map<String, Object?>) return null;
      if (decoded['type'] != 'Point') return null;
      final coords = decoded['coordinates'];
      if (coords is! List<Object?>) return null;
      if (coords.length < 2) return null;
      final lng = coords[0];
      final lat = coords[1];
      if (lng is! num || lat is! num) return null;
      return Point(coordinates: Position(lng.toDouble(), lat.toDouble()));
    } on Object {
      return null;
    }
  }

  int _colorForStatus(String status) {
    switch (status) {
      case 'complete':
        return 0xFF276749;
      case 'in_progress':
        return 0xFFB7791F;
      default:
        return 0xFFC53030;
    }
  }
}

// ignore: deprecated_member_use
class _FeatureClickHandler extends OnPolygonAnnotationClickListener {
  _FeatureClickHandler({
    required this.annotationToFeature,
    required this.onTap,
  });

  final Map<String, Feature> annotationToFeature;
  final void Function(Feature) onTap;

  @override
  void onPolygonAnnotationClick(PolygonAnnotation annotation) {
    final feature = annotationToFeature[annotation.id];
    if (feature != null) onTap(feature);
  }
}
