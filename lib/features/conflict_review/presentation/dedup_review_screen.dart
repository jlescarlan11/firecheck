import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/conflict_review/domain/dedup_comparison.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:firecheck/features/conflict_review/presentation/dedup_comparison_view.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Review screen for a new-feature dedup decision. Three actions:
///   - Keep both       — both rows coexist as separate features
///   - Replace theirs  — supersede the older feature with this one
///   - Discard mine    — soft-delete this new feature
///
class DedupReviewScreen extends ConsumerStatefulWidget {
  const DedupReviewScreen({required this.featureId, super.key});
  final String featureId;

  @override
  ConsumerState<DedupReviewScreen> createState() => _DedupReviewScreenState();
}

class _DedupReviewScreenState extends ConsumerState<DedupReviewScreen> {
  bool _busy = false;
  DedupComparison? _comparison;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dedupComparisonProvider(widget.featureId));
    final selected = ref.watch(currentAssignmentProvider).asData?.value;
    final account = ref.watch(currentUserIdProvider);
    final loaded = state.asData?.value;
    _comparison =
        loaded?.assignmentId == selected?.id && loaded?.accountId == account
            ? loaded
            : null;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: const Text('Possible duplicate')),
      body: ListView(
        padding: appPageInsets(context),
        children: [
          const AppPageIntro(
            title: 'Review this feature',
            subtitle:
                'A nearby feature of the same type was already added by another enumerator. Pick how to resolve.',
          ),
          const SizedBox(height: 8),
          Text(
            'Feature ${_short(widget.featureId)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_comparison != null)
            DedupComparisonView(comparison: _comparison!)
          else ...[
            Text(
              l10n.dedupUnavailable,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(l10n.dedupUnavailableDetail),
            TextButton(
              onPressed: () =>
                  ref.invalidate(dedupComparisonProvider(widget.featureId)),
              child: Text(l10n.dedupRetry),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('dedup-review.keep-both'),
            onPressed: _decisionCallback(DedupDecision.keepBoth),
            child: const Text('Keep both'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('dedup-review.replace-theirs'),
            onPressed: _decisionCallback(DedupDecision.replaceTheirs),
            child: const Text('Replace theirs'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('dedup-review.discard-mine'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
            ),
            onPressed: _decisionCallback(DedupDecision.discardMine),
            child: const Text('Discard mine'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('dedup-review.skip'),
            onPressed: _busy ? null : () => context.pop(),
            child: const Text('Skip — decide later'),
          ),
        ],
      ),
    );
  }

  VoidCallback? _decisionCallback(DedupDecision decision) =>
      _busy || _comparison == null ? null : () => _resolve(decision);

  Future<void> _resolve(DedupDecision decision) async {
    if (_busy) return;
    final comparison = _comparison;
    if (comparison == null) return;
    setState(() => _busy = true);
    final repo = ref.read(conflictReviewRepositoryProvider);
    try {
      // Revalidate after async provider updates; never queue a decision for a
      // comparison whose account, selected map, or counterpart has changed.
      if (ref.read(currentUserIdProvider) != comparison.accountId ||
          ref.read(currentAssignmentProvider).valueOrNull?.id !=
              comparison.assignmentId) {
        return;
      }
      await ref.read(dedupComparisonRepositoryProvider).queueDecision(
            comparison: comparison,
            decision: decision,
            resolutions: repo,
            isCurrentContext: () =>
                mounted &&
                ref.read(currentUserIdProvider) == comparison.accountId &&
                ref.read(currentAssignmentProvider).asData?.value?.id ==
                    comparison.assignmentId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued: ${decision.wire}')),
      );
      context.pop();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.dedupQueueFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _short(String s) => s.length <= 8 ? s : s.substring(0, 8);
}
