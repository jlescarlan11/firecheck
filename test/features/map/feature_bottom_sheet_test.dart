import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/presentation/feature_bottom_sheet.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders feature metadata + distance + phase 2 note',
      (tester) async {
    final feature = Feature(
      id: 'f3e4aaaaaaaa000000000000000000a7b2',
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson: '{}',
      isNew: false,
      status: 'unfilled',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      wrap(
        FeatureBottomSheet(
          feature: feature,
          distanceMeters: 23.4,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Building'), findsWidgets);
    expect(find.textContaining('23 m'), findsOneWidget);
    expect(find.textContaining('Form coming in Phase 2'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
