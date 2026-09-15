import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/features/remote_activity/domain/remote_attribution_view.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Scrollable list of features that other enumerators have attributed,
/// fed by the phase-2 remote_attributions_cache. Empty-state shows a
/// friendly note; the cold-open + realtime pipeline keeps this in sync
/// without per-screen polling.
class RemoteActivityListScreen extends ConsumerWidget {
  const RemoteActivityListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attribsAsync = ref.watch(othersRemoteAttributionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edited by others')),
      body: attribsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (rows) {
          if (rows.isEmpty) {
            return const _Empty();
          }
          return ListView.separated(
            key: const Key('remote-activity.list'),
            padding: appPageInsets(context),
            itemCount: rows.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => i == 0
                ? AppPageIntro(
                    title: AppLocalizations.of(context)!.designActivityTitle,
                    subtitle: AppLocalizations.of(context)!.designActivityBody)
                : _RemoteAttributionTile(view: rows[i - 1]),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 56,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'No remote activity yet.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'When another enumerator attributes a feature in this '
              'assignment, it shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteAttributionTile extends StatelessWidget {
  const _RemoteAttributionTile({required this.view});
  final RemoteAttributionView view;

  @override
  Widget build(BuildContext context) {
    final relTime = _relativeTime(view.submittedAt);
    return ListTile(
      key: Key('remote-activity.tile.${view.featureId}'),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Icon(
          view.featureType == 'building'
              ? Icons.home_work_outlined
              : Icons.alt_route_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        '${_capitalize(view.featureType)} ${_shortId(view.featureId)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'by ${view.submittedBy ?? 'unknown'} • $relTime',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        '/remote-activity/${Uri.encodeComponent(view.featureId)}',
      ),
    );
  }

  String _shortId(String id) {
    if (id.length <= 8) return id;
    return id.substring(0, 8);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _relativeTime(DateTime t) {
    final delta = DateTime.now().difference(t);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
