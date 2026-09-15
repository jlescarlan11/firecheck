import 'package:firecheck/features/account/presentation/account_screen.dart';
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

class _ThrowingRepo implements GoogleAuthRepository {
  @override
  Future<bool> isSignedIn() async => true;
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async => throw Exception('boom');
  @override
  Future<String> getEnumeratorId() async => 'enum-1';
  @override
  Future<bool> requestDriveUploadScope() async => true;
  @override
  Future<String> getAccessToken() async => 'tok';
}

Session _sessionWith({String? fullName, String? email, String? avatarUrl}) {
  final user = _MockUser();
  when(() => user.email).thenReturn(email);
  when(() => user.userMetadata).thenReturn({
    if (fullName != null) 'full_name': fullName,
    if (email != null) 'email': email,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  });
  final session = _MockSession();
  when(() => session.user).thenReturn(user);
  return session;
}

Widget _wrap({
  required Session? session,
  GoogleAuthRepository? repo,
}) {
  return ProviderScope(
    overrides: [
      supabaseAuthStateProvider.overrideWith((_) async* {
        yield session;
      }),
      googleAuthRepositoryProvider
          .overrideWithValue(repo ?? FakeGoogleAuthRepository()),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AccountScreen(),
    ),
  );
}

void main() {
  testWidgets('renders name, email, and avatar from session metadata',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        session: _sessionWith(
          fullName: 'Juan dela Cruz',
          email: 'juan@example.com',
          avatarUrl: 'https://example.com/a.png',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Juan dela Cruz'), findsOneWidget);
    expect(find.text('juan@example.com'), findsOneWidget);

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<NetworkImage>());
    expect(
      (avatar.backgroundImage! as NetworkImage).url,
      'https://example.com/a.png',
    );

    // Drain pending image load; flutter_test returns 400 for all HTTP, which
    // surfaces as a NetworkImageLoadException — consume it.
    await tester.pumpAndSettle();
    tester.takeException();
  });

  testWidgets('falls back to email local-part when full_name is missing',
      (tester) async {
    await tester.pumpWidget(
      _wrap(session: _sessionWith(email: 'juan@example.com')),
    );
    await tester.pumpAndSettle();

    expect(find.text('juan'), findsOneWidget);
    expect(find.text('juan@example.com'), findsOneWidget);
  });

  testWidgets('shows person icon when avatar_url is missing', (tester) async {
    await tester.pumpWidget(
      _wrap(session: _sessionWith(email: 'a@b.co')),
    );
    await tester.pumpAndSettle();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
    expect(find.byIcon(Icons.person), findsWidgets);
  });

  testWidgets('tapping Sign out opens confirm dialog', (tester) async {
    await tester.pumpWidget(_wrap(session: _sessionWith(email: 'a@b.co')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    expect(
      find.text("You'll need to sign in again to continue."),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('Cancel in dialog does not call signOut', (tester) async {
    final repo = FakeGoogleAuthRepository();
    await tester.pumpWidget(
      _wrap(session: _sessionWith(email: 'a@b.co'), repo: repo),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsNothing);
    expect(await repo.isSignedIn(), isTrue);
  });

  testWidgets('confirming dialog calls signOut on the repo', (tester) async {
    final repo = FakeGoogleAuthRepository();
    await tester.pumpWidget(
      _wrap(session: _sessionWith(email: 'a@b.co'), repo: repo),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    // The confirm button is the second 'Sign out' text in the tree
    // (first is the ListTile, second is the dialog action).
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();

    expect(await repo.isSignedIn(), isFalse);
  });

  testWidgets('shows snackbar when signOut throws', (tester) async {
    await tester.pumpWidget(
      _wrap(session: _sessionWith(email: 'a@b.co'), repo: _ThrowingRepo()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't sign out. Try again."), findsOneWidget);
  });

  testWidgets('renders empty body when session is null', (tester) async {
    await tester.pumpWidget(_wrap(session: null));
    await tester.pumpAndSettle();

    // AppBar title still renders; "Account" also appears in the bottom nav.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('FireCheck')),
      findsOneWidget,
    );
    expect(find.text('Sign out'), findsNothing);
  });
}
