import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/features/conflict_review/domain/local_attribution_flatten.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:firecheck/features/conflict_review/presentation/side_by_side_compare.dart';
import 'package:firecheck/features/remote_activity/domain/remote_attribution_flatten.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Side-by-side compare for a single existing-feature conflict. Three
/// actions:
///   - Keep theirs   (primary) — withdraws our row, the prior canonical wins
///   - Use mine               — supersedes their row via force_overwrite
///   - Skip — decide later    — leaves the row parked
class AttributionConflictScreen extends ConsumerStatefulWidget {
  const AttributionConflictScreen({required this.submissionId, super.key});
  final String submissionId;

  @override
  ConsumerState<AttributionConflictScreen> createState() =>
      _AttributionConflictScreenState();
}

class _AttributionConflictScreenState
    extends ConsumerState<AttributionConflictScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final mineAsync = ref.watch(
      localAttributionForSubmissionProvider(widget.submissionId),
    );
    final subsAsync = ref.watch(awaitingSubmissionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Conflict')),
      body: subsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (subs) {
          final sub = subs.where((s) => s.id == widget.submissionId).firstOrNull;
          if (sub == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This submission is no longer in conflict. '
                  'It may have been resolved on another device.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final theirsAsync = ref.watch(
            remoteAttributionForFeatureProvider(sub.featureId),
          );
          return mineAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (mine) => theirsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (theirsView) {
                if (theirsView == null) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24,),
                    children: [
                      const Text(
                        "Theirs is no longer available — the other "
                        'enumerator may have withdrawn it. Tap "Use mine" '
                        'to commit your version as-is.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('conflict-review.use-mine'),
                        onPressed: _busy
                            ? null
                            : () =>
                                _resolve(AttributionDecision.forceOverwrite),
                        child: const Text('Use mine'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('conflict-review.skip'),
                        onPressed: _busy ? null : () => context.pop(),
                        child: const Text('Skip — decide later'),
                      ),
                    ],
                  );
                }
                final theirs =
                    flattenRemoteAttributionForDisplay(theirsView);
                final differing = diffAttributionKeys(mine, theirs);
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    SideBySideCompare(
                      mine: mine,
                      theirs: theirs,
                      differingKeys: differing,
                      mineLabel: 'Yours',
                      theirsLabel: 'Theirs',
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton(
                            key: const Key('conflict-review.keep-theirs'),
                            onPressed: _busy
                                ? null
                                : () => _resolve(
                                    AttributionDecision.keepTheirs),
                            child: const Text('Keep theirs'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            key: const Key('conflict-review.use-mine'),
                            onPressed: _busy
                                ? null
                                : () => _resolve(
                                    AttributionDecision.forceOverwrite),
                            child: const Text('Use mine'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            key: const Key('conflict-review.skip'),
                            onPressed:
                                _busy ? null : () => context.pop(),
                            child: const Text('Skip — decide later'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _resolve(AttributionDecision decision) async {
    setState(() => _busy = true);
    final repo = ref.read(conflictReviewRepositoryProvider);
    try {
      await repo.queueAttributionDecision(
        submissionId: widget.submissionId,
        decision: decision,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == AttributionDecision.keepTheirs
                ? 'Keeping theirs. Will sync when online.'
                : 'Overwriting with yours. Will sync when online.',
          ),
        ),
      );
      context.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
