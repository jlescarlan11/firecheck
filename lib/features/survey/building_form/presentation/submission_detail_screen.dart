import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_validator.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_tabs.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_validator.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _softCap = 5;

final _submissionsForFeatureProvider = StreamProvider.autoDispose
    .family<List<Submission>, String>((ref, featureId) {
  return ref
      .watch(submissionRepositoryProvider)
      .watchSubmissionsForFeature(featureId);
});

final _photoCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, submissionId) async* {
  final repo = ref.watch(photoRepositoryProvider);
  await for (final list in repo.watchForSubmission(submissionId)) {
    yield list.length;
  }
});

final _featureByIdProvider = FutureProvider.autoDispose
    .family<Feature?, String>((ref, featureId) async {
  return ref.watch(featureRepositoryProvider).getFeature(featureId);
});

class SubmissionDetailScreen extends ConsumerStatefulWidget {
  const SubmissionDetailScreen({required this.featureId, super.key});
  final String featureId;

  @override
  ConsumerState<SubmissionDetailScreen> createState() =>
      _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState
    extends ConsumerState<SubmissionDetailScreen> {
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_ensureFirst);
  }

  Future<void> _ensureFirst() async {
    final repo = ref.read(submissionRepositoryProvider);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('SubmissionDetailScreen reached without an authenticated user');
    }
    await repo.ensureDraftForFeature(
      featureId: widget.featureId,
      enumeratorId: userId,
    );
  }

  Future<void> _addTab() async {
    final repo = ref.read(submissionRepositoryProvider);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('SubmissionDetailScreen._addTab without authenticated user');
    }
    await repo.createAdditionalSubmission(
      featureId: widget.featureId,
      enumeratorId: userId,
    );
    final submissions =
        await repo.watchSubmissionsForFeature(widget.featureId).first;
    if (mounted) setState(() => _activeIndex = submissions.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final featureAsync = ref.watch(_featureByIdProvider(widget.featureId));
    final submissionsAsync =
        ref.watch(_submissionsForFeatureProvider(widget.featureId));

    return featureAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (feature) {
        if (feature == null) {
          return Scaffold(body: Center(child: Text(l.featureNotFound)));
        }
        final isRoad = feature.featureType == 'road';
        final title = isRoad
            ? l.submissionDetailTitleRoad
            : l.submissionDetailTitleBuilding;

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: submissionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (submissions) {
              if (submissions.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_activeIndex >= submissions.length) {
                // Tab was removed while the screen was open; clamp.
                _activeIndex = submissions.length - 1;
              }
              final active = submissions[_activeIndex];
              return Column(
                children: [
                  // Read-only banner when the assignment is locked. Renders
                  // above SubmissionTabs so it's the first thing the user
                  // sees on a previously-submitted feature. Bug 15 follow-up.
                  Consumer(
                    builder: (context, ref2, _) {
                      final lock = ref2.watch(assignmentLockStateProvider).value;
                      if (lock is! Submitted && lock is! ClosedRemotely) {
                        return const SizedBox.shrink();
                      }
                      final isClosed = lock is ClosedRemotely;
                      return Container(
                        width: double.infinity,
                        color: isClosed
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFFEF3C7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: isClosed
                                  ? const Color(0xFFC53030)
                                  : const Color(0xFFB7791F),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isClosed
                                    ? l.readOnlyBannerClosed
                                    : l.readOnlyBanner,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isClosed
                                      ? const Color(0xFFC53030)
                                      : const Color(0xFFB7791F),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  SubmissionTabs(
                    submissions: submissions,
                    activeIndex: _activeIndex,
                    onTap: (i) => setState(() => _activeIndex = i),
                    onAdd: _addTab,
                    canAddMore: submissions.length < _softCap,
                    softCapTooltip: l.tabSoftCapTooltip,
                  ),
                  Consumer(
                    builder: (context, ref2, _) {
                      final locked = ref2.watch(isAssignmentLockedProvider);
                      return IgnorePointer(
                        ignoring: locked,
                        child: PhotoStrip(submissionId: active.id),
                      );
                    },
                  ),
                  Expanded(
                    child: Consumer(
                      builder: (context, ref2, _) {
                        final locked = ref2.watch(isAssignmentLockedProvider);
                        // Bug 15: pass readOnly: locked instead of wrapping
                        // the form in IgnorePointer. IgnorePointer blocks
                        // ALL pointer events including scroll, so users
                        // couldn't review submitted data on a long form.
                        // The form's existing `disabled` plumbing already
                        // disables every input via enabled:/onChanged:null;
                        // readOnly just OR's that on top of doesNotExist.
                        return isRoad
                            ? RoadForm(
                                submissionId: active.id,
                                featureId: widget.featureId,
                                readOnly: locked,
                              )
                            : BuildingForm(
                                submissionId: active.id,
                                featureId: widget.featureId,
                                readOnly: locked,
                              );
                      },
                    ),
                  ),
                  _Footer(
                    submissionId: active.id,
                    featureId: widget.featureId,
                    isRoad: isRoad,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.submissionId,
    required this.featureId,
    required this.isRoad,
  });

  final String submissionId;
  final String featureId;
  final bool isRoad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final isLocked = ref.watch(isAssignmentLockedProvider);
    if (isLocked) return const SizedBox.shrink();
    final photoCountAsync = ref.watch(_photoCountProvider(submissionId));

    final ready = photoCountAsync.maybeWhen(
      data: (photoCount) {
        if (isRoad) {
          final key = RoadFormKey(
            submissionId: submissionId,
            featureId: featureId,
          );
          final state = ref.watch(roadFormNotifierProvider(key));
          return validateRoadForm(state, photoCount).isComplete;
        } else {
          final key = BuildingFormKey(
            submissionId: submissionId,
            featureId: featureId,
          );
          final state = ref.watch(buildingFormNotifierProvider(key));
          return validateBuildingForm(state, photoCount).isComplete;
        }
      },
      orElse: () => false,
    );

    return photoCountAsync.when(
      loading: () => const SizedBox(height: 56),
      error: (_, __) => const SizedBox(height: 56),
      data: (photoCount) {
        final statusText = ready
            ? l.footerStatusReady
            : (photoCount < 1
                ? l.footerStatusPhotoRequired
                : l.footerStatusFieldsMissing);
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: ready
                        ? const Color(0xFF276749)
                        : const Color(0xFFC53030),
                  ),
                ),
              ),
              FilledButton(
                onPressed: ready
                    ? () async {
                        if (isRoad) {
                          final key = RoadFormKey(
                            submissionId: submissionId,
                            featureId: featureId,
                          );
                          await ref
                              .read(roadFormNotifierProvider(key).notifier)
                              .flushNow();
                        } else {
                          final key = BuildingFormKey(
                            submissionId: submissionId,
                            featureId: featureId,
                          );
                          await ref
                              .read(buildingFormNotifierProvider(key).notifier)
                              .flushNow();
                        }
                        // Forward-only transition: don't regress a submission
                        // that's already past ready_to_upload. Re-tapping Done
                        // on an uploaded submission must not flip its local
                        // sync_status back, or its already-uploaded photos
                        // would get stuck waiting for a parent that's no
                        // longer 'uploaded'.
                        final db = ref.read(appDatabaseProvider);
                        final current = await (db.select(db.submissions)
                              ..where((t) => t.id.equals(submissionId)))
                            .getSingleOrNull();
                        const advancable = {'draft', 'in_progress'};
                        if (current != null &&
                            advancable.contains(current.syncStatus)) {
                          await ref
                              .read(submissionRepositoryProvider)
                              .markStatus(submissionId, 'ready_to_upload');
                        }
                        // Recompute the feature's color-coded status so the
                        // map polygon flips green immediately.
                        await ref
                            .read(featureRepositoryProvider)
                            .markFeatureStatus(featureId);
                        if (context.mounted) context.go('/map');
                      }
                    : null,
                child: Text(l.doneButton),
              ),
            ],
          ),
        );
      },
    );
  }
}
