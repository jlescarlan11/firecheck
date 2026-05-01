import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
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
                UploadProgressSection(progress: state.upload)
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
                  onGoToFeature: (id) => context.go('/feature/${Uri.encodeComponent(id)}'),
                ),
                const SizedBox(height: 8),
                ValidationSection(
                  issues: state.warnings,
                  severity: ReviewSeverity.warning,
                  onGoToFeature: (id) => context.go('/feature/${Uri.encodeComponent(id)}'),
                ),
                const SizedBox(height: 16),
                StartUploadButton(
                  enabled: state.canStartUpload,
                  onPressed: () => _start(context, ref),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    ref.read(uploadProgressControllerProvider.notifier).beginUpload();
    final useCase = ref.read(startUploadUseCaseProvider);
    final repo = ref.read(assignmentRepositoryProvider);
    final assignment = await repo.getCurrentAssignment();
    if (assignment == null) return;
    await useCase.execute(assignment.id);
  }
}
