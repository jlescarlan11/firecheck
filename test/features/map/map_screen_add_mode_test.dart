import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject() {
    return ProviderScope(
      overrides: [
        mapRendererProvider.overrideWithValue(FakeMapRenderer()),
        currentFeaturesProvider.overrideWith((ref) => Stream.value(const [])),
        currentAssignmentProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MapScreen(),
      ),
    );
  }

  testWidgets('+ New Feature pill toggles add-mode visual state',
      (tester) async {
    await tester.pumpWidget(subject());
    await tester.pump();

    const banner =
        'Long-press the map to add a building or road. Tap the pill again to cancel.';

    expect(find.text(banner), findsNothing);
    expect(find.text('add-mode'), findsNothing);

    await tester.tap(find.byKey(const Key('map.add-feature-pill')));
    await tester.pump();

    expect(find.text(banner), findsOneWidget);
    expect(find.text('add-mode'), findsOneWidget);

    await tester.tap(find.byKey(const Key('map.add-feature-pill')));
    await tester.pump();

    expect(find.text(banner), findsNothing);
    expect(find.text('add-mode'), findsNothing);
  });
}
