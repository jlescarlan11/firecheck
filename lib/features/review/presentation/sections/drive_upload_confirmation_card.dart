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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour > 12
        ? dt.hour - 12
        : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day} · $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Upload successful. Remote path: $folderPath. Reference ID: $referenceId.',
      excludeSemantics: true,
      child: Card(
        color: const Color(0xFFF0FDF4),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF15803D), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Submitted to Google Drive',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REMOTE PATH',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF166534),
                        letterSpacing: 0.06,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            folderPath,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Color(0xFF14532D),
                            ),
                          ),
                        ),
                        Semantics(
                          label: 'Copy remote path to clipboard',
                          child: TextButton(
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: folderUrl),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text(
                              'Copy',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _InfoBox(label: 'REFERENCE ID', value: referenceId),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _InfoBox(
                      label: 'CONFIRMED',
                      value: _formatDate(confirmedAt),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse(folderUrl);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Center(
                  child: Text(
                    'Open in Google Drive →',
                    style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF166534),
              letterSpacing: 0.06,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF14532D),
            ),
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
    return Semantics(
      label:
          'Upload failed. $message.${canRetry ? ' Retry button available.' : ''}',
      excludeSemantics: true,
      child: Card(
        color: const Color(0xFFFEF2F2),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error, color: Color(0xFFDC2626), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Upload Failed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF7F1D1D),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(canRetry ? 'Retry Upload' : 'Re-authenticate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
