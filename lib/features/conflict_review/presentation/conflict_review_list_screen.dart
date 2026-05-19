import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Single list of items requiring user decisions: existing-feature value
/// conflicts on top, new-feature dedup reviews below.
class ConflictReviewListScreen extends ConsumerWidget {
  const ConflictReviewListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(awaitingSubmissionsProvider);
    final dedupAsync = ref.watch(pendingDedupProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Resolve conflicts')),
      body: subsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (subs) => dedupAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (dedup) {
            if (subs.isEmpty && dedup.isEmpty) {
              return const _Empty();
            }
            return ListView(
              key: const Key('conflict-review.list'),
              children: [
                if (subs.isNotEmpty)
                  const _SectionHeader('Attribution conflicts'),
                for (final s in subs) _SubmissionTile(submission: s),
                if (dedup.isNotEmpty)
                  const _SectionHeader('New-feature dedup'),
                for (final f in dedup) _DedupTile(feature: f),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: Colors.green.shade400),
            const SizedBox(height: 12),
            const Text('Nothing to resolve.',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              "You're caught up. Conflicts and dedup decisions will appear "
              'here when the server flags them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission});
  final Submission submission;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('conflict-review.submission.${submission.id}'),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFFE0B2),
        child: Icon(Icons.warning_amber_rounded, color: Color(0xFFB85A00)),
      ),
      title: Text('Submission ${_short(submission.id)}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        'Feature ${_short(submission.featureId)} • conflict with '
        '${_short(submission.pendingTheirsId ?? '?')}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        '/resolve/attribution/${Uri.encodeComponent(submission.id)}',
      ),
    );
  }
}

class _DedupTile extends StatelessWidget {
  const _DedupTile({required this.feature});
  final Feature feature;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('conflict-review.dedup.${feature.id}'),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFFCDD2),
        child: Icon(Icons.merge_type, color: Color(0xFFB71C1C)),
      ),
      title: Text(
        '${_capitalize(feature.featureType)} ${_short(feature.id)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Possible duplicate of ${_short(feature.pendingDedupOf ?? '?')}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        '/resolve/dedup/${Uri.encodeComponent(feature.id)}',
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _short(String s) => s.length <= 8 ? s : s.substring(0, 8);
