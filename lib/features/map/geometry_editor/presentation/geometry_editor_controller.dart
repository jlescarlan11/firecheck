import 'dart:convert';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/polygon_validator.dart';
import 'package:firecheck/features/map/geometry_editor/domain/geometry_editor_state.dart';
import 'package:firecheck/features/map/geometry_editor/domain/reshape_op.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GeometryEditorController extends Notifier<GeometryEditorState> {
  @override
  GeometryEditorState build() => const GeometryEditorState();

  void enterReshape({required Feature feature, String? overrideReason}) {
    final parsed = _parseGeojson(feature.geometryGeojson);
    state = GeometryEditorState(
      originalFeature: feature,
      workingRings: parsed.rings,
      overrideReason: overrideReason,
      isClosed: parsed.isClosed,
    );
  }

  void enterSketch({required String featureType}) {
    state = GeometryEditorState(
      pendingFeatureType: featureType,
      workingRings: const [<LngLat>[]],
      isClosed: featureType == 'building',
    );
  }

  void cancel() {
    state = const GeometryEditorState();
  }

  void moveVertex(int ringIdx, int vertexIdx, LngLat next) {
    if (!state.isActive) return;
    final rings = _cloneRings(state.workingRings);
    final prev = rings[ringIdx][vertexIdx];
    rings[ringIdx][vertexIdx] = next;
    final newStack = [
      ...state.undoStack,
      Move(ringIdx: ringIdx, vertexIdx: vertexIdx, prev: prev, next: next),
    ];
    state = state.copyWith(
      workingRings: rings,
      undoStack: newStack,
      selfIntersects: _recomputeSelfIntersect(state, rings),
    );
  }

  void addVertex(int ringIdx, int vertexIdx, LngLat lngLat) {
    if (!state.isActive) return;
    final rings = _cloneRings(state.workingRings);
    rings[ringIdx].insert(vertexIdx, lngLat);
    final newStack = [
      ...state.undoStack,
      Add(ringIdx: ringIdx, vertexIdx: vertexIdx, lngLat: lngLat),
    ];
    state = state.copyWith(
      workingRings: rings,
      undoStack: newStack,
      selfIntersects: _recomputeSelfIntersect(state, rings),
    );
  }

  void removeVertex(int ringIdx, int vertexIdx) {
    if (!state.isActive) return;
    final ring = state.workingRings[ringIdx];
    // Polygons in open form need ≥3 vertices to remain a valid ring; polylines
    // need ≥2 vertices to remain a line.
    final minVertices = state.isClosed ? 3 : 2;
    if (ring.length <= minVertices) return;
    final removed = ring[vertexIdx];
    final rings = _cloneRings(state.workingRings);
    rings[ringIdx].removeAt(vertexIdx);
    final newStack = [
      ...state.undoStack,
      Remove(ringIdx: ringIdx, vertexIdx: vertexIdx, removed: removed),
    ];
    state = state.copyWith(
      workingRings: rings,
      undoStack: newStack,
      selfIntersects: _recomputeSelfIntersect(state, rings),
    );
  }

  /// Shifts every vertex of every ring by ([dLng], [dLat]). Shape is preserved
  /// exactly, so the polygon-validity flag does not change.
  void translateAll(double dLng, double dLat) {
    if (!state.isActive) return;
    if (dLng == 0 && dLat == 0) return;
    final rings = state.workingRings
        .map(
          (r) => r
              .map(
                (v) => (lng: v.lng + dLng, lat: v.lat + dLat) as LngLat,
              )
              .toList(),
        )
        .toList();
    final newStack = [
      ...state.undoStack,
      Translate(dLng: dLng, dLat: dLat),
    ];
    state = state.copyWith(
      workingRings: rings,
      undoStack: newStack,
      // Translation preserves shape; do not change the validity latch.
    );
  }

  void undo() {
    if (state.undoStack.isEmpty) return;
    final top = state.undoStack.last;
    final rings = _cloneRings(state.workingRings);
    switch (top) {
      case Move():
        rings[top.ringIdx][top.vertexIdx] = top.prev;
      case Add():
        rings[top.ringIdx].removeAt(top.vertexIdx);
      case Remove():
        rings[top.ringIdx].insert(top.vertexIdx, top.removed);
      case Translate():
        for (var r = 0; r < rings.length; r++) {
          rings[r] = rings[r]
              .map(
                (v) => (lng: v.lng - top.dLng, lat: v.lat - top.dLat) as LngLat,
              )
              .toList();
        }
    }
    state = state.copyWith(
      workingRings: rings,
      undoStack: state.undoStack.sublist(0, state.undoStack.length - 1),
      selfIntersects: _recomputeSelfIntersect(state, rings),
    );
  }

  void markSaving({required bool saving}) {
    state = state.copyWith(saving: saving);
  }

  /// Serializes the working copy back to GeoJSON in the same geometry type
  /// that was loaded — Polygon for closed shapes, LineString (or
  /// MultiLineString when there are multiple parts) for open ones.
  String serializeWorking() {
    if (state.isClosed) {
      final rings = state.workingRings.map((r) {
        final closed = [...r, r.first];
        return closed.map((v) => [v.lng, v.lat]).toList();
      }).toList();
      return jsonEncode({'type': 'Polygon', 'coordinates': rings});
    }
    if (state.workingRings.length == 1) {
      final coords =
          state.workingRings[0].map((v) => [v.lng, v.lat]).toList();
      return jsonEncode({'type': 'LineString', 'coordinates': coords});
    }
    final coords = state.workingRings
        .map((part) => part.map((v) => [v.lng, v.lat]).toList())
        .toList();
    return jsonEncode({'type': 'MultiLineString', 'coordinates': coords});
  }

  /// Legacy alias retained for existing call sites that expect a polygon-only
  /// serializer. New code should call [serializeWorking].
  String serializeWorkingPolygon() => serializeWorking();
}

class _ParsedGeometry {
  const _ParsedGeometry({required this.rings, required this.isClosed});
  final List<List<LngLat>> rings;
  final bool isClosed;
}

_ParsedGeometry _parseGeojson(String s) {
  final m = jsonDecode(s) as Map<String, dynamic>;
  final type = m['type'] as String;
  final coords = m['coordinates'] as List;
  if (type == 'Polygon') {
    return _ParsedGeometry(
      rings: coords.map<List<LngLat>>(_parseRing).toList(),
      isClosed: true,
    );
  }
  if (type == 'LineString') {
    return _ParsedGeometry(
      rings: [_parseLine(coords)],
      isClosed: false,
    );
  }
  if (type == 'MultiLineString') {
    return _ParsedGeometry(
      rings: coords
          .map<List<LngLat>>((part) => _parseLine(part as List))
          .toList(),
      isClosed: false,
    );
  }
  throw FormatException('Unsupported geometry type for reshape: $type');
}

List<LngLat> _parseRing(dynamic ring) {
  final list = (ring as List).map<LngLat>((p) {
    final pair = p as List;
    return (
      lng: (pair[0] as num).toDouble(),
      lat: (pair[1] as num).toDouble(),
    );
  }).toList();
  // Strip the duplicated closing vertex if present (open form).
  if (list.length >= 2 && list.first == list.last) {
    list.removeLast();
  }
  return list;
}

List<LngLat> _parseLine(List coords) => coords.map<LngLat>((p) {
      final pair = p as List;
      return (
        lng: (pair[0] as num).toDouble(),
        lat: (pair[1] as num).toDouble(),
      );
    }).toList();

List<List<LngLat>> _cloneRings(List<List<LngLat>> rings) {
  return rings.map(List<LngLat>.from).toList();
}

bool _recomputeSelfIntersect(
  GeometryEditorState state,
  List<List<LngLat>> rings,
) {
  // Polylines don't have a polygon-validity notion; skip the check entirely.
  if (!state.isClosed) return false;
  // Latch behavior: once invalid during an editing burst, stay invalid until
  // undo/cancel/enterReshape resets — preserved from the original polygon-only
  // implementation.
  return state.selfIntersects || _hasSelfIntersection(rings[0]);
}

bool _hasSelfIntersection(List<LngLat> outer) {
  // World-spanning boundary makes the boundary-containment rule a guaranteed
  // pass; we only care about the intrinsic polygon-validity rules here.
  const worldBoundary =
      '{"type":"Polygon","coordinates":[[[-180,-90],[180,-90],[180,90],[-180,90],[-180,-90]]]}';
  final r = validateBuildingPolygon([outer], boundaryGeojson: worldBoundary);
  return !r.valid;
}
