import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({
    required List<Feature> features,
    Assignment? assignment,
  }) {
    return ProviderScope(
      overrides: [
        mapRendererProvider.overrideWithValue(FakeMapRenderer()),
        currentFeaturesProvider.overrideWith((ref) => Stream.value(features)),
        currentAssignmentProvider
            .overrideWith((ref) => Stream.value(assignment)),
        assignmentLockStateProvider
            .overrideWith((_) => Stream.value(const Unlocked())),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MapScreen(),
      ),
    );
  }

  testWidgets('renders title + follow-me toggle', (tester) async {
    await tester.pumpWidget(buildSubject(features: const []));
    await tester.pump();
    expect(find.text('Gather Data'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
  });

  testWidgets('renders one fake-map tile per feature', (tester) async {
    final f = Feature(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson: '{}',
      isNew: false,
      status: 'unfilled',
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(buildSubject(features: [f]));
    await tester.pump();
    expect(find.byKey(const Key('fake-map-feature-f1')), findsOneWidget);
  });
}
