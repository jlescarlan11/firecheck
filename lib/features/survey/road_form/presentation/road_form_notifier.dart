import 'dart:async';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/road_form/data/road_attributes_repository.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_applicability.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoadFormNotifier extends StateNotifier<RoadFormState> {
  RoadFormNotifier({
    required String submissionId,
    required this.featureId,
    required this.attrsRepo,
    required this.submissionRepo,
    this.hiddenFields = const {},
  }) : super(RoadFormState(submissionId: submissionId)) {
    _initialLoad = _loadInitial();
  }

  final String featureId;
  final RoadAttributesRepository attrsRepo;
  final SubmissionRepository submissionRepo;
  // Fields the active form variant hides for this user/assignment.
  final Set<RoadFormField> hiddenFields;

  /// Latest geometry-derived signal for the feature this form is filling.
  /// Updated by [onGeometryChanged] whenever a reshape commit lands so
  /// skip-logic re-evaluates automatically.
  GeometrySignal? _geometrySignal;
  GeometrySignal? get geometrySignal => _geometrySignal;

  Timer? _debounce;
  static const _window = Duration(milliseconds: 500);
  late final Future<void> _initialLoad;

  Future<void> _loadInitial() async {
    final submissionId = state.submissionId;
    final attrs = await attrsRepo.findBySubmission(submissionId);
    final submission = await submissionRepo.findById(submissionId);
    if (!mounted) return;

    // Preserve any edit made during the short async hydration window while
    // filling untouched fields from the durable row. This also prevents a
    // later flush from replacing persisted values with the notifier's blank
    // constructor defaults.
    final current = state;
    final hydrated = RoadFormState(
      submissionId: current.submissionId,
      isBridge: current.isBridge || (attrs?.isBridge ?? false),
      roadName: current.roadName ?? attrs?.roadName,
      widthMeters: current.widthMeters ?? attrs?.widthMeters,
      roadFeatures: current.roadFeatures.isNotEmpty
          ? current.roadFeatures
          : attrs == null
              ? const []
              : RoadAttributesRepository.decodeStringList(
                  attrs.roadFeaturesJson,
                ),
      othersDescription: current.othersDescription ?? attrs?.othersDescription,
      doesNotExist: current.doesNotExist || (submission?.doesNotExist ?? false),
    );
    state = applyApplicability(
      hydrated,
      hidden: hiddenFields,
      geometry: _geometrySignal,
    );
  }

  void update(RoadFormState Function(RoadFormState) mutate) {
    // Apply field applicability after the mutation — field visibility and
    // auto-clear share this hook with the remaining-questions count.
    state = applyApplicability(
      mutate(state),
      hidden: hiddenFields,
      geometry: _geometrySignal,
    );
    _debounce?.cancel();
    _debounce = Timer(_window, _flush);
  }

  void onGeometryChanged(GeometrySignal signal) {
    if (signal == _geometrySignal) return;
    _geometrySignal = signal;
    state = applyApplicability(
      state,
      hidden: hiddenFields,
      geometry: signal,
    );
  }

  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }

  Future<void> _flush() async {
    try {
      await _initialLoad;
      if (!mounted) return;
      final s = state;
      await submissionRepo.updateDoesNotExist(
        s.submissionId,
        doesNotExist: s.doesNotExist,
      );
      if (s.doesNotExist) return;
      await attrsRepo.upsertForSubmission(
        s.submissionId,
        RoadAttributesCompanion.insert(
          submissionId: s.submissionId,
          isBridge: Value(s.isBridge),
          roadName: Value(s.roadName),
          widthMeters: Value(s.widthMeters),
          roadFeaturesJson:
              Value(RoadAttributesRepository.encodeStringList(s.roadFeatures)),
          othersDescription: Value(s.othersDescription),
        ),
      );
    } catch (_) {
      // Silently ignore flush errors (e.g. DB already closed during teardown).
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Best-effort flush on dispose; deliberately not awaited.
    unawaited(_flush());
    super.dispose();
  }
}
