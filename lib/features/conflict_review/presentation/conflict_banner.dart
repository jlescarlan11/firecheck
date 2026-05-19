import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Slim banner placed on the home screen: "N conflicts to resolve →".
/// Hidden when count is zero. Tapping routes to the review list.
class ConflictBanner extends ConsumerWidget {
  const ConflictBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(awaitingResolutionCountProvider);
    if (count == 0) return const SizedBox.shrink();

    return Material(
      key: const Key('conflict-banner'),
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/resolve'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 conflict to resolve'
                      : '$count conflicts to resolve',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.orange.shade800),
            ],
          ),
        ),
      ),
    );
  }
}
