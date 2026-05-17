import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/midpoint_handle.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_overlay.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/vertex_handle.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Feature _seedBuilding() => Feature(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson:
          '{"type":"Polygon","coordinates":[[[10,10],[100,10],[100,100],[10,100],[10,10]]]}',
      isNew: false,
      status: 'unfilled',
      createdAt: DateTime.utc(2026),
    );

Widget _wrap(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: child,
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders 4 vertex + 4 midpoint handles for a 4-vertex ring',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(geometryEditorControllerProvider.notifier)
        .enterReshape(feature: _seedBuilding());

    await tester.pumpWidget(
      _wrap(
        container,
        GeometryEditorOverlay(projection: _IdentityProjection()),
      ),
    );
    expect(find.byType(VertexHandle), findsNWidgets(4));
    expect(find.byType(MidpointHandle), findsNWidgets(4));
  });

  testWidgets('inactive state renders nothing', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _wrap(
        container,
        GeometryEditorOverlay(projection: _IdentityProjection()),
      ),
    );
    expect(find.byType(VertexHandle), findsNothing);
    expect(find.byType(MidpointHandle), findsNothing);
  });
}

class _IdentityProjection implements MapProjection {
  @override
  Offset screenPointFromLngLat(double lng, double lat) => Offset(lng, lat);
  @override
  ({double lng, double lat}) lngLatFromScreenPoint(Offset p) =>
      (lng: p.dx, lat: p.dy);
}
