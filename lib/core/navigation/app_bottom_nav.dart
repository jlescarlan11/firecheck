import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum AppTab { home, account }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({required this.current, super.key});

  final AppTab current;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return NavigationBar(
      selectedIndex: current.index,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: l.navHome,
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          selectedIcon: const Icon(Icons.person),
          label: l.navAccount,
        ),
      ],
      onDestinationSelected: (index) {
        final tapped = AppTab.values[index];
        if (tapped == current) return;
        switch (tapped) {
          case AppTab.home:
            context.go('/');
          case AppTab.account:
            context.go('/account');
        }
      },
    );
  }
}
