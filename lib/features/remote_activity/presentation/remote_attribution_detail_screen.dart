import 'package:firecheck/features/remote_activity/domain/remote_attribution_flatten.dart';
import 'package:firecheck/features/remote_activity/presentation/attribute_kv_table.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Read-only view of another enumerator's attribution for a feature.
/// Phase 5 will reuse the underlying widgets in the side-by-side compare
/// during conflict review.
class RemoteAttributionDetailScreen extends ConsumerWidget {
  const RemoteAttributionDetailScreen({required this.featureId, super.key});
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewAsync =
        ref.watch(remoteAttributionForFeatureProvider(featureId));

    return Scaffold(
      appBar: AppBar(title: const Text('Their answers')),
      body: viewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (view) {
          if (view == null) {
            return const _NoData();
          }
          final values = flattenRemoteAttributionForDisplay(view);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              _Header(
                featureId: view.featureId,
                featureType: view.featureType,
                submittedBy: view.submittedBy,
                submittedAt: view.submittedAt,
              ),
              const SizedBox(height: 12),
              Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 0,
                child: AttributeKvTable(values: values),
              ),
              const SizedBox(height: 12),
              // Phase-5 hook: open form for local edit / "compare with mine".
              // For phase 4 we surface a "Open feature" CTA that drops the
              // user back into the standard feature form, where any local
              // submission can be inspected.
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ElevatedButton.icon(
                  key: const Key('remote-activity.open-feature'),
                  onPressed: () => context.push(
                    '/feature/${Uri.encodeComponent(view.featureId)}',
                  ),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Open feature'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.featureId,
    required this.featureType,
    required this.submittedBy,
    required this.submittedAt,
  });
  final String featureId;
  final String featureType;
  final String? submittedBy;
  final DateTime submittedAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: featureType == 'building'
                ? Colors.blueGrey.shade100
                : Colors.brown.shade100,
            child: Icon(
              featureType == 'building'
                  ? Icons.home_work_outlined
                  : Icons.alt_route_outlined,
              color: featureType == 'building'
                  ? Colors.blueGrey.shade700
                  : Colors.brown.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_capitalize(featureType)} ${_shortId(featureId)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'by ${submittedBy ?? 'unknown'} • ${_absTime(submittedAt)}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortId(String id) =>
      id.length <= 8 ? id : id.substring(0, 8);

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _absTime(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No remote attribution found for this feature.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
