// Issue #42: reshape road polylines with the same gestures as polygons.
// Existing controller-level tests cover LineString reshape; this widget
// test exercises the long-press → action sheet → reshape entry flow end-
// to-end for a road feature so the contract is locked in at the UI seam.
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'map_screen_reshape_test.dart' as base;

Feature fakeRoadFeature() => Feature(
      id: 'r1',
      assignmentId: 'a1',
      featureType: 'road',
      geometryGeojson:
          '{"type":"LineString","coordinates":'
          '[[123.8825,10.3180],[123.8835,10.3180],[123.8835,10.3185]]}',
      isNew: false,
      status: 'unfilled',
      createdAt: DateTime.utc(2026),
    );

void main() {
  testWidgets(
      'Issue #42: road long-press opens action sheet; Reshape enters '
      'isClosed=false edit mode', (tester) async {
    final renderer = FakeMapRenderer();
    final road = fakeRoadFeature();

    final container = await base.pumpMap(
      tester,
      renderer: renderer,
      features: [road],
      // Mid-feature GPS fix → no override dialog.
      positionStream: Stream<Position>.value(
        base.fakePos(lat: 10.3182, lng: 123.8830),
      ),
    );

    await renderer.simulatePolygonLongPress(road);
    await tester.pumpAndSettle();

    // Same action sheet polygons get.
    expect(
      find.byKey(const Key('reshape.actionsheet.openForm')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reshape.actionsheet.reshape')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
    await tester.pumpAndSettle();

    final state = container.read(geometryEditorControllerProvider);
    expect(state.isActive, isTrue);
    expect(state.originalFeature?.id, road.id);
    // Polyline reshape must NOT enable the closed-shape body-drag /
    // self-intersection latches.
    expect(state.isClosed, isFalse);
    expect(state.selfIntersects, isFalse);
  });
}
