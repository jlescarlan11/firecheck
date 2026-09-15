// test/features/assignment/get_maps_screen_us17_test.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(GetMapsState initialState) {
  return ProviderScope(
    overrides: [
      getMapsNotifierProvider.overrideWith((_) => _FakeNotifier(initialState)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GetMapsScreen(),
    ),
  );
}

class _FakeNotifier extends StateNotifier<GetMapsState>
    implements GetMapsNotifier {
  _FakeNotifier(super.state);
  String? lastSelectId;
  bool confirmCalled = false;
  int resetCalls = 0;

  @override
  void selectAssignment(String id) => lastSelectId = id;
  @override
  Future<void> confirmDownload() async => confirmCalled = true;
  @override
  Future<void> start() async {}
  @override
  Future<void> cancel() async {}
  @override
  void reset() => resetCalls++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _brgy = DriveAssignment(
  assignmentId: 'brgy-001',
  localAssignmentId: 'brgy-001',
  inputZipModifiedTime: '2026-04-28T10:00:00Z',
  driveFolderId: 'fd',
);

void main() {
  testWidgets('import options are absent and start is immediately available',
      (tester) async {
    await tester.pumpWidget(_wrap(const Idle()));
    expect(find.text('Import options'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
  for (final entry in [
    (500, 1000, '50%'),
    (1200, 1000, '100%'),
    (-10, 1000, '0%'),
    (0, 0, 'Calculating progress…')
  ]) {
    testWidgets('download progress displays ${entry.$3}', (tester) async {
      await tester.pumpWidget(
          _wrap(DownloadingShapefiles(downloaded: entry.$1, total: entry.$2)));
      await tester.pump();
      expect(find.text(entry.$3), findsOneWidget);
      expect(find.textContaining('MB'), findsNothing);
    });
  }

  testWidgets('DiscoveringAssignments → spinner shown', (tester) async {
    await tester.pumpWidget(_wrap(const DiscoveringAssignments()));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PickingAssignment → assignment name shown', (tester) async {
    final state =
        PickingAssignment(assignments: [_brgy], selectedId: 'brgy-001');
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    expect(find.text('brgy-001'), findsOneWidget);
  });

  testWidgets('PickingAssignment → Download Selected button enabled',
      (tester) async {
    final state =
        PickingAssignment(assignments: [_brgy], selectedId: 'brgy-001');
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('InsufficientStorage offers a retry after freeing storage',
      (tester) async {
    final state = InsufficientStorage(requiredBytes: 100, availableBytes: 10);
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GetMapsScreen)),
    );
    final notifier =
        container.read(getMapsNotifierProvider.notifier) as _FakeNotifier;
    final before = notifier.resetCalls;
    await tester.tap(find.text('Try again'));
    expect(notifier.resetCalls, before + 1);
  });

  testWidgets('DownloadingShapefiles → progress bar and cancel shown',
      (tester) async {
    final state = DownloadingShapefiles(downloaded: 500, total: 1000);
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('ImportingShapefiles → indeterminate progress shown',
      (tester) async {
    await tester.pumpWidget(_wrap(const ImportingShapefiles()));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
