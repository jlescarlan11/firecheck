import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
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
    await repo.ensureDraftForFeature(
      featureId: widget.featureId,
      enumeratorId: 'admin', // Phase 4 will wire real auth
    );
  }

  Future<void> _addTab() async {
    final repo = ref.read(submissionRepositoryProvider);
    await repo.createAdditionalSubmission(
      featureId: widget.featureId,
      enumeratorId: 'admin',
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
                  SubmissionTabs(
                    submissions: submissions,
                    activeIndex: _activeIndex,
                    onTap: (i) => setState(() => _activeIndex = i),
                    onAdd: _addTab,
                    canAddMore: submissions.length < _softCap,
                    softCapTooltip: l.tabSoftCapTooltip,
                  ),
                  PhotoStrip(submissionId: active.id),
                  Expanded(
                    child: isRoad
                        ? RoadForm(
                            submissionId: active.id,
                            featureId: widget.featureId,
                          )
                        : BuildingForm(
                            submissionId: active.id,
                            featureId: widget.featureId,
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
                        await ref
                            .read(submissionRepositoryProvider)
                            .markStatus(submissionId, 'ready_to_upload');
                        // Recompute the feature's color-coded status so the
                        // map polygon flips green immediately. Without this,
                        // the polygon stays yellow until the next autosave or
                        // re-tap triggers markFeatureStatus.
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
