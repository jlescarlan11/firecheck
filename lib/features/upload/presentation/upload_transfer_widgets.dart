import 'package:firecheck/core/drive/upload_transfer_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UploadTransferBar extends StatelessWidget {
  const UploadTransferBar({required this.progress, super.key});
  final UploadTransferProgress progress;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        // Smooth actual byte-count updates; never invent timed progress while
        // the network is stalled or advance beyond the acknowledged target.
        key: ValueKey(progress.job.id),
        tween: Tween<double>(begin: 0, end: progress.percent.toDouble()),
        duration: const Duration(milliseconds: 350),
        builder: (context, value, _) {
          final displayed = value.floor();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(progress.labelAt(displayed)),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: value / 100,
                semanticsLabel: progress.job.fileName,
                semanticsValue: '$displayed',
              ),
            ],
          );
        },
      );
}

/// The same per-file percentages appear here and in the upload queue.
class AssignmentTransferProgress extends ConsumerWidget {
  const AssignmentTransferProgress({required this.assignmentId, super.key});
  final String assignmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref
        .watch(uploadTransferProgressProvider)
        .values
        .where((p) => p.job.assignmentId == assignmentId)
        .toList();
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.job.fileName,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                UploadTransferBar(progress: item),
              ],
            ),
          ),
      ],
    );
  }
}
