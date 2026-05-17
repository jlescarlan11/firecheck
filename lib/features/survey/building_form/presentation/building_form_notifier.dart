import 'dart:async';

import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BuildingFormNotifier extends StateNotifier<BuildingFormState> {
  BuildingFormNotifier({
    required this.submissionId,
    required this.featureId,
    required this.submissionRepo,
    required this.attrsRepo,
    required this.featureRepo,
    this.hiddenFields = const {},
  }) : super(BuildingFormState(submissionId: submissionId)) {
    _loadInitial();
  }

  /// Latest geometry-derived signal for the feature this form is filling.
  /// Updated by [onGeometryChanged] whenever a reshape commit lands; routed
  /// through to [applyApplicability] so skip-logic re-evaluates without the
  /// user re-opening the form (Issue #44).
  GeometrySignal? _geometrySignal;
  GeometrySignal? get geometrySignal => _geometrySignal;

  final String submissionId;
  final String featureId;
  final SubmissionRepository submissionRepo;
  final BuildingAttributesRepository attrsRepo;
  final FeatureRepository featureRepo;
  // US-41: fields the active form variant hides for this user/assignment.
  // Passed through to applyApplicability / remainingQuestionCount so the
  // form behaves as if the hidden fields don't exist.
  final Set<BuildingFormField> hiddenFields;

  Timer? _debounce;
  static const _window = Duration(milliseconds: 500);

  Future<void> _loadInitial() async {
    final attrs = await attrsRepo.watchForSubmission(submissionId).first;
    if (attrs == null) return;
    state = BuildingFormState(
      submissionId: submissionId,
      cbmsId: attrs.cbmsId,
      buildingName: attrs.buildingName,
      ra9514Type: attrs.ra9514Type,
      storeys: attrs.storeys,
      material: attrs.material,
      costIsExact: attrs.costIsExact,
      costAmount: attrs.costAmount,
      costEstimateRange: attrs.costEstimateRange,
      fireFightingFacilities: BuildingAttributesRepository.decodeStringList(
        attrs.fireFightingFacilitiesJson,
      ),
      fireLoad: BuildingAttributesRepository.decodeStringList(
        attrs.fireLoadJson,
      ),
    );
  }

  void update(BuildingFormState Function(BuildingFormState) mutate) {
    // Sweep inapplicable fields after every mutation so a field that became
    // non-applicable (e.g. cost-range when the user just switched to exact)
    // can't carry a stale value into the database (US-7). Visibility (US-6)
    // and the remaining-questions count (US-8) read the same predicate.
    state = applyApplicability(
      mutate(state),
      hidden: hiddenFields,
      geometry: _geometrySignal,
    );
    _debounce?.cancel();
    _debounce = Timer(_window, _flush);
  }

  /// Called when the feature's geometry changes (e.g. reshape commit).
  /// Re-runs applicability against the current form state so any
  /// geometry-dependent skip rule clears or surfaces the affected field
  /// without waiting for the next field edit (Issue #44).
  void onGeometryChanged(GeometrySignal signal) {
    if (signal == _geometrySignal) return;
    _geometrySignal = signal;
    state = applyApplicability(
      state,
      hidden: hiddenFields,
      geometry: signal,
    );
  }

  /// For external triggers (e.g. Done button) that need to wait for the
  /// pending write to land.
  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }

  Future<void> _flush() async {
    // Snapshot state into a local before any await. After the notifier is
    // disposed, even reading `state` throws (state_notifier's debug guard),
    // and dispose() invokes an unawaited _flush() that would otherwise crash
    // mid-write — leaving the feature's status stale and the polygon stuck
    // red on the map. Matches the pattern RoadFormNotifier already uses.
    final s = state;
    try {
      await attrsRepo.upsertForSubmission(
        submissionId: s.submissionId,
        cbmsId: s.cbmsId,
        buildingName: s.buildingName,
        ra9514Type: s.ra9514Type,
        storeys: s.storeys,
        material: s.material,
        costIsExact: s.costIsExact,
        costAmount: s.costAmount,
        costEstimateRange: s.costEstimateRange,
        fireFightingFacilities: s.fireFightingFacilities,
        fireLoad: s.fireLoad,
      );
      await submissionRepo.updateDoesNotExist(
        s.submissionId,
        doesNotExist: s.doesNotExist,
      );
      await featureRepo.markFeatureStatus(featureId);
    } catch (_) {
      // Silently ignore flush errors (e.g. DB already closed during teardown).
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Best-effort flush on dispose; we deliberately don't await — the
    // notifier is being torn down.
    unawaited(_flush());
    super.dispose();
  }
}
