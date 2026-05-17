import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_banner.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_controller.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/features/map/geometry_editor/domain/geometry_editor_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        geometryEditorControllerProvider.overrideWith(
          () => _ReshapeStub(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(body: child),
      ),
    );

/// Stub that returns the default GeometryEditorState (reshape mode — both
/// originalFeature and pendingFeatureType are null, so isSketchMode == false).
class _ReshapeStub extends GeometryEditorController {
  @override
  GeometryEditorState build() => const GeometryEditorState();
}

void main() {
  testWidgets('renders edit count and title', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GeometryEditorBanner(
          editCount: 3,
          undoEnabled: true,
          saveEnabled: true,
        ),
      ),
    );
    expect(find.textContaining('3'), findsOneWidget);
  });

  testWidgets('Save tap fires onSave', (tester) async {
    var saves = 0;
    await tester.pumpWidget(
      _wrap(
        GeometryEditorBanner(
          editCount: 1,
          undoEnabled: true,
          saveEnabled: true,
          onSave: () => saves++,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('reshape.banner.save')));
    expect(saves, 1);
  });

  testWidgets('Cancel tap fires onCancel', (tester) async {
    var cancels = 0;
    await tester.pumpWidget(
      _wrap(
        GeometryEditorBanner(
          editCount: 0,
          undoEnabled: false,
          saveEnabled: false,
          onCancel: () => cancels++,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('reshape.banner.cancel')));
    expect(cancels, 1);
  });

  testWidgets('Undo tap fires onUndo when enabled', (tester) async {
    var undos = 0;
    await tester.pumpWidget(
      _wrap(
        GeometryEditorBanner(
          editCount: 1,
          undoEnabled: true,
          saveEnabled: true,
          onUndo: () => undos++,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('reshape.banner.undo')));
    expect(undos, 1);
  });

  testWidgets('Save disabled does not fire onSave', (tester) async {
    var saves = 0;
    await tester.pumpWidget(
      _wrap(
        GeometryEditorBanner(
          editCount: 0,
          undoEnabled: false,
          saveEnabled: false,
          onSave: () => saves++,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('reshape.banner.save')));
    expect(saves, 0);
  });
}
