import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/geometry_editor/domain/geometry_editor_state.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_banner.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_controller.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness({required Widget child, required GeometryEditorState seed}) {
  return ProviderScope(
    overrides: [
      geometryEditorControllerProvider.overrideWith(() => _StubController(seed)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

class _StubController extends GeometryEditorController {
  _StubController(this._seed);
  final GeometryEditorState _seed;

  @override
  GeometryEditorState build() => _seed;
}

Feature _fakeFeature() => Feature(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson:
          '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}',
      isNew: false,
      createdAt: DateTime.utc(2026, 1, 1),
      status: 'unfilled',
    );

void main() {
  testWidgets('sketch mode shows Finish label', (tester) async {
    await tester.pumpWidget(_harness(
      seed: const GeometryEditorState(pendingFeatureType: 'building'),
      child: const GeometryEditorBanner(
        editCount: 0,
        undoEnabled: false,
        saveEnabled: false,
      ),
    ));
    await tester.pump();
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('reshape mode shows Save label', (tester) async {
    final featureSeed = _fakeFeature();
    await tester.pumpWidget(_harness(
      seed: GeometryEditorState(originalFeature: featureSeed),
      child: const GeometryEditorBanner(
        editCount: 1,
        undoEnabled: true,
        saveEnabled: true,
      ),
    ));
    await tester.pump();
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Finish'), findsNothing);
  });
}
