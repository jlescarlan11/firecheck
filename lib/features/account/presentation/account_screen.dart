import 'package:firecheck/core/navigation/app_bottom_nav.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final session = ref.watch(supabaseAuthStateProvider).valueOrNull;
    final meta = session?.user.userMetadata ?? const <String, dynamic>{};
    final email =
        (meta['email'] as String?) ?? session?.user.email;
    final fullName = meta['full_name'] as String?;
    final avatarUrl = meta['avatar_url'] as String?;
    final displayName = (fullName != null && fullName.trim().isNotEmpty)
        ? fullName
        : (email != null && email.contains('@')
            ? email.split('@').first
            : (email ?? ''));

    return Scaffold(
      appBar: AppBar(title: Text(l.accountTitle)),
      body: session == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        (avatarUrl != null && avatarUrl.isNotEmpty)
                            ? NetworkImage(avatarUrl)
                            : null,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
                        ? Icon(
                            Icons.person,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (email != null) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      email,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(l.accountSignOut),
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
    if (confirmed != true) return;

    try {
      await ref.read(googleAuthRepositoryProvider).signOut();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(errorText)));
    }
  }
}
