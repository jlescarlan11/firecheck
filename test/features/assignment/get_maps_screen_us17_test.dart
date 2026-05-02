// test/features/assignment/get_maps_screen_us17_test.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/errors/failure.dart';
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

  @override
  void selectAssignment(String id) => lastSelectId = id;
  @override
  Future<void> confirmDownload() async => confirmCalled = true;
  @override
  Future<void> start() async {}
  @override
  Future<void> cancel() async {}
  @override
  void reset() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _brgy = DriveAssignment(
  assignmentId: 'brgy-001',
  inputZipModifiedTime: '2026-04-28T10:00:00Z',
  driveFolderId: 'fd',
);

void main() {
  testWidgets('DiscoveringAssignments → spinner shown', (tester) async {
    await tester.pumpWidget(_wrap(const DiscoveringAssignments()));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PickingAssignment → assignment name shown', (tester) async {
    final state = PickingAssignment(assignments: [_brgy], selectedId: 'brgy-001');
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

  testWidgets('InsufficientStorage → Download Selected button disabled',
      (tester) async {
    final state = InsufficientStorage(requiredBytes: 100, availableBytes: 10);
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
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
