// test/features/auth/sign_in_screen_test.dart
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _wrap(Widget w, {FakeGoogleAuthRepository? repo}) {
  final r = repo ?? FakeGoogleAuthRepository(startSignedIn: false);
  final router = GoRouter(
    initialLocation: '/sign-in',
    routes: [
      GoRoute(path: '/sign-in', builder: (_, __) => w),
      GoRoute(path: '/get-maps', builder: (_, __) => const SizedBox()),
    ],
  );
  return ProviderScope(
    overrides: [
      googleAuthRepositoryProvider.overrideWithValue(r),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  testWidgets('renders Sign in with Google button', (tester) async {
    await tester.pumpWidget(_wrap(const SignInScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('tapping button calls signIn', (tester) async {
    final repo = FakeGoogleAuthRepository(startSignedIn: false);
    await tester.pumpWidget(_wrap(const SignInScreen(), repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(await repo.isSignedIn(), isTrue);
  });
}
