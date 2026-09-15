import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class DriveUploadConfirmationCard extends StatelessWidget {
  const DriveUploadConfirmationCard({
    required this.state,
    this.onRetry,
    super.key,
  });

  final DriveUploadState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      DriveUploadIdle() || DriveUploadInProgress() => const SizedBox.shrink(),
      DriveUploadSuccess(
        :final folderPath,
        :final folderUrl,
        :final referenceId,
        :final confirmedAt,
      ) =>
        _SuccessCard(
          folderPath: folderPath,
          folderUrl: folderUrl,
          referenceId: referenceId,
          confirmedAt: confirmedAt,
        ),
      DriveUploadFailure(:final message, :final canRetry) => _FailureCard(
          message: message,
          canRetry: canRetry,
          onRetry: onRetry,
        ),
    };
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.folderPath,
    required this.folderUrl,
    required this.referenceId,
    required this.confirmedAt,
  });

  final String folderPath;
  final String folderUrl;
  final String referenceId;
  final DateTime confirmedAt;

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day} · $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: colors.secondary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Submitted to Google Drive',
                      style: Theme.of(context).textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 24),
          Text('Remote path', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: SelectableText(folderPath)),
              IconButton(
                tooltip: 'Copy Google Drive link',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: folderUrl)),
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const Divider(height: 32),
          Text('Reference ID', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SelectableText(referenceId),
          const SizedBox(height: 20),
          Text('Confirmed', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(_formatDate(confirmedAt)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              await launchUrl(Uri.parse(folderUrl),
                  mode: LaunchMode.externalApplication);
            },
            label: const Text('Open in Google Drive'),
          ),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({
    required this.message,
    required this.canRetry,
    this.onRetry,
  });

  final String message;
  final bool canRetry;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: colors.error),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Upload Failed',
                      style: Theme.of(context).textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: colors.error, height: 1.5)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: canRetry ? onRetry : null,
            child: Text(canRetry ? 'Retry Upload' : 'Re-authenticate'),
          ),
        ],
      ),
    );
  }
}
