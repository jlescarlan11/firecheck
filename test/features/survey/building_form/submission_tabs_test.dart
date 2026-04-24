import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Submission s(String id) => Submission(
        id: id,
        featureId: 'f1',
        doesNotExist: false,
        syncStatus: 'draft',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  testWidgets('renders one tab per submission', (tester) async {
    var tappedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmissionTabs(
            submissions: [s('a'), s('b')],
            activeIndex: 0,
            onTap: (i) => tappedIndex = i,
            onAdd: () {},
            canAddMore: true,
            softCapTooltip: '',
          ),
        ),
      ),
    );
    expect(find.text('Structure 1'), findsOneWidget);
    expect(find.text('Structure 2'), findsOneWidget);
    await tester.tap(find.text('Structure 2'));
    expect(tappedIndex, 1);
  });

  testWidgets('+ tab disabled when canAddMore is false', (tester) async {
    var added = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmissionTabs(
            submissions: [s('a'), s('b'), s('c'), s('d'), s('e')],
            activeIndex: 0,
            onTap: (_) {},
            onAdd: () => added = true,
            canAddMore: false,
            softCapTooltip: 'cap',
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('submission-tabs.add')),
      warnIfMissed: false,
    );
    expect(added, isFalse);
  });
}
