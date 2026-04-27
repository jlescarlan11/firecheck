import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class FailedJobsSection extends StatelessWidget {
  const FailedJobsSection({
    required this.deadJobs,
    required this.onRetryAll,
    required this.onRetryOne,
    super.key,
  });

  final List<DeadJobRow> deadJobs;
  final VoidCallback onRetryAll;
  final void Function(String jobId) onRetryOne;

  @override
  Widget build(BuildContext context) {
    if (deadJobs.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return Card(
      color: const Color(0xFFFFF5F5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.failedJobsTitle(deadJobs.length),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFC53030),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onRetryAll,
                  child: Text(l.retryAllButton),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...deadJobs.map(
              (j) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${j.entityType} · ${j.entityId.length > 6 ? j.entityId.substring(0, 6) : j.entityId}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            j.lastError,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: Key('failedJobs.retry-${j.jobId}'),
                      icon: const Icon(Icons.refresh, color: Color(0xFFC53030)),
                      onPressed: () => onRetryOne(j.jobId),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
