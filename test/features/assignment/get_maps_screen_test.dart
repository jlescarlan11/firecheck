import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject(GetMapsState state) {
    return ProviderScope(
      overrides: [
        getMapsNotifierProvider.overrideWith(
          (ref) => _StaticNotifier(state),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GetMapsScreen(),
      ),
    );
  }

  testWidgets('Idle state shows Start download button', (tester) async {
    await tester.pumpWidget(buildSubject(const Idle()));
    await tester.pump();
    expect(find.text('Start download'), findsOneWidget);
  });

  testWidgets('DownloadingTiles shows progress + Cancel', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        const DownloadingTiles(
          downloadedBytes: 5000000,
          totalBytes: 10000000,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Downloading map tiles…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Ready state shows Open map + Back to home', (tester) async {
    await tester.pumpWidget(
      buildSubject(const Ready(featureCount: 10, totalBytes: 1000)),
    );
    await tester.pump();
    expect(find.text('Ready to gather data'), findsOneWidget);
    expect(find.text('Open map'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
  });

  testWidgets('GetMapsError shows retry affordance', (tester) async {
    await tester.pumpWidget(
      buildSubject(const GetMapsError(NetworkFailure('no net'))),
    );
    await tester.pump();
    expect(find.textContaining('failed'), findsWidgets);
    expect(find.text('Try again'), findsOneWidget);
  });
}

class _StaticNotifier extends StateNotifier<GetMapsState>
    implements GetMapsNotifier {
  _StaticNotifier(super.state);

  @override
  Future<void> start() async {}
  @override
  Future<void> cancel() async {}
  @override
  void reset() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
