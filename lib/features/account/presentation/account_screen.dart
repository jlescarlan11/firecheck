import 'package:firecheck/core/navigation/app_bottom_nav.dart';
import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final authState = ref.watch(supabaseAuthStateProvider);
    final session = authState.valueOrNull;
    final meta = session?.user.userMetadata ?? const <String, dynamic>{};
    final email = (meta['email'] as String?) ?? session?.user.email;
    final fullName = meta['full_name'] as String?;
    final avatarUrl = meta['avatar_url'] as String?;
    final displayName = (fullName != null && fullName.trim().isNotEmpty)
        ? fullName
        : (email != null && email.contains('@')
            ? email.split('@').first
            : (email ?? ''));

    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: session == null
          ? Center(
              child: authState.isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          authState.hasError
                              ? l.accountLoadError
                              : l.signInWithGoogle,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            if (authState.hasError) {
                              ref.invalidate(supabaseAuthStateProvider);
                            } else {
                              context.go('/sign-in');
                            }
                          },
                          child: Text(
                            authState.hasError
                                ? l.retryAction
                                : l.signInWithGoogle,
                          ),
                        ),
                      ],
                    ),
            )
          : ListView(
              padding: appPageInsets(context),
              children: [
                AppPageIntro(
                  title: l.accountTitle,
                  subtitle: l.designAccountBody,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      backgroundImage:
                          (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? NetworkImage(avatarUrl)
                              : null,
                      onBackgroundImageError:
                          (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? (_, __) {}
                              : null,
                      child: (avatarUrl == null || avatarUrl.isEmpty)
                          ? Icon(
                              Icons.person_outline,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (email != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              email,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text(l.uploadsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/uploads'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.rule_outlined),
                  title: Text(l.formRulesTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/form-preview'),
                ),
                const Divider(),
                const SizedBox(height: 20),
                ListTile(
                  leading: Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    l.accountSignOut,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () => _confirmSignOut(context, ref),
                ),
              ],
            ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.account),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final errorText = l.accountSignOutError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.accountSignOutConfirmTitle),
        content: Text(l.accountSignOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.accountSignOutCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.accountSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(googleAuthRepositoryProvider).signOut();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(errorText)));
    }
  }
}
