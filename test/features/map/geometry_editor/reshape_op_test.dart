import 'package:firecheck/features/map/geometry_editor/domain/reshape_op.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Move op stores prev and next', () {
    const op = Move(
      ringIdx: 0,
      vertexIdx: 1,
      prev: (lng: 0, lat: 0),
      next: (lng: 1, lat: 1),
    );
    expect(op.ringIdx, 0);
    expect(op.vertexIdx, 1);
    expect(op.prev, (lng: 0.0, lat: 0.0));
    expect(op.next, (lng: 1.0, lat: 1.0));
  });

  test('Add op stores inserted lngLat', () {
    const op = Add(
      ringIdx: 0,
      vertexIdx: 2,
      lngLat: (lng: 5, lat: 5),
    );
    expect(op.lngLat, (lng: 5.0, lat: 5.0));
  });

  test('Remove op stores removed lngLat', () {
    const op = Remove(
      ringIdx: 0,
      vertexIdx: 0,
      removed: (lng: 9, lat: 9),
    );
    expect(op.removed, (lng: 9.0, lat: 9.0));
  });

  test('Translate op stores lng/lat deltas', () {
    const op = Translate(dLng: 0.5, dLat: -0.25);
    expect(op.dLng, 0.5);
    expect(op.dLat, -0.25);
    // Whole-shape op uses sentinel indices.
    expect(op.ringIdx, -1);
    expect(op.vertexIdx, -1);
  });

  test('switch over ReshapeOp is exhaustive', () {
    const List<ReshapeOp> ops = [
      Move(ringIdx: 0, vertexIdx: 0, prev: (lng: 0, lat: 0), next: (lng: 1, lat: 1)),
      Add(ringIdx: 0, vertexIdx: 0, lngLat: (lng: 0, lat: 0)),
      Remove(ringIdx: 0, vertexIdx: 0, removed: (lng: 0, lat: 0)),
      Translate(dLng: 0, dLat: 0),
    ];
    final names = ops.map((op) => switch (op) {
          Move() => 'move',
          Add() => 'add',
          Remove() => 'remove',
          Translate() => 'translate',
        });
    expect(names, ['move', 'add', 'remove', 'translate']);
  });
}
