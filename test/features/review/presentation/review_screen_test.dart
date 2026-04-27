import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// A no-op repository whose [getCurrentAssignment] returns null so every
/// provider that branches on the assignment short-circuits cleanly.
class _NoOpAssignmentRepository extends AssignmentRepository {
  _NoOpAssignmentRepository(SupabaseClient client, AppDatabase db)
      : super(client: client, db: db);

  @override
  Future<Assignment?> getCurrentAssignment() async => null;
}

/// Bare-minimum SupabaseClient stub. The fake repo overrides every method
/// that would touch the network, so the client is never actually invoked.
/// We only need an instance for the AssignmentRepository constructor.
// ignore: subtype_of_sealed_class
class _StubClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Network calls are not allowed in this test');
}

void main() {
  testWidgets('renders title even when there is no assignment', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          assignmentRepositoryProvider.overrideWith(
            (ref) => _NoOpAssignmentRepository(_StubClient(), db),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Review'), findsOneWidget);
  });
}
