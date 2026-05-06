import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart'
    hide driveUploadNotifierProvider;
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
import 'package:firecheck/features/review/presentation/sections/drive_upload_confirmation_card.dart';
import 'package:firecheck/features/review/presentation/sections/failed_jobs_section.dart';
import 'package:firecheck/features/review/presentation/sections/start_upload_button.dart';
import 'package:firecheck/features/review/presentation/sections/summary_card.dart';
import 'package:firecheck/features/review/presentation/sections/upload_progress_section.dart';
import 'package:firecheck/features/review/presentation/sections/validation_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final stateAsync = ref.watch(reviewStateProvider);
    final driveUpload = ref.watch(driveUploadNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.reviewTitle)),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) {
          final inProgressOrCompleted =
              state.upload is InProgress || state.upload is Completed;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (inProgressOrCompleted)
                UploadProgressSection(
                  progress: state.upload,
                  onReset: () => ref
                      .read(uploadProgressControllerProvider.notifier)
                      .reset(),
                )
              else ...[
                SummaryCard(summary: state.summary),
                const SizedBox(height: 8),
                FailedJobsSection(
                  deadJobs: state.deadJobs,
                  onRetryAll: () =>
                      ref.read(retryDeadUseCaseProvider).retryAll(),
                  onRetryOne: (id) =>
                      ref.read(retryDeadUseCaseProvider).retryOne(id),
                ),
                const SizedBox(height: 8),
                ValidationSection(
                  issues: state.blockers,
                  severity: ReviewSeverity.blocker,
                  onGoToFeature: (id) =>
                      context.go('/feature/${Uri.encodeComponent(id)}'),
                ),
                const SizedBox(height: 8),
                ValidationSection(
                  issues: state.warnings,
                  severity: ReviewSeverity.warning,
                  onGoToFeature: (id) =>
                      context.go('/feature/${Uri.encodeComponent(id)}'),
                ),
                const SizedBox(height: 16),
                StartUploadButton(
                  enabled: state.canStartUpload,
                  onPressed: () => _startSupabaseUpload(context, ref),
                ),
                const SizedBox(height: 8),
                if (driveUpload is! DriveUploadSuccess) ...[
                  FilledButton.icon(
                    onPressed: driveUpload is DriveUploadInProgress
                        ? null
                        : () => _startDriveUpload(ref),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Upload to Google Drive'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                DriveUploadConfirmationCard(
                  state: driveUpload,
                  onRetry: () => _startDriveUpload(ref),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _startSupabaseUpload(BuildContext context, WidgetRef ref) async {
    debugPrint('[StartUpload] beginning upload');
    ref.read(uploadProgressControllerProvider.notifier).beginUpload();
    try {
      final useCase = ref.read(startUploadUseCaseProvider);
      final repo = ref.read(assignmentRepositoryProvider);
      final assignment = await repo.getCurrentAssignment();
      if (assignment == null) {
        debugPrint('[StartUpload] no current assignment — aborting');
        ref.read(uploadProgressControllerProvider.notifier).reset();
        return;
      }
      debugPrint('[StartUpload] executing for assignment ${assignment.id}');
      final result = await useCase.execute(assignment.id);
      debugPrint(
        '[StartUpload] finalized ${result.finalizedCount} submission(s); '
        'sync worker triggered',
      );
      if (result.finalizedCount == 0) {
        ref.read(uploadProgressControllerProvider.notifier).reset();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Nothing new to upload — all items already synced.'),
            ),
          );
        }
        return;
      }
    } catch (e, st) {
      debugPrint('[StartUpload] failed: $e\n$st');
      ref.read(uploadProgressControllerProvider.notifier).reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _startDriveUpload(WidgetRef ref) async {
    debugPrint('[DriveUpload] enqueue started');
    final assignment = await ref
        .read(assignmentRepositoryProvider)
        .getCurrentAssignment();
    if (assignment == null) {
      debugPrint('[DriveUpload] no current assignment');
      return;
    }

    final driveRepo = ref.read(driveUploadRepoProvider);
    final enqueued = await ref
        .read(enqueueAssignmentUseCaseProvider)
        .execute(assignmentId: assignment.id);
    debugPrint('[DriveUpload] enqueued $enqueued new job(s)');

    final allJobs = await driveRepo.getJobsForAssignment(assignment.id);
    debugPrint(
      '[DriveUpload][debug] queue for ${assignment.id}: '
      '${allJobs.length} total · '
      '${allJobs.where((j) => j.status == DriveUploadJobStatus.pending).length} pending · '
      '${allJobs.where((j) => j.status == DriveUploadJobStatus.completed).length} completed · '
      '${allJobs.where((j) => j.status == DriveUploadJobStatus.failed).length} failed · '
      '${allJobs.where((j) => j.status == DriveUploadJobStatus.dead).length} dead',
    );

    if (allJobs.isEmpty) {
      debugPrint('[DriveUpload] nothing to upload');
      ref.read(driveUploadNotifierProvider.notifier).applyQueueFailure(
            'No files found to upload. Complete your field data first.',
            canRetry: false,
          );
      return;
    }

    await ref.read(driveUploadWorkerProvider).drain();

    final finalJobs = await driveRepo.getJobsForAssignment(assignment.id);
    final completed = finalJobs
        .where((j) => j.status == DriveUploadJobStatus.completed)
        .length;
    final failed = finalJobs
        .where((j) =>
            j.status == DriveUploadJobStatus.failed ||
            j.status == DriveUploadJobStatus.dead,)
        .length;
    debugPrint(
      '[DriveUpload][debug] after drain: $completed completed, $failed failed',
    );

    if (completed > 0 && failed == 0) {
      final now = DateTime.now();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final folderPath = '${assignment.enumeratorId}/$dateKey/';
      await ref.read(assignmentRepositoryProvider).setDriveUploadResult(
            assignmentId: assignment.id,
            driveFolderPath: folderPath,
            driveFolderUrl: '',
            driveUploadConfirmedAt: now,
          );
      ref.read(driveUploadNotifierProvider.notifier).applyQueueSuccess(
            folderPath: folderPath,
            confirmedAt: now,
            assignmentId: assignment.id,
          );
    } else {
      ref.read(driveUploadNotifierProvider.notifier).applyQueueFailure(
            completed > 0
                ? '$completed uploaded, $failed failed. '
                    'Tap retry to re-upload failed files.'
                : 'Upload failed — $failed file(s) could not be sent. '
                    'Check your connection and try again.',
          );
    }
  }
}
