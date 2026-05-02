import 'dart:async';
import 'dart:convert';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/point_in_polygon.dart';
import 'package:firecheck/core/geo/polyline_midpoint.dart';
import 'package:firecheck/features/map/presentation/camera_target.dart';
import 'package:flutter/material.dart';
// Hide Feature because the Drift-generated row class (imported above) shares
// the same name with `mapbox_maps_flutter`'s GeoJSON Feature wrapper.
// Hide Size because mapbox_maps_flutter ships its own Size class that
// shadows Flutter's `dart:ui` Size — we use Flutter's everywhere here.
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    hide Feature, Size;

/// Minimal surface the map screen actually needs.
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
    // US-9 reshape additions:
    void Function(Feature)? onPolygonLongPress,
    String? reshapeWorkingPolygonGeojson,
    String? reshapeInvalidEdgeGeojson,
    void Function(MapProjection projection)? onProjectionReady,
  });
}

/// Lat/lng <-> screen-px projection seam exposed by the renderer to overlays.
abstract class MapProjection {
  Offset screenPointFromLngLat(double lng, double lat);
  ({double lng, double lat}) lngLatFromScreenPoint(Offset point);
}

/// Fake for widget tests — renders one tappable tile per feature instead of
/// a real map. Matches the real renderer's tap contract.
class FakeMapRenderer implements MapRenderer {
  void Function(double, double)? _lastOnLongPress;
  void Function(double, double, double)? _lastOnCameraChanged;
  void Function(Feature)? _lastOnPolygonLongPress;
  CameraTarget? lastCameraTarget;
  CameraTarget? lastInitialCameraTarget;
  String? lastReshapeWorkingPolygonGeojson;
  String? lastReshapeInvalidEdgeGeojson;
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
  Future<void> simulateCameraChanged(
    double zoom,
    double lat,
    double lng,
  ) async {
    final cb = _lastOnCameraChanged;
    if (cb != null) cb(zoom, lat, lng);
  }

  /// Test seam: simulates a long-press on a polygon feature. Invokes the
  /// most recently stored onPolygonLongPress callback.
  Future<void> simulatePolygonLongPress(Feature f) async {
    _lastOnPolygonLongPress?.call(f);
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
    void Function(Feature)? onPolygonLongPress,
    String? reshapeWorkingPolygonGeojson,
    String? reshapeInvalidEdgeGeojson,
    void Function(MapProjection projection)? onProjectionReady,
  }) {
    _lastOnLongPress = onLongPress;
    _lastOnCameraChanged = onCameraChanged;
    _lastOnPolygonLongPress = onPolygonLongPress;
    lastInitialCameraTarget = initialCameraTarget;
    if (cameraTarget != null && cameraTarget != lastCameraTarget) {
      cameraTargetHistory.add(cameraTarget);
    }
    lastCameraTarget = cameraTarget;
    lastReshapeWorkingPolygonGeojson = reshapeWorkingPolygonGeojson;
    lastReshapeInvalidEdgeGeojson = reshapeInvalidEdgeGeojson;

    // Identity projection: each lng,lat maps to (lng, lat) screen pixels.
    onProjectionReady?.call(_IdentityProjection());

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
            onLongPress:
                f.isNew ? null : () => onPolygonLongPress?.call(f),
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

/// Identity-degree projection used by FakeMapRenderer for tests.
class _IdentityProjection implements MapProjection {
  @override
  Offset screenPointFromLngLat(double lng, double lat) => Offset(lng, lat);

  @override
  ({double lng, double lat}) lngLatFromScreenPoint(Offset point) =>
      (lng: point.dx, lat: point.dy);
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
    void Function(Feature)? onPolygonLongPress,
    String? reshapeWorkingPolygonGeojson,
    String? reshapeInvalidEdgeGeojson,
    void Function(MapProjection projection)? onProjectionReady,
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
      onPolygonLongPress: onPolygonLongPress,
      reshapeWorkingPolygonGeojson: reshapeWorkingPolygonGeojson,
      reshapeInvalidEdgeGeojson: reshapeInvalidEdgeGeojson,
      onProjectionReady: onProjectionReady,
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
    this.onPolygonLongPress,
    this.reshapeWorkingPolygonGeojson,
    this.reshapeInvalidEdgeGeojson,
    this.onProjectionReady,
  });

  final List<Feature> features;
  final String boundaryGeojson;
  final void Function(Feature) onFeatureTap;
  final void Function(double lat, double lng)? onLongPress;
  final void Function(double zoom, double lat, double lng)? onCameraChanged;
  final bool addModeActive;
  final CameraTarget? cameraTarget;
  final CameraTarget? initialCameraTarget;
  final void Function(Feature)? onPolygonLongPress;
  final String? reshapeWorkingPolygonGeojson;
  final String? reshapeInvalidEdgeGeojson;
  final void Function(MapProjection projection)? onProjectionReady;

  @override
  State<_MapboxMapView> createState() => _MapboxMapViewState();
}

class _MapboxMapViewState extends State<_MapboxMapView> {
  PolygonAnnotationManager? _featureManager;
  PolygonAnnotationManager? _boundaryManager;
  PolylineAnnotationManager? _roadManager;
  PointAnnotationManager? _pointManager;
  MapboxMap? _mapboxMap;

  // Map annotation-id to feature. Populated as each polygon is created so
  // the tap listener can resolve the Drift row from the tapped annotation.
  final Map<String, Feature> _annotationToFeature = <String, Feature>{};

  // US-9: working-polygon overlay rendered while reshape mode is active.
  PolygonAnnotation? _reshapeWorkingAnnotation;

  // US-9: lat/lng <-> screen-px projection state. Refreshed on camera change
  // so ReshapeOverlay can read it synchronously during finger drags.
  _MapboxProjection? _projection;
  Size? _viewportSize;

  // US-9 T13: set to true when _onMapCreated runs before the first
  // LayoutBuilder pass so we can defer projection init until the viewport
  // size is known.
  bool _projectionReadyPending = false;

  @override
  void dispose() {
    _boundaryManager = null;
    _featureManager = null;
    _roadManager = null;
    _pointManager = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initialCameraTarget;
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        // If _onMapCreated ran before the first layout pass, finish projection
        // initialization now that we have a viewport.
        if (_projectionReadyPending && _projection != null) {
          _projectionReadyPending = false;
          final s = Size(constraints.maxWidth, constraints.maxHeight);
          unawaited(_projection!.refresh(s.width, s.height).then((_) {
            if (mounted) widget.onProjectionReady?.call(_projection!);
          }),);
        }

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
          onLongTapListener: (MapContentGestureContext ctx) async {
            // Add-mode placement remains unchanged.
            if (widget.addModeActive && widget.onLongPress != null) {
              final pos = ctx.point.coordinates;
              widget.onLongPress!(pos.lat.toDouble(), pos.lng.toDouble());
              return;
            }
            // Reshape entry: hit-test all rendered polygons against the
            // long-press point.
            final cb = widget.onPolygonLongPress;
            if (cb == null) return;
            final hit = _hitTestPolygon(
              ctx.point.coordinates.lat.toDouble(),
              ctx.point.coordinates.lng.toDouble(),
            );
            if (hit != null) cb(hit);
          },
          onCameraChangeListener: (CameraChangedEventData data) {
            final cb = widget.onCameraChanged;
            final state = data.cameraState;
            cb?.call(
              state.zoom,
              state.center.coordinates.lat.toDouble(),
              state.center.coordinates.lng.toDouble(),
            );
            final projection = _projection;
            final size = _viewportSize;
            if (projection != null && size != null) {
              unawaited(
                projection.refresh(size.width, size.height).then((_) {
                  widget.onProjectionReady?.call(projection);
                }),
              );
            }
          },
        );
      },
    );
  }

  Feature? _hitTestPolygon(double lat, double lng) {
    for (final f in widget.features) {
      if (f.isNew) continue;
      if (pointInPolygonGeojson(lat, lng, f.geometryGeojson)) return f;
    }
    return null;
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

    // Disable rotation and pitch globally. The reshape overlay's
    // _MapboxProjection uses a north-up linear corner-calibration (spec §14
    // first pass); rotated or pitched maps would make handle positions drift
    // away from their polygon corners. The app UI is also designed top-down
    // (no compass, no pitch indicator), so this matches the visual model.
    try {
      await map.gestures.updateSettings(
        GesturesSettings(rotateEnabled: false, pitchEnabled: false),
      );
    } on Object {
      // Non-fatal — gesture settings are a hardening measure, not load-bearing.
    }

    // GL context reset (e.g., app evicted from background): null any
    // annotation references from a prior context so they're not double-deleted.
    _reshapeWorkingAnnotation = null;

    // Boundary manager FIRST so it sits BENEATH features in the layer stack.
    // Mapbox stacks annotation managers by creation order: later managers
    // render on top. Features must be on top so polygon taps hit them
    // (Bug 13 — caught manually). The boundary's polygon is fully
    // transparent, but Mapbox still hit-tests it; if it sat on top, every
    // tap inside the assignment area would land on the (listener-less)
    // boundary polygon and never reach the feature manager.
    _boundaryManager = await map.annotations.createPolygonAnnotationManager();
    _featureManager = await map.annotations.createPolygonAnnotationManager();
    // Road manager above building fills; point manager topmost above roads.
    _roadManager = await map.annotations.createPolylineAnnotationManager();
    _pointManager = await map.annotations.createPointAnnotationManager();

    await _renderBoundary();
    await _renderFeatures();
    await _renderRoads();
    await _renderNewFeatures();

    // ignore: deprecated_member_use
    _featureManager!.addOnPolygonAnnotationClickListener(
      _FeatureClickHandler(
        annotationToFeature: _annotationToFeature,
        onTap: widget.onFeatureTap,
      ),
    );
    // ignore: deprecated_member_use
    _roadManager!.addOnPolylineAnnotationClickListener(
      _RoadClickHandler(
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

    // US-9: instantiate the projection now that the map is alive and run
    // an initial refresh so ReshapeOverlay has correct screen-px math
    // before the user's first drag.
    final projection = _MapboxProjection(map);
    _projection = projection;
    final size = _viewportSize;
    if (size != null) {
      try {
        await projection.refresh(size.width, size.height);
        widget.onProjectionReady?.call(projection);
      } on Object {
        // Refresh failures are non-fatal; ReshapeOverlay tolerates a
        // not-yet-ready projection (returns Offset.zero).
      }
    } else {
      // Layout hasn't run yet. Defer to the next LayoutBuilder pass.
      _projectionReadyPending = true;
    }

    // Render any working polygon supplied before the map booted.
    if (widget.reshapeWorkingPolygonGeojson != null &&
        widget.reshapeWorkingPolygonGeojson!.isNotEmpty) {
      unawaited(_rerenderReshapeWorkingPolygon());
    }
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
    if (!featuresChanged &&
        oldWidget.reshapeWorkingPolygonGeojson !=
            widget.reshapeWorkingPolygonGeojson) {
      unawaited(_rerenderReshapeWorkingPolygon());
    }
    final target = widget.cameraTarget;
    if (target != null && target != oldWidget.cameraTarget) {
      unawaited(_flyToCameraTarget(target));
    }
  }

  Future<void> _rerenderReshapeWorkingPolygon() async {
    final manager = _featureManager;
    if (manager == null) return;
    if (_reshapeWorkingAnnotation != null) {
      await manager.delete(_reshapeWorkingAnnotation!);
      _reshapeWorkingAnnotation = null;
    }
    final geojson = widget.reshapeWorkingPolygonGeojson;
    if (geojson == null || geojson.isEmpty) return;
    final polygon = _decodePolygon(geojson);
    if (polygon == null) return;
    _reshapeWorkingAnnotation = await manager.create(
      PolygonAnnotationOptions(
        geometry: polygon,
        fillColor: 0xFF3182CE,
        fillOpacity: 0.3,
      ),
    );
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
    await _roadManager?.deleteAll();
    _reshapeWorkingAnnotation = null; // deleteAll() destroyed it too
    _annotationToFeature.clear();
    await _renderFeatures();
    await _renderRoads();
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
    // ignore: deprecated_member_use
    _roadManager?.addOnPolylineAnnotationClickListener(
      _RoadClickHandler(
        annotationToFeature: _annotationToFeature,
        onTap: widget.onFeatureTap,
      ),
    );

    // Re-render the in-progress reshape polygon if one is active. Doing this
    // inside _rerenderFeatures serializes it after deleteAll() instead of
    // racing it via a parallel unawaited call from didUpdateWidget.
    if (widget.reshapeWorkingPolygonGeojson != null &&
        widget.reshapeWorkingPolygonGeojson!.isNotEmpty) {
      await _rerenderReshapeWorkingPolygon();
    }
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
      if (f.featureType == 'road') continue;
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

  Future<void> _renderRoads() async {
    final manager = _roadManager;
    if (manager == null) return;
    for (final f in widget.features) {
      if (f.isNew) continue;
      if (f.featureType != 'road') continue;
      final coords = _decodeLineString(f.geometryGeojson);
      if (coords == null) {
        debugPrint(
          '[MapRenderer] skipped road feature ${f.id}: invalid LineString geometry',
        );
        continue;
      }
      final created = await manager.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: coords),
          lineColor: _colorForStatus(f.status),
          lineWidth: 8,
        ),
      );
      _annotationToFeature[created.id] = f;
    }
  }

  List<Position>? _decodeLineString(String geojson) {
    final coords = decodePolylineGeojson(geojson);
    if (coords == null) return null;
    return coords.map((p) => Position(p[0], p[1])).toList();
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

// ignore: deprecated_member_use
class _RoadClickHandler extends OnPolylineAnnotationClickListener {
  _RoadClickHandler({
    required this.annotationToFeature,
    required this.onTap,
  });

  final Map<String, Feature> annotationToFeature;
  final void Function(Feature) onTap;

  @override
  void onPolylineAnnotationClick(PolylineAnnotation annotation) {
    final feature = annotationToFeature[annotation.id];
    if (feature != null) onTap(feature);
  }
}

/// Caches lat/lng <-> screen-px projections via async `coordinateForPixel`
/// and exposes a synchronous linear interpolation. Refreshed on each camera
/// change so ReshapeOverlay (which rebuilds on every Riverpod tick during
/// drags) can read sync without an async hop.
///
/// The linear-corner calibration is approximate near map edges and at very
/// low zoom. At reshape working zoom (>=17) it is sub-pixel inside the
/// visible viewport — acceptable for finger-drag UX.
class _MapboxProjection implements MapProjection {
  _MapboxProjection(this._map);
  final MapboxMap _map;

  Offset? _topLeftPx;
  Position? _topLeftLngLat;
  Offset? _bottomRightPx;
  Position? _bottomRightLngLat;

  Future<void> refresh(double viewportWidth, double viewportHeight) async {
    final tl = await _map.coordinateForPixel(ScreenCoordinate(x: 0, y: 0));
    final br = await _map.coordinateForPixel(
      ScreenCoordinate(x: viewportWidth, y: viewportHeight),
    );
    _topLeftPx = Offset.zero;
    _topLeftLngLat = tl.coordinates;
    _bottomRightPx = Offset(viewportWidth, viewportHeight);
    _bottomRightLngLat = br.coordinates;
  }

  @override
  Offset screenPointFromLngLat(double lng, double lat) {
    final tlP = _topLeftPx;
    final brP = _bottomRightPx;
    final tlC = _topLeftLngLat;
    final brC = _bottomRightLngLat;
    if (tlP == null || brP == null || tlC == null || brC == null) {
      return Offset.zero;
    }
    final tx = (lng - tlC.lng) / (brC.lng - tlC.lng);
    final ty = (lat - tlC.lat) / (brC.lat - tlC.lat);
    return Offset(
      tlP.dx + tx * (brP.dx - tlP.dx),
      tlP.dy + ty * (brP.dy - tlP.dy),
    );
  }

  @override
  ({double lng, double lat}) lngLatFromScreenPoint(Offset p) {
    final tlP = _topLeftPx;
    final brP = _bottomRightPx;
    final tlC = _topLeftLngLat;
    final brC = _bottomRightLngLat;
    if (tlP == null || brP == null || tlC == null || brC == null) {
      return (lng: 0.0, lat: 0.0);
    }
    final tx = (p.dx - tlP.dx) / (brP.dx - tlP.dx);
    final ty = (p.dy - tlP.dy) / (brP.dy - tlP.dy);
    return (
      lng: tlC.lng + tx * (brC.lng - tlC.lng),
      lat: tlC.lat + ty * (brC.lat - tlC.lat),
    );
  }
}
