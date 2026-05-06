import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class UploadProgressSection extends StatelessWidget {
  const UploadProgressSection({
    required this.progress,
    this.onReset,
    super.key,
  });
  final UploadProgress progress;

  /// Called when the user taps Cancel (InProgress) or Retry (Completed with
  /// failures). Resets the controller to Idle so the normal review screen
  /// is shown and the user can act on failed jobs.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return switch (progress) {
      Idle() => const SizedBox.shrink(),
      Locked() => const SizedBox.shrink(),
      InProgress(:final done, :final total) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.uploadProgressLabel(done, total)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: total == 0 ? null : done / total),
                if (onReset != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onReset,
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      Completed(:final failedCount) => Card(
          color: failedCount == 0
              ? const Color(0xFFE6FFFA)
              : const Color(0xFFFFF5F5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failedCount == 0
                      ? l.uploadCompleteSuccess(0)
                      : l.uploadCompleteWithFailures(failedCount),
                ),
                if (failedCount > 0 && onReset != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onReset,
                      child: const Text('View & Retry Failed'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    };
  }
}
