import 'dart:convert';

import 'package:firecheck/core/db/database.dart';
import 'package:flutter/material.dart';
// Hide Feature because the Drift-generated row class (imported above) shares
// the same name with `mapbox_maps_flutter`'s GeoJSON Feature wrapper.
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Feature;

/// Minimal surface the map screen actually needs. Lets tests substitute a
/// renderer that doesn't require a GL context. Intentionally an abstract
/// class rather than a typedef so concrete implementations (Fake + real
/// Mapbox) can be distinguished by type in tests and provider overrides.
// ignore: one_member_abstracts
abstract class MapRenderer {
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
  });
}

/// Fake for widget tests — renders one tappable tile per feature instead of
/// a real map. Matches the real renderer's tap contract.
class FakeMapRenderer implements MapRenderer {
  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
  }) {
    return ListView(
      shrinkWrap: true,
      children: features.map((f) {
        return GestureDetector(
          key: Key('fake-map-feature-${f.id}'),
          onTap: () => onFeatureTap(f),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(8),
            color: _colorForStatus(f.status),
            child: Text('feature ${f.id}'),
          ),
        );
      }).toList(),
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

/// Real renderer backed by `mapbox_maps_flutter` 2.22. Renders an actual map
/// with polygon annotation managers for features + boundary, and a location
/// component pinned to GPS via [LocationSettings].
class MapboxMapRenderer implements MapRenderer {
  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
  }) {
    return _MapboxMapView(
      features: features,
      boundaryGeojson: boundaryGeojson,
      onFeatureTap: onFeatureTap,
    );
  }
}

class _MapboxMapView extends StatefulWidget {
  const _MapboxMapView({
    required this.features,
    required this.boundaryGeojson,
    required this.onFeatureTap,
  });

  final List<Feature> features;
  final String boundaryGeojson;
  final void Function(Feature) onFeatureTap;

  @override
  State<_MapboxMapView> createState() => _MapboxMapViewState();
}

class _MapboxMapViewState extends State<_MapboxMapView> {
  PolygonAnnotationManager? _featureManager;
  PolygonAnnotationManager? _boundaryManager;

  // Map annotation-id to feature. Populated as each polygon is created so
  // the tap listener can resolve the Drift row from the tapped annotation.
  final Map<String, Feature> _annotationToFeature = <String, Feature>{};

  @override
  Widget build(BuildContext context) {
    return MapWidget(
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(123.88270, 10.31810)),
        zoom: 15,
      ),
      onMapCreated: _onMapCreated,
    );
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    // Enable the built-in GPS pin. Non-fatal — permission might not be
    // granted yet; in that case the puck simply doesn't appear.
    try {
      await map.location.updateSettings(
        LocationComponentSettings(enabled: true, pulsingEnabled: true),
      );
    } on Object {
      // Swallow — location is a nice-to-have here.
    }

    // Two managers so feature + boundary paint properties don't collide.
    _featureManager = await map.annotations.createPolygonAnnotationManager();
    _boundaryManager = await map.annotations.createPolygonAnnotationManager();

    await _renderFeatures();
    await _renderBoundary();

    // ignore: deprecated_member_use
    _featureManager!.addOnPolygonAnnotationClickListener(
      _FeatureClickHandler(
        annotationToFeature: _annotationToFeature,
        onTap: widget.onFeatureTap,
      ),
    );
  }

  Future<void> _renderFeatures() async {
    final manager = _featureManager;
    if (manager == null) return;
    for (final f in widget.features) {
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
