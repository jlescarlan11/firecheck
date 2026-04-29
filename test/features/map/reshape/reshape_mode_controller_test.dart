import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/reshape/domain/reshape_op.dart';
import 'package:firecheck/features/map/reshape/presentation/reshape_mode_controller.dart';
import 'package:firecheck/features/map/reshape/presentation/reshape_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container() => ProviderContainer();

Feature _seedBuilding({String id = 'f1'}) => Feature(
      id: id,
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson:
          '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}',
      isNew: false,
      status: 'unfilled',
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('initial state is inactive', () {
    final c = _container();
    addTearDown(c.dispose);
    final state = c.read(reshapeModeControllerProvider);
    expect(state.isActive, isFalse);
  });

  test('enterReshape parses geojson into workingRings', () {
    final c = _container();
    addTearDown(c.dispose);
    c.read(reshapeModeControllerProvider.notifier).enterReshape(
          feature: _seedBuilding(),
          overrideReason: null,
        );
    final s = c.read(reshapeModeControllerProvider);
    expect(s.isActive, isTrue);
    expect(s.workingRings, hasLength(1));
    expect(s.workingRings[0], hasLength(4));
    expect(s.isDirty, isFalse);
  });

  test('moveVertex pushes a Move op and updates the ring', () {
    final c = _container();
    addTearDown(c.dispose);
    final notifier = c.read(reshapeModeControllerProvider.notifier);
    notifier.enterReshape(feature: _seedBuilding(), overrideReason: null);
    notifier.moveVertex(0, 0, (lng: 5, lat: 5));
    final s = c.read(reshapeModeControllerProvider);
    expect(s.workingRings[0][0], (lng: 5.0, lat: 5.0));
    expect(s.undoStack, hasLength(1));
    expect(s.undoStack.last, isA<Move>());
    expect(s.isDirty, isTrue);
  });

  test('addVertex inserts at index and pushes Add', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(reshapeModeControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.addVertex(0, 1, (lng: 0.5, lat: 0));
    final s = c.read(reshapeModeControllerProvider);
    expect(s.workingRings[0], hasLength(5));
    expect(s.workingRings[0][1], (lng: 0.5, lat: 0));
  });

  test('removeVertex removes and pushes Remove', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(reshapeModeControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.removeVertex(0, 0);
    final s = c.read(reshapeModeControllerProvider);
    expect(s.workingRings[0], hasLength(3));
  });

  test('removeVertex is a no-op at 3 vertices', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(reshapeModeControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.removeVertex(0, 0);
    n.removeVertex(0, 0);
    final s = c.read(reshapeModeControllerProvider);
    expect(s.workingRings[0], hasLength(3));
  });

  test('undo pops and inverts last op', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(reshapeModeControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.moveVertex(0, 0, (lng: 5, lat: 5));
    n.undo();
    final s = c.read(reshapeModeControllerProvider);
    expect(s.workingRings[0][0], (lng: 0.0, lat: 0.0));
    expect(s.undoStack, isEmpty);
  });

  test('cancel returns to inactive', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(reshapeModeControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.moveVertex(0, 0, (lng: 5, lat: 5));
    n.cancel();
    final s = c.read(reshapeModeControllerProvider);
    expect(s.isActive, isFalse);
  });

  test('selfIntersects flag tracks bowtie state during drag', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(reshapeModeControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);

    n.moveVertex(0, 1, (lng: 1, lat: 1));
    final s1 = c.read(reshapeModeControllerProvider);
    expect(s1.workingRings[0][1], (lng: 1.0, lat: 1.0));

    n.moveVertex(0, 1, (lng: 0, lat: 1));
    n.moveVertex(0, 3, (lng: 1, lat: 0));
    final s2 = c.read(reshapeModeControllerProvider);
    expect(s2.selfIntersects, isTrue);
  });
}
