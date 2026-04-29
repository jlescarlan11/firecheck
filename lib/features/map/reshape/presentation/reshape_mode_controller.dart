import 'dart:convert';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/polygon_validator.dart';
import 'package:firecheck/features/map/reshape/domain/reshape_mode_state.dart';
import 'package:firecheck/features/map/reshape/domain/reshape_op.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReshapeModeController extends Notifier<ReshapeModeState> {
  @override
  ReshapeModeState build() => const ReshapeModeState();

  void enterReshape({required Feature feature, String? overrideReason}) {
    final rings = _parseGeojson(feature.geometryGeojson);
    state = ReshapeModeState(
      originalFeature: feature,
      workingRings: rings,
      undoStack: const [],
      selfIntersects: false,
      saving: false,
      overrideReason: overrideReason,
    );
  }

  void cancel() {
    state = const ReshapeModeState();
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
      // Latch: once the polygon becomes invalid/degenerate during a drag
      // sequence, keep the flag set until undo/cancel/enterReshape resets it.
      selfIntersects: state.selfIntersects || _hasSelfIntersection(rings[0]),
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
      selfIntersects: state.selfIntersects || _hasSelfIntersection(rings[0]),
    );
  }

  void removeVertex(int ringIdx, int vertexIdx) {
    if (!state.isActive) return;
    final ring = state.workingRings[ringIdx];
    if (ring.length <= 3) return;
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
      selfIntersects: state.selfIntersects || _hasSelfIntersection(rings[0]),
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
    }
    state = state.copyWith(
      workingRings: rings,
      undoStack: state.undoStack.sublist(0, state.undoStack.length - 1),
      selfIntersects: _hasSelfIntersection(rings[0]),
    );
  }

  void markSaving(bool saving) {
    state = state.copyWith(saving: saving);
  }

  /// Serializes the current working copy back to a closed-ring GeoJSON Polygon.
  String serializeWorkingPolygon() {
    final rings = state.workingRings.map((r) {
      final closed = [...r, r.first];
      return closed.map((v) => [v.lng, v.lat]).toList();
    }).toList();
    return jsonEncode({'type': 'Polygon', 'coordinates': rings});
  }
}

List<List<LngLat>> _parseGeojson(String s) {
  final m = jsonDecode(s) as Map<String, dynamic>;
  final coords = m['coordinates'] as List;
  return coords.map<List<LngLat>>((ring) {
    final list = (ring as List).map<LngLat>((p) {
      final pair = p as List;
      return (lng: (pair[0] as num).toDouble(), lat: (pair[1] as num).toDouble());
    }).toList();
    if (list.length >= 2 && list.first == list.last) {
      list.removeLast();
    }
    return list;
  }).toList();
}

List<List<LngLat>> _cloneRings(List<List<LngLat>> rings) {
  return rings.map((r) => List<LngLat>.from(r)).toList();
}

bool _hasSelfIntersection(List<LngLat> outer) {
  // Returns true when the ring is geometrically invalid in any way (transverse
  // self-intersection, zero area, zero-length edge, etc.).  Used together with
  // the latch in moveVertex/addVertex/removeVertex: once the polygon becomes
  // bad during a drag the UI stays red until undo/cancel/enterReshape resets.
  // World-spanning boundary makes rule 4 a guaranteed pass.
  const worldBoundary =
      '{"type":"Polygon","coordinates":[[[-180,-90],[180,-90],[180,90],[-180,90],[-180,-90]]]}';
  final r = validateBuildingPolygon([outer], boundaryGeojson: worldBoundary);
  return !r.valid;
}
