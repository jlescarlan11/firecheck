import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_confirmer.dart';
import 'package:firecheck/features/review/domain/upload_flow_outcome.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/drive_upload_notifier.dart';
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

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  @override
  void deactivate() {
    // Clear lingering Completed state so re-entering the screen shows the
    // normal review, not a stale success card. InProgress is preserved so
    // a user who leaves mid-upload can return and keep watching progress.
    // Runs in deactivate (not dispose) because ref.read is invalid once
    // the ConsumerStatefulElement is disposed.
    final progress = ref.read(uploadProgressControllerProvider);
    if (progress is Completed) {
      ref.read(uploadProgressControllerProvider.notifier).reset();
    }
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
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
                      context.push('/feature/${Uri.encodeComponent(id)}'),
                ),
                const SizedBox(height: 8),
                ValidationSection(
                  issues: state.warnings,
                  severity: ReviewSeverity.warning,
                  onGoToFeature: (id) =>
                      context.push('/feature/${Uri.encodeComponent(id)}'),
                ),
                const SizedBox(height: 16),
                StartUploadButton(
                  enabled: state.canStartUpload &&
                      driveUpload is! DriveUploadInProgress,
                  onPressed: () => _runUpload(context, ref, state),
                ),
                const SizedBox(height: 8),
                DriveUploadConfirmationCard(
                  state: driveUpload,
                  onRetry: () => _runUpload(context, ref, state),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _runUpload(
    BuildContext context,
    WidgetRef ref,
    ReviewState state,
  ) async {
    final useCase = ref.read(executeAssignmentUploadUseCaseProvider);
    final notifier = ref.read(driveUploadNotifierProvider.notifier);
    final currentUserId = ref.read(currentUserIdProvider);
    final messenger = ScaffoldMessenger.of(context);

    final outcome = await useCase.execute(
      state: state,
      currentUserId: currentUserId,
      confirmer: _DialogUploadConfirmer(context),
    );

    if (!context.mounted) {
      _applyOutcomeToNotifier(notifier, outcome);
      return;
    }
    switch (outcome) {
      case UploadFlowNoAssignment():
      case UploadFlowCancelled():
        // No-op: progress controller already reset / never started.
        break;
      case UploadFlowSupabaseFailed():
        messenger.showSnackBar(
          const SnackBar(content: Text('Upload failed. Please try again.')),
        );
      case UploadFlowEmpty():
      case UploadFlowIncomplete():
      case UploadFlowSucceeded():
        _applyOutcomeToNotifier(notifier, outcome);
    }
  }

  void _applyOutcomeToNotifier(
    DriveUploadNotifier notifier,
    UploadFlowOutcome outcome,
  ) {
    switch (outcome) {
      case UploadFlowSucceeded(:final folderPath, :final confirmedAt):
        notifier.applyQueueSuccess(
          folderPath: folderPath,
          confirmedAt: confirmedAt,
        );
      case UploadFlowIncomplete(:final completedCount, :final failedCount):
        notifier.applyQueueFailure(
          completedCount > 0
              ? '$completedCount uploaded, $failedCount failed. '
                  'Tap retry to re-upload failed files.'
              : 'Upload failed — $failedCount file(s) could not be sent. '
                  'Check your connection and try again.',
        );
      case UploadFlowEmpty():
        notifier.applyQueueFailure(
          'No files found to upload. Complete your field data first.',
          canRetry: false,
        );
      case UploadFlowNoAssignment():
      case UploadFlowCancelled():
      case UploadFlowSupabaseFailed():
        break;
    }
  }
}

class _DialogUploadConfirmer implements UploadConfirmer {
  _DialogUploadConfirmer(this._context);
  final BuildContext _context;

  @override
  Future<bool> confirmPartial({
    required int unsurveyedCount,
    required int totalFeatures,
  }) async {
    if (!_context.mounted) return false;
    final surveyed = totalFeatures - unsurveyedCount;
    final ok = await showDialog<bool>(
      context: _context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload partial data?'),
        content: Text(
          '$surveyed of $totalFeatures features surveyed. '
          'The remaining $unsurveyedCount unsurveyed feature(s) will be '
          'skipped and can be uploaded later.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Upload partial'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Future<bool> confirmOverwrite({
    required List<DriveUploadAudit> priorUploads,
    required String? currentUserId,
  }) async {
    if (!_context.mounted) return false;
    final latest = priorUploads.first;
    final fromOther = priorUploads
        .where((u) => u.uploadedBy != currentUserId)
        .toList(growable: false);
    final byOther = fromOther.isNotEmpty;
    final shown = byOther ? fromOther.first : latest;

    final who = byOther
        ? (shown.uploaderDisplayName?.trim().isNotEmpty ?? false
            ? shown.uploaderDisplayName!
            : 'another enumerator')
        : 'You';
    final when = _formatTimestamp(shown.uploadedAt);
    final files = shown.fileCount > 0 ? ' (${shown.fileCount} file(s))' : '';

    final ok = await showDialog<bool>(
      context: _context,
      builder: (ctx) => AlertDialog(
        title: Text(
          byOther ? 'Already uploaded by someone else' : 'Already uploaded',
        ),
        content: Text(
          byOther
              ? '$who uploaded this assignment $when$files. '
                  'Uploading again will add a new copy to your Drive folder '
                  'and may overwrite shared data downstream.\n\n'
                  'Continue anyway?'
              : 'You uploaded this assignment $when$files. '
                  'Re-upload to send the latest changes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(byOther ? 'Upload anyway' : 'Re-upload'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Future<bool> confirmUnverified() async {
    if (!_context.mounted) return false;
    final ok = await showDialog<bool>(
      context: _context,
      builder: (ctx) => AlertDialog(
        title: const Text("Couldn't verify prior uploads"),
        content: const Text(
          "We couldn't reach the server to check whether this assignment "
          'was uploaded before. Uploading anyway may overwrite a copy '
          'someone else has already sent.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Upload anyway'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} day(s) ago';
    final m = ts.month.toString().padLeft(2, '0');
    final d = ts.day.toString().padLeft(2, '0');
    return 'on ${ts.year}-$m-$d';
  }
}
