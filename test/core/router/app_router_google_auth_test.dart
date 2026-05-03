// test/core/router/app_router_google_auth_test.dart
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/router/app_router.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSession extends Mock implements Session {}
class _MockUser extends Mock implements User {}

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

ProviderContainer _makeContainer({required bool signedIn}) {
  Session? session;
  if (signedIn) {
    final user = _MockUser();
    when(() => user.id).thenReturn('u1');
    session = _MockSession();
    when(() => session!.user).thenReturn(user);
  }

  return ProviderContainer(
    overrides: [
      googleAuthRepositoryProvider.overrideWithValue(
        FakeGoogleAuthRepository(startSignedIn: signedIn),
      ),
      supabaseAuthStateProvider.overrideWith(
        (ref) => Stream.value(session),
      ),
      assignmentLockStateProvider
          .overrideWith((ref) => Stream.value(const Unlocked())),
      progressProvider.overrideWith(
        (ref) => Stream.value(ProgressSnapshot.empty),
      ),
      getMapsNotifierProvider.overrideWith(
        (ref) => _StaticGetMapsNotifier(const Idle()),
      ),
      driveUploadNotifierProvider.overrideWith(
        (ref) => DriveUploadNotifier.seeded(const DriveUploadState(jobs: [])),
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

void main() {
  testWidgets('navigating /get-maps while signed-out redirects to /sign-in',
      (tester) async {
    final container = _makeContainer(signedIn: false);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go('/get-maps');
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('/sign-in while signed-in redirects to /', (tester) async {
    final container = _makeContainer(signedIn: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go('/sign-in');
    await tester.pumpAndSettle();

    expect(find.byType(GetMapsScreen), findsNothing);
    expect(find.byType(SignInScreen), findsNothing);
  });
}
