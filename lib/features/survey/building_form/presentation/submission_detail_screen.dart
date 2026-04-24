import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_validator.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_tabs.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip.dart';
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
    final submissions = await repo
        .watchSubmissionsForFeature(widget.featureId)
        .first;
    if (mounted) setState(() => _activeIndex = submissions.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final submissionsAsync =
        ref.watch(_submissionsForFeatureProvider(widget.featureId));

    return Scaffold(
      appBar: AppBar(title: Text(l.submissionDetailTitleBuilding)),
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
                child: BuildingForm(
                  submissionId: active.id,
                  featureId: widget.featureId,
                ),
              ),
              _Footer(
                submissionId: active.id,
                featureId: widget.featureId,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.submissionId, required this.featureId});
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key = BuildingFormKey(
      submissionId: submissionId,
      featureId: featureId,
    );
    final state = ref.watch(buildingFormNotifierProvider(key));
    final notifier = ref.read(buildingFormNotifierProvider(key).notifier);
    final photoCountAsync = ref.watch(_photoCountProvider(submissionId));

    return photoCountAsync.when(
      loading: () => const SizedBox(height: 56),
      error: (_, __) => const SizedBox(height: 56),
      data: (photoCount) {
        final result = validateBuildingForm(state, photoCount);
        final ready = result.isComplete;
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
                        await notifier.flushNow();
                        await ref
                            .read(submissionRepositoryProvider)
                            .markStatus(submissionId, 'ready_to_upload');
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
