import 'package:firecheck/core/navigation/app_bottom_nav.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _buildApp({required AppTab current, required List<String> visited}) {
  final router = GoRouter(
    initialLocation: current == AppTab.home ? '/' : '/account',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) {
          visited.add('/');
          return const Scaffold(
            body: SizedBox(),
            bottomNavigationBar: AppBottomNav(current: AppTab.home),
          );
        },
      ),
      GoRoute(
        path: '/account',
        builder: (_, __) {
          visited.add('/account');
          return const Scaffold(
            body: SizedBox(),
            bottomNavigationBar: AppBottomNav(current: AppTab.account),
          );
        },
      ),
    ],
  );

  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

void main() {
  testWidgets('tapping Account on Home navigates to /account', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_buildApp(current: AppTab.home, visited: visited));
    await tester.pumpAndSettle();

    expect(visited, ['/']);

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(visited.last, '/account');
  });

  testWidgets('tapping Home on Account navigates to /', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(
      _buildApp(current: AppTab.account, visited: visited),
    );
    await tester.pumpAndSettle();

    expect(visited, ['/account']);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(visited.last, '/');
  });

  testWidgets('tapping the already-selected tab is a no-op', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_buildApp(current: AppTab.home, visited: visited));
    await tester.pumpAndSettle();

    expect(visited, ['/']);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(visited, ['/']);
  });
}
