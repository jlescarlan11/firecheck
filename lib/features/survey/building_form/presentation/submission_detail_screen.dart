import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_configuration_gate.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/core/forms/geometry_signal_providers.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_context.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_validator.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_tabs.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_context.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_validator.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _softCap = 5;
const _editableSubmissionStatuses = {
  'draft',
  'in_progress',
  'ready_to_upload',
  'queued',
  'uploaded',
};

bool _canEditSubmission(Submission submission, String? actor, bool locked) =>
    !locked &&
    actor != null &&
    actor.isNotEmpty &&
    submission.submittedBy == actor &&
    _editableSubmissionStatuses.contains(submission.syncStatus);

final _submissionsForFeatureProvider = StreamProvider.autoDispose
    .family<List<Submission>, String>((ref, featureId) {
  return ref
      .watch(submissionRepositoryProvider)
      .watchSubmissionsForFeature(featureId);
});

final _photoCountProvider =
    StreamProvider.autoDispose.family<int, String>((ref, submissionId) async* {
  final repo = ref.watch(photoRepositoryProvider);
  await for (final list in repo.watchForSubmission(submissionId)) {
    yield list.length;
  }
});

final _featureByIdProvider =
    FutureProvider.autoDispose.family<Feature?, String>((ref, featureId) async {
  return ref.watch(featureRepositoryProvider).getFeature(featureId);
});

class SubmissionDetailScreen extends ConsumerStatefulWidget {
  const SubmissionDetailScreen({
    required this.featureId,
    this.initialSubmissionId,
    super.key,
  });
  final String featureId;
  final String? initialSubmissionId;

  @override
  ConsumerState<SubmissionDetailScreen> createState() =>
      _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState
    extends ConsumerState<SubmissionDetailScreen> {
  int _activeIndex = 0;
  bool _selectedInitialSubmission = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    Future.microtask(_ensureFirst);
  }

  Future<void> _ensureFirst() async {
    try {
      final feature = await ref
          .read(featureRepositoryProvider)
          .getFeature(widget.featureId);
      final assignment = ref.read(currentAssignmentProvider).valueOrNull;
      if (feature == null ||
          assignment == null ||
          feature.assignmentId != assignment.id) {
        throw StateError('Open this building from its map in My Maps.');
      }
      final definition = await ref.read(currentFormDefinitionProvider.future);
      await ref.read(fieldRequirementsConfigProvider.future);
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw StateError('Sign in to gather data.');
      final repository = ref.read(submissionRepositoryProvider);
      final existingCount =
          await repository.countSubmissionsForFeature(widget.featureId);
      if (existingCount > 0) return;
      if (assignment.closedRemotely) throw StateError('This map is closed.');
      await repository.ensureDraftForFeature(
        featureId: widget.featureId,
        enumeratorId: userId,
        formVersion: definition.version,
      );
    } catch (error) {
      if (mounted) setState(() => _loadError = error.toString());
    }
  }

  Future<void> _addTab() async {
    if (ref.read(isAssignmentLockedProvider)) return;
    final definition = await ref.read(currentFormDefinitionProvider.future);
    final repo = ref.read(submissionRepositoryProvider);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError(
        'SubmissionDetailScreen._addTab without authenticated user',
      );
    }
    await repo.createAdditionalSubmission(
      featureId: widget.featureId,
      enumeratorId: userId,
      formVersion: definition.version,
    );
    final submissions =
        await repo.watchSubmissionsForFeature(widget.featureId).first;
    if (mounted) setState(() => _activeIndex = submissions.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gather Data')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!),
                TextButton(
                  onPressed: () => context.pushReplacement('/my-maps'),
                  child: const Text('My Maps'),
                ),
              ],
            ),
          ),
        ),
      );
    }
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
              if (!_selectedInitialSubmission) {
                _selectedInitialSubmission = true;
                final requested = widget.initialSubmissionId;
                if (requested != null) {
                  final requestedIndex =
                      submissions.indexWhere((item) => item.id == requested);
                  if (requestedIndex >= 0) _activeIndex = requestedIndex;
                }
              }
              if (_activeIndex >= submissions.length) {
                // Tab was removed while the screen was open; clamp.
                _activeIndex = submissions.length - 1;
              }
              final active = submissions[_activeIndex];
              return ProviderScope(
                overrides: [
                  formDefinitionVersionProvider.overrideWithValue(
                    active.formVersion,
                  ),
                ],
                child: FormConfigurationGate(
                  child: PopScope(
                    // Block the default pop, run flushNow + markFeatureStatus,
                    // then pop explicitly. Without this, dispose-time _flush is
                    // fire-and-forget and the feature can render red on the map
                    // until the user re-opens and saves again.
                    // Done also routes through this handler via context.pop(); its
                    // own flushNow + markFeatureStatus calls are idempotent.
                    canPop: false,
                    onPopInvokedWithResult: (didPop, _) async {
                      if (didPop) return;
                      try {
                        if (isRoad) {
                          final fkey = RoadFormKey(
                            submissionId: active.id,
                            featureId: widget.featureId,
                          );
                          await ref
                              .read(roadFormNotifierProvider(fkey).notifier)
                              .flushNow();
                        } else {
                          final fkey = BuildingFormKey(
                            submissionId: active.id,
                            featureId: widget.featureId,
                          );
                          await ref
                              .read(buildingFormNotifierProvider(fkey).notifier)
                              .flushNow();
                        }
                        await ref
                            .read(featureRepositoryProvider)
                            .markFeatureStatus(widget.featureId);
                      } catch (_) {
                        // Don't trap the user in the form if save fails.
                      }
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Column(
                      children: [
                        // Read-only banner when the assignment is closed remotely.
                        // Submitted is no longer a hard lock — enumerators may
                        // re-edit and re-submit after the first submission.
                        Consumer(
                          builder: (context, ref2, _) {
                            final lock =
                                ref2.watch(assignmentLockStateProvider).value;
                            if (lock is! ClosedRemotely) {
                              return const SizedBox.shrink();
                            }
                            return Container(
                              width: double.infinity,
                              color: const Color(0xFFFEE2E2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.lock_outline,
                                    size: 16,
                                    color: Color(0xFFC53030),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l.readOnlyBannerClosed,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFC53030),
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
                            final locked =
                                ref2.watch(isAssignmentLockedProvider);
                            return IgnorePointer(
                              ignoring: !_canEditSubmission(
                                active,
                                ref2.watch(currentUserIdProvider),
                                locked,
                              ),
                              child: PhotoStrip(
                                submissionId: active.id,
                                featureId: widget.featureId,
                              ),
                            );
                          },
                        ),
                        Expanded(
                          child: Consumer(
                            builder: (context, ref2, _) {
                              final locked =
                                  ref2.watch(isAssignmentLockedProvider);
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
                                      readOnly: !_canEditSubmission(
                                        active,
                                        ref2.watch(currentUserIdProvider),
                                        locked,
                                      ),
                                    )
                                  : BuildingForm(
                                      submissionId: active.id,
                                      featureId: widget.featureId,
                                      readOnly: !_canEditSubmission(
                                        active,
                                        ref2.watch(currentUserIdProvider),
                                        locked,
                                      ),
                                    );
                            },
                          ),
                        ),
                        _Footer(
                          submission: active,
                          featureId: widget.featureId,
                          isRoad: isRoad,
                        ),
                      ],
                    ),
                  ),
                ),
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
    required this.submission,
    required this.featureId,
    required this.isRoad,
  });

  final Submission submission;
  String get submissionId => submission.id;
  final String featureId;
  final bool isRoad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final isLocked = ref.watch(isAssignmentLockedProvider);
    if (!_canEditSubmission(
      submission,
      ref.watch(currentUserIdProvider),
      isLocked,
    )) {
      return const SizedBox.shrink();
    }
    final photoCountAsync = ref.watch(_photoCountProvider(submissionId));

    final requirements = ref.watch(fieldRequirementsProvider);
    final definition = ref.watch(currentFormDefinitionProvider).valueOrNull;
    final geometry = ref.watch(geometrySignalProvider(featureId)).valueOrNull ??
        GeometrySignal.empty;
    final ready = photoCountAsync.maybeWhen(
      data: (photoCount) {
        if (isRoad) {
          final key = RoadFormKey(
            submissionId: submissionId,
            featureId: featureId,
          );
          final state = ref.watch(roadFormNotifierProvider(key));
          final legacyComplete = validateRoadForm(
            state,
            photoCount,
            requirements: requirements,
          ).isComplete;
          final definitionComplete = definition == null ||
              definition
                  .validate(
                    roadFormContext(state, geometry).answers,
                    now: DateTime.now(),
                  )
                  .isEmpty;
          return legacyComplete && definitionComplete;
        } else {
          final key = BuildingFormKey(
            submissionId: submissionId,
            featureId: featureId,
          );
          final state = ref.watch(buildingFormNotifierProvider(key));
          final legacyComplete = validateBuildingForm(
            state,
            photoCount,
            requirements: requirements,
            hidden: ref.watch(currentFormVariantProvider).hideBuildingFields,
            definition: definition ?? FormDefinition.legacy,
            geometry: geometry,
          ).isComplete;
          final definitionComplete = definition == null ||
              definition
                  .validate(
                    buildingFormContext(state, geometry).answers,
                    now: DateTime.now(),
                  )
                  .isEmpty;
          return legacyComplete && definitionComplete;
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
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    color: ready
                        ? const Color(0xFF276749)
                        : const Color(0xFFC53030),
                  ),
                ),
              ),
              FilledButton(
                onPressed: ready
                    ? () async {
                        try {
                          final guardDb = ref.read(appDatabaseProvider);
                          final beforeSave =
                              await (guardDb.select(guardDb.submissions)
                                    ..where((t) => t.id.equals(submissionId)))
                                  .getSingle();
                          final owningFeature =
                              await (guardDb.select(guardDb.features)
                                    ..where((t) => t.id.equals(featureId)))
                                  .getSingle();
                          final owningMap =
                              await (guardDb.select(guardDb.assignments)
                                    ..where(
                                      (t) => t.id
                                          .equals(owningFeature.assignmentId),
                                    ))
                                  .getSingle();
                          if (!_canEditSubmission(
                            beforeSave,
                            ref.read(currentUserIdProvider),
                            owningMap.closedRemotely,
                          )) {
                            return;
                          }
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
                                .read(
                                  buildingFormNotifierProvider(key).notifier,
                                )
                                .flushNow();
                          }
                          final db = ref.read(appDatabaseProvider);
                          final current = await (db.select(db.submissions)
                                ..where((t) => t.id.equals(submissionId)))
                              .getSingleOrNull();
                          final currentMap = await (db.select(db.assignments)
                                ..where(
                                  (t) =>
                                      t.id.equals(owningFeature.assignmentId),
                                ))
                              .getSingle();
                          if (current == null ||
                              !_canEditSubmission(
                                current,
                                ref.read(currentUserIdProvider),
                                currentMap.closedRemotely,
                              )) {
                            return;
                          }
                          final latest =
                              await SyncJobsRepository(db).findByEntity(
                            SyncEntityType.attributionUpload,
                            submissionId,
                          );
                          final changed = latest?.payloadJson != null &&
                              !SubmissionPayloadBuilder.sameRevision(
                                Map<String, dynamic>.from(
                                  jsonDecode(latest!.payloadJson!) as Map,
                                ),
                                await SubmissionPayloadBuilder(db)
                                    .build(submissionId),
                              );
                          if ({'draft', 'in_progress'}
                                  .contains(current.syncStatus) ||
                              (changed &&
                                  {'uploaded', 'queued'}
                                      .contains(current.syncStatus))) {
                            final feature = await (db.select(db.features)
                                  ..where((t) => t.id.equals(featureId)))
                                .getSingle();
                            final capability =
                                await (db.select(db.sharedMapCursors)
                                      ..where(
                                        (t) =>
                                            t.accountId.equals(
                                              current.submittedBy ?? '',
                                            ) &
                                            t.assignmentId
                                                .equals(feature.assignmentId),
                                      ))
                                    .getSingleOrNull();
                            await db.transaction(() async {
                              await ref
                                  .read(submissionRepositoryProvider)
                                  .markStatus(submissionId, 'ready_to_upload');
                              if (capability != null) {
                                await FinalizeSubmissionUseCase(db)
                                    .execute(submissionId);
                              }
                            });
                            if (capability != null) {
                              unawaited(
                                ref.read(syncControllerProvider).triggerNow(),
                              );
                            }
                          }
                          // New photographic evidence can complete independently
                          // of already-acknowledged survey answers.
                          if ({'uploaded', 'queued'}
                                  .contains(current.syncStatus) &&
                              !changed) {
                            final result = await FinalizeSubmissionUseCase(db)
                                .execute(submissionId);
                            if (result.photoCount > 0) {
                              final feature = await (db.select(db.features)
                                    ..where((t) => t.id.equals(featureId)))
                                  .getSingle();
                              final shared =
                                  await (db.select(db.sharedMapCursors)
                                        ..where(
                                          (t) =>
                                              t.assignmentId.equals(
                                                feature.assignmentId,
                                              ) &
                                              t.accountId.equals(
                                                current.submittedBy ?? '',
                                              ),
                                        ))
                                      .getSingleOrNull();
                              if (shared != null) {
                                unawaited(
                                  ref.read(syncControllerProvider).triggerNow(),
                                );
                              }
                            }
                          }
                          // Recompute the feature's color-coded status so the
                          // map polygon flips green immediately.
                          await ref
                              .read(featureRepositoryProvider)
                              .markFeatureStatus(featureId);
                          // Pop the form off the router stack so the user lands
                          // back on /map with /home still beneath it. Using
                          // context.go('/map') here would flatten the stack to
                          // [/map] and a subsequent Back from /map would exit
                          // the app. PopScope's handler re-runs flushNow +
                          // markFeatureStatus (both idempotent) before its
                          // manual pop completes the navigation.
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l.surveySavedLocally),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                            context.pop();
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.surveySaveFailed)),
                            );
                          }
                        }
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
