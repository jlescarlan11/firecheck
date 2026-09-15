// lib/features/upload/presentation/upload_queue_screen.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UploadQueueScreen extends ConsumerStatefulWidget {
  const UploadQueueScreen({super.key});

  @override
  ConsumerState<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends ConsumerState<UploadQueueScreen> {
  final _scrollController = ScrollController();
  bool _autoUpload = false;

  void _loadNearEnd() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 300) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(driveUploadNotifierProvider.notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _preferencesBusy = true;
  bool _actionBusy = false;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadNearEnd);
    _loadAutoUpload();
  }

  Future<void> _loadAutoUpload() async {
    final prefs = ref.read(driveUploadPreferencesProvider);
    try {
      final enabled = await prefs.isAutoUploadEnabled();
      if (mounted) setState(() => _autoUpload = enabled);
    } on Object {
      _showError("Couldn't load auto-upload settings. Try again.");
    } finally {
      if (mounted) setState(() => _preferencesBusy = false);
    }
  }

  Future<void> _toggleAutoUpload(bool value) async {
    final prefs = ref.read(driveUploadPreferencesProvider);
    setState(() => _preferencesBusy = true);
    try {
      await prefs.setAutoUploadEnabled(enabled: value);
      if (mounted) setState(() => _autoUpload = value);
    } on Object {
      _showError("Couldn't save auto-upload settings. Try again.");
    } finally {
      if (mounted) setState(() => _preferencesBusy = false);
    }
  }

  Future<void> _runUpload(Future<void> Function() action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
    } on Object {
      _showError(
        "Couldn't start the upload. Your files are still saved. Retry.",
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final state = ref.watch(driveUploadNotifierProvider);
    final notifier = ref.read(driveUploadNotifierProvider.notifier);
    final jobs = state.visibleJobs;

    final totalMb = (state.totalPendingBytes / 1024 / 1024).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(title: const Text('Uploads')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Padding(
                          padding: appPageInsets(context, vertical: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppPageIntro(title: l.designUploadsTitle),
                              Text(
                                '${state.pendingCount} file(s) · $totalMb MB',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              const Divider(),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Auto-upload'),
                                subtitle: const Text('Wi-Fi only'),
                                value: _autoUpload,
                                onChanged:
                                    _preferencesBusy ? null : _toggleAutoUpload,
                              ),
                            ],
                          ),
                        ),

                        // Progress bar (only when uploading)
                        if (state.isUploading)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Uploading… ${state.uploadingCount} files',
                                ),
                                const SizedBox(height: 4),
                                const LinearProgressIndicator(),
                              ],
                            ),
                          ),

                        if (jobs.isEmpty)
                          Padding(
                            padding: appPageInsets(context, vertical: 40),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.cloud_done_outlined,
                                  size: 40,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No pending uploads',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l.designUploadsBody,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (jobs.isNotEmpty)
                    SliverPadding(
                      padding: appPageInsets(context, vertical: 0),
                      sliver: SliverList.separated(
                        itemCount: jobs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final job = jobs[index];
                          return _JobTile(
                            job: job,
                            onRetry: (_actionBusy || state.isUploading)
                                ? null
                                : () =>
                                    _runUpload(() => notifier.retryJob(job.id)),
                          );
                        },
                      ),
                    ),
                  if (state.hasMore || state.isLoadingMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: appPageInsets(context, vertical: 16),
                        child: state.isLoadingMore
                            ? const Center(child: CircularProgressIndicator())
                            : TextButton(
                                onPressed: notifier.loadMore,
                                child: Text(l.uploadLoadMore),
                              ),
                      ),
                    ),
                ],
              ),
            ),

            // Upload All button
            Padding(
              padding: appPageInsets(context, vertical: 16),
              child: ElevatedButton(
                onPressed: (_actionBusy ||
                        state.isUploading ||
                        state.pendingCount == 0)
                    ? null
                    : () => _runUpload(notifier.uploadAll),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Upload All'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onRetry});

  final DriveUploadJob job;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isFailed = job.status == DriveUploadJobStatus.failed ||
        job.status == DriveUploadJobStatus.dead;

    final kb = (job.fileSizeBytes / 1024).toStringAsFixed(0);

    final chipText = switch (job.status) {
      DriveUploadJobStatus.pending => 'Pending',
      DriveUploadJobStatus.uploading => 'Uploading',
      DriveUploadJobStatus.completed => 'Done',
      DriveUploadJobStatus.failed => 'FAILED',
      DriveUploadJobStatus.dead => 'FAILED',
      _ => job.status.toUpperCase(),
    };

    return ListTile(
      leading: Icon(
        job.fileType == DriveFileType.photo
            ? Icons.image_outlined
            : Icons.folder_zip_outlined,
      ),
      title: Text(job.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: isFailed
          ? Text(
              job.failureReason ?? 'Upload failed · Tap to retry',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          : Text('${job.assignmentId} · $kb KB'),
      trailing: isFailed
          ? IconButton(
              tooltip: 'Retry upload',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
            )
          : Text(chipText, style: Theme.of(context).textTheme.labelSmall),
      onTap: isFailed ? onRetry : null,
    );
  }
}
