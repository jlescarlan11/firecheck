import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/auth_repository.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repo;

  setUp(() {
    repo = _MockAuthRepository();
    when(() => repo.restoreSession())
        .thenAnswer((_) async => const Unauthenticated());
  });

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: LoginScreen()),
    );
  }

  testWidgets('renders email + password fields and Sign in button',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byKey(const Key('login.email')), findsOneWidget);
    expect(find.byKey(const Key('login.password')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('submitting valid credentials calls repo.login', (tester) async {
    when(() => repo.login(any(), any())).thenAnswer(
      (_) async => const Authenticated(userId: 'u1', email: 'a@b.co'),
    );

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('login.email')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('login.password')), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    verify(() => repo.login('a@b.co', 'pw')).called(1);
  });

  testWidgets('shows snackbar on AuthFailure', (tester) async {
    when(() => repo.login(any(), any()))
        .thenThrow(const AuthFailure('Invalid credentials'));

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('login.email')), 'x');
    await tester.enterText(find.byKey(const Key('login.password')), 'y');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Invalid credentials'), findsOneWidget);
  });
}
