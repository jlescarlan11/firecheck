import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Review screen for a new-feature dedup decision. Three actions:
///   - Keep both       — both rows coexist as separate features
///   - Replace theirs  — supersede the older feature with this one
///   - Discard mine    — soft-delete this new feature
///
/// A mini-map header showing both geometries is intentionally deferred —
/// the spec calls for it but it requires Mapbox plumbing best done in a
/// later visual-polish pass. The decision-making is functional as-is.
class DedupReviewScreen extends ConsumerStatefulWidget {
  const DedupReviewScreen({required this.featureId, super.key});
  final String featureId;

  @override
  ConsumerState<DedupReviewScreen> createState() => _DedupReviewScreenState();
}

class _DedupReviewScreenState extends ConsumerState<DedupReviewScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Possible duplicate')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A nearby feature of the same type was already added by '
            'another enumerator. Pick how to resolve.',
          ),
          const SizedBox(height: 8),
          Text(
            'Feature ${_short(widget.featureId)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('dedup-review.keep-both'),
            onPressed: _busy
                ? null
                : () => _resolve(DedupDecision.keepBoth),
            child: const Text('Keep both'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('dedup-review.replace-theirs'),
            onPressed: _busy
                ? null
                : () => _resolve(DedupDecision.replaceTheirs),
            child: const Text('Replace theirs'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('dedup-review.discard-mine'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
            ),
            onPressed: _busy
                ? null
                : () => _resolve(DedupDecision.discardMine),
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

  Future<void> _resolve(DedupDecision decision) async {
    setState(() => _busy = true);
    final repo = ref.read(conflictReviewRepositoryProvider);
    try {
      await repo.queueDedupDecision(
        featureId: widget.featureId,
        decision: decision,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued: ${decision.wire}')),
      );
      context.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _short(String s) => s.length <= 8 ? s : s.substring(0, 8);
}
