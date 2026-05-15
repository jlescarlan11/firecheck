import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;
import 'package:firecheck/features/map/geometry_editor/domain/geometry_editor_state.dart';
import 'package:firecheck/features/map/geometry_editor/domain/reshape_op.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_controller.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
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
    final state = c.read(geometryEditorControllerProvider);
    expect(state.isActive, isFalse);
  });

  test('enterReshape parses geojson into workingRings', () {
    final c = _container();
    addTearDown(c.dispose);
    c.read(geometryEditorControllerProvider.notifier).enterReshape(
          feature: _seedBuilding(),
          overrideReason: null,
        );
    final s = c.read(geometryEditorControllerProvider);
    expect(s.isActive, isTrue);
    expect(s.workingRings, hasLength(1));
    expect(s.workingRings[0], hasLength(4));
    expect(s.isDirty, isFalse);
  });

  test('moveVertex pushes a Move op and updates the ring', () {
    final c = _container();
    addTearDown(c.dispose);
    final notifier = c.read(geometryEditorControllerProvider.notifier);
    notifier.enterReshape(feature: _seedBuilding(), overrideReason: null);
    notifier.moveVertex(0, 0, (lng: 5, lat: 5));
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0][0], (lng: 5.0, lat: 5.0));
    expect(s.undoStack, hasLength(1));
    expect(s.undoStack.last, isA<Move>());
    expect(s.isDirty, isTrue);
  });

  test('addVertex inserts at index and pushes Add', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.addVertex(0, 1, (lng: 0.5, lat: 0));
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0], hasLength(5));
    expect(s.workingRings[0][1], (lng: 0.5, lat: 0));
  });

  test('removeVertex removes and pushes Remove', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.removeVertex(0, 0);
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0], hasLength(3));
  });

  test('removeVertex is a no-op at 3 vertices', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.removeVertex(0, 0);
    n.removeVertex(0, 0);
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0], hasLength(3));
  });

  test('undo pops and inverts last op', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.moveVertex(0, 0, (lng: 5, lat: 5));
    n.undo();
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0][0], (lng: 0.0, lat: 0.0));
    expect(s.undoStack, isEmpty);
  });

  test('cancel returns to inactive', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.moveVertex(0, 0, (lng: 5, lat: 5));
    n.cancel();
    final s = c.read(geometryEditorControllerProvider);
    expect(s.isActive, isFalse);
  });

  Feature _seedRoad({String id = 'r1'}) => Feature(
        id: id,
        assignmentId: 'a1',
        featureType: 'road',
        geometryGeojson:
            '{"type":"LineString","coordinates":[[0,0],[1,1],[2,1]]}',
        isNew: false,
        status: 'unfilled',
        createdAt: DateTime.utc(2026, 1, 1),
      );

  test('translateAll shifts every vertex and pushes a Translate op (US-11)', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.translateAll(10, 20);
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0][0], (lng: 10.0, lat: 20.0));
    expect(s.workingRings[0][1], (lng: 11.0, lat: 20.0));
    expect(s.workingRings[0][2], (lng: 11.0, lat: 21.0));
    expect(s.workingRings[0][3], (lng: 10.0, lat: 21.0));
    expect(s.undoStack.last, isA<Translate>());
  });

  test('translateAll undo restores original positions (US-11)', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.translateAll(10, 20);
    n.undo();
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0][0], (lng: 0.0, lat: 0.0));
    expect(s.workingRings[0][1], (lng: 1.0, lat: 0.0));
    expect(s.undoStack, isEmpty);
  });

  test('translateAll zero-delta is a no-op (US-11)', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);
    n.translateAll(0, 0);
    expect(c.read(geometryEditorControllerProvider).undoStack, isEmpty);
  });

  test('LineString feature enters reshape as open (isClosed=false) (US-10)', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedRoad(), overrideReason: null);
    final s = c.read(geometryEditorControllerProvider);
    expect(s.isActive, isTrue);
    expect(s.isClosed, isFalse);
    expect(s.workingRings, hasLength(1));
    expect(s.workingRings[0], hasLength(3));
  });

  test('LineString serialize round-trips as LineString GeoJSON (US-10)', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedRoad(), overrideReason: null);
    n.moveVertex(0, 1, (lng: 1.5, lat: 1.5));
    final json = n.serializeWorking();
    expect(json, contains('"LineString"'));
    expect(json, contains('1.5'));
  });

  test('polyline removeVertex floor is 2 vertices, not 3 (US-10)', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedRoad(), overrideReason: null);
    // 3 → 2 should succeed
    n.removeVertex(0, 2);
    expect(c.read(geometryEditorControllerProvider).workingRings[0], hasLength(2));
    // 2 → 1 should be refused
    n.removeVertex(0, 1);
    expect(c.read(geometryEditorControllerProvider).workingRings[0], hasLength(2));
  });

  test('polyline never sets selfIntersects (US-10)', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedRoad(), overrideReason: null);
    // Try to force a degenerate state — should not flip the flag for polylines.
    n.moveVertex(0, 0, (lng: 1, lat: 1));
    n.moveVertex(0, 1, (lng: 1, lat: 1));
    expect(c.read(geometryEditorControllerProvider).selfIntersects, isFalse);
  });

  test('selfIntersects flag tracks bowtie state during drag', () {
    final c = _container();
    addTearDown(c.dispose);
    final n = c.read(geometryEditorControllerProvider.notifier);
    n.enterReshape(feature: _seedBuilding(), overrideReason: null);

    n.moveVertex(0, 1, (lng: 1, lat: 1));
    final s1 = c.read(geometryEditorControllerProvider);
    expect(s1.workingRings[0][1], (lng: 1.0, lat: 1.0));

    n.moveVertex(0, 1, (lng: 0, lat: 1));
    n.moveVertex(0, 3, (lng: 1, lat: 0));
    final s2 = c.read(geometryEditorControllerProvider);
    expect(s2.selfIntersects, isTrue);
  });

  group('sketch state', () {
    test('default state has no pending feature type and is not active', () {
      const s = GeometryEditorState();
      expect(s.pendingFeatureType, isNull);
      expect(s.isSketchMode, isFalse);
      expect(s.isActive, isFalse);
    });

    test('pendingFeatureType set with no originalFeature → isSketchMode + isActive', () {
      const s = GeometryEditorState(pendingFeatureType: 'building');
      expect(s.pendingFeatureType, 'building');
      expect(s.isSketchMode, isTrue);
      expect(s.isActive, isTrue);
    });

    test('originalFeature set → isActive remains true (reshape mode)', () {
      final s = GeometryEditorState(
        originalFeature: _seedBuilding(),
        pendingFeatureType: null,
      );
      expect(s.isSketchMode, isFalse);
      expect(s.isActive, isTrue);
    });
  });

  group('enterSketch', () {
    ProviderContainer makeContainer() => ProviderContainer();

    test('building → empty closed ring, sketch mode active', () {
      final c = makeContainer();
      c.read(geometryEditorControllerProvider.notifier)
          .enterSketch(featureType: 'building');
      final s = c.read(geometryEditorControllerProvider);
      expect(s.pendingFeatureType, 'building');
      expect(s.isSketchMode, isTrue);
      expect(s.isClosed, isTrue);
      expect(s.workingRings, [<LngLat>[]]);
      expect(s.undoStack, isEmpty);
      expect(s.selfIntersects, isFalse);
    });

    test('road → empty open ring, isClosed false', () {
      final c = makeContainer();
      c.read(geometryEditorControllerProvider.notifier)
          .enterSketch(featureType: 'road');
      final s = c.read(geometryEditorControllerProvider);
      expect(s.pendingFeatureType, 'road');
      expect(s.isClosed, isFalse);
      expect(s.workingRings, [<LngLat>[]]);
    });

    test('point → empty open ring, isClosed false', () {
      final c = makeContainer();
      c.read(geometryEditorControllerProvider.notifier)
          .enterSketch(featureType: 'point');
      final s = c.read(geometryEditorControllerProvider);
      expect(s.pendingFeatureType, 'point');
      expect(s.isClosed, isFalse);
    });

    test('cancel() clears sketch state', () {
      final c = makeContainer();
      final n = c.read(geometryEditorControllerProvider.notifier)
        ..enterSketch(featureType: 'building');
      n.cancel();
      final s = c.read(geometryEditorControllerProvider);
      expect(s.isActive, isFalse);
      expect(s.pendingFeatureType, isNull);
    });
  });
}
