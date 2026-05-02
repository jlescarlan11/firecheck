// lib/features/upload/presentation/upload_queue_screen.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UploadQueueScreen extends ConsumerStatefulWidget {
  const UploadQueueScreen({super.key});

  @override
  ConsumerState<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends ConsumerState<UploadQueueScreen> {
  bool _autoUpload = false;

  @override
  void initState() {
    super.initState();
    _loadAutoUpload();
  }

  Future<void> _loadAutoUpload() async {
    final prefs = ref.read(driveUploadPreferencesProvider);
    final enabled = await prefs.isAutoUploadEnabled();
    if (mounted) {
      setState(() => _autoUpload = enabled);
    }
  }

  Future<void> _toggleAutoUpload(bool value) async {
    final prefs = ref.read(driveUploadPreferencesProvider);
    await prefs.setAutoUploadEnabled(enabled: value);
    if (mounted) {
      setState(() => _autoUpload = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driveUploadNotifierProvider);
    final notifier = ref.read(driveUploadNotifierProvider.notifier);

    final totalMb =
        (state.totalPendingBytes / 1024 / 1024).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(title: const Text('Uploads')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  '${state.pendingCount} file(s) · $totalMb MB',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Text('Auto-upload'),
                const SizedBox(width: 8),
                Switch(
                  value: _autoUpload,
                  onChanged: _toggleAutoUpload,
                ),
              ],
            ),
          ),

          // Progress bar (only when uploading)
          if (state.isUploading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Uploading… ${state.uploadingCount} files'),
                  const SizedBox(height: 4),
                  const LinearProgressIndicator(value: null),
                ],
              ),
            ),

          // File list
          Expanded(
            child: state.jobs.isEmpty
                ? const Center(child: Text('No pending uploads'))
                : ListView.separated(
                    itemCount: state.jobs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final job = state.jobs[index];
                      return _JobTile(
                        job: job,
                        onRetry: () => notifier.retryJob(job.id),
                      );
                    },
                  ),
          ),

          // Upload All button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed:
                  (state.isUploading || state.pendingCount == 0)
                      ? null
                      : () => notifier.uploadAll(),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Upload All'),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onRetry});

  final DriveUploadJob job;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isFailed = job.status == DriveUploadJobStatus.failed ||
        job.status == DriveUploadJobStatus.dead;

    final kb = (job.fileSizeBytes / 1024).toStringAsFixed(0);

    String chipText;
    switch (job.status) {
      case DriveUploadJobStatus.pending:
        chipText = 'PENDING';
        break;
      case DriveUploadJobStatus.uploading:
        chipText = 'UPLOADING';
        break;
      case DriveUploadJobStatus.completed:
        chipText = '✓ DONE';
        break;
      case DriveUploadJobStatus.failed:
        chipText = 'FAILED';
        break;
      case DriveUploadJobStatus.dead:
        chipText = 'FAILED';
        break;
      default:
        chipText = job.status.toUpperCase();
    }

    return ListTile(
      leading: Icon(
        job.fileType == DriveFileType.photo
            ? Icons.image
            : Icons.folder_zip,
      ),
      title: Text(job.fileName),
      subtitle: isFailed
          ? Text(
              job.failureReason ?? 'Upload failed · Tap to retry',
              style: const TextStyle(color: Colors.red),
            )
          : Text('${job.assignmentId} · $kb KB'),
      trailing: Text(chipText),
      onTap: isFailed ? onRetry : null,
    );
  }
}
