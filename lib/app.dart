import 'package:firecheck/core/photos/photo_recovery_bootstrap.dart';
import 'package:firecheck/core/router/app_router.dart';
import 'package:firecheck/core/theme/app_theme.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FireCheckApp extends ConsumerWidget {
  const FireCheckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'FireCheck',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) => PhotoRecoveryBootstrap(
        child: child ?? const SizedBox.shrink(),
      ),
      theme: buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
