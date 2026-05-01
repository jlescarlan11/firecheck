// test/core/router/app_router_google_auth_test.dart
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/core/router/app_router.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _makeContainer(FakeGoogleAuthRepository repo) {
  return ProviderContainer(
    overrides: [
      googleAuthRepositoryProvider.overrideWithValue(repo),
      authStateProvider.overrideWith(
        (ref) => _StaticAuthNotifier(
          const Authenticated(userId: 'u1', email: 'test@test.com'),
        ),
      ),
      assignmentLockStateProvider
          .overrideWith((ref) => Stream.value(const Unlocked())),
      // HomeScreen watches progressProvider — override so it doesn't need real DB
      progressProvider.overrideWith(
        (ref) => Stream.value(ProgressSnapshot.empty),
      ),
      // GetMapsScreen watches getMapsNotifierProvider — override so it doesn't
      // need real Drive / DB dependencies
      getMapsNotifierProvider.overrideWith(
        (ref) => _StaticGetMapsNotifier(const Idle()),
      ),
    ],
  );
}

Widget _app(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final router = ref.watch(appRouterProvider);
        return MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        );
      },
    ),
  );
}

class _StaticAuthNotifier extends StateNotifier<AuthState>
    implements AuthStateNotifier {
  _StaticAuthNotifier(super.state);

  @override
  Future<void> login(String email, String password) async {}

  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticGetMapsNotifier extends StateNotifier<GetMapsState>
    implements GetMapsNotifier {
  _StaticGetMapsNotifier(super.state);

  @override
  Future<void> start() async {}

  @override
  Future<void> cancel() async {}

  @override
  void reset() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('navigating /get-maps while signed-out redirects to /sign-in',
      (tester) async {
    final repo = FakeGoogleAuthRepository(startSignedIn: false);
    final container = _makeContainer(repo);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go('/get-maps');
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('/sign-in while signed-in redirects to /get-maps', (tester) async {
    final repo = FakeGoogleAuthRepository(startSignedIn: true);
    final container = _makeContainer(repo);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go('/sign-in');
    await tester.pumpAndSettle();

    expect(find.byType(GetMapsScreen), findsOneWidget);
  });
}
