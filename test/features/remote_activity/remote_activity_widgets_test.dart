import 'package:firecheck/features/remote_activity/domain/remote_attribution_view.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_chip.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_list_screen.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests override `othersRemoteAttributionsProvider` directly with
/// a synthetic stream — that way we don't pull in Drift / Supabase /
/// `currentAssignmentProvider` (which would require a real DB or extra
/// overrides). Provider behaviour is covered separately in
/// `remote_activity_providers_test.dart`.

RemoteAttributionView _view(
  String submissionId, {
  required String featureId,
  String submittedBy = 'alice',
}) {
  return RemoteAttributionView(
    id: submissionId,
    assignmentId: 'a1',
    featureId: featureId,
    featureType: 'building',
    attributeValues: {
      'building': {'storeys': 2},
    },
    submittedBy: submittedBy,
    submittedAt: DateTime.utc(2026, 5, 18, 10),
    supersededAt: null,
    updatedAt: DateTime.utc(2026, 5, 18, 10),
  );
}

Override _stub(List<RemoteAttributionView> views) {
  return othersRemoteAttributionsProvider.overrideWith(
    (ref) => Stream.value(views),
  );
}

void main() {
  testWidgets('chip is hidden when count is zero', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [_stub(const [])],
        child: const MaterialApp(
          home: Scaffold(body: RemoteActivityChip()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('remote-activity.chip')), findsNothing);
  });

  testWidgets('chip shows "1 feature edited by others" with one row',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [_stub([_view('s1', featureId: 'f1')])],
        child: const MaterialApp(
          home: Scaffold(body: RemoteActivityChip()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('remote-activity.chip')), findsOneWidget);
    expect(find.textContaining('1 feature edited by others'), findsOneWidget);
  });

  testWidgets('chip counts distinct features, not submissions',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _stub([
            _view('s1', featureId: 'f1'),
            _view('s2', featureId: 'f1', submittedBy: 'bob'),
            _view('s3', featureId: 'f2'),
          ]),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RemoteActivityChip()),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('2 features edited by others'), findsOneWidget);
  });

  testWidgets('list screen shows empty state when no rows', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [_stub(const [])],
        child: const MaterialApp(home: RemoteActivityListScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('No remote activity yet.'), findsOneWidget);
  });

  testWidgets('list screen renders one tile per remote attribution',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _stub([
            _view('s1', featureId: 'f1'),
            _view('s2', featureId: 'f2'),
          ]),
        ],
        child: const MaterialApp(home: RemoteActivityListScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('remote-activity.tile.f1')), findsOneWidget);
    expect(find.byKey(const Key('remote-activity.tile.f2')), findsOneWidget);
  });
}
