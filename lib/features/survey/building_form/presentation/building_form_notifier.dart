import 'dart:async';

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
  }) : super(BuildingFormState(submissionId: submissionId)) {
    _loadInitial();
  }

  final String submissionId;
  final String featureId;
  final SubmissionRepository submissionRepo;
  final BuildingAttributesRepository attrsRepo;
  final FeatureRepository featureRepo;

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
    state = applyApplicability(mutate(state));
    _debounce?.cancel();
    _debounce = Timer(_window, _flush);
  }

  /// For external triggers (e.g. Done button) that need to wait for the
  /// pending write to land.
  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }

  Future<void> _flush() async {
    await attrsRepo.upsertForSubmission(
      submissionId: state.submissionId,
      cbmsId: state.cbmsId,
      buildingName: state.buildingName,
      ra9514Type: state.ra9514Type,
      storeys: state.storeys,
      material: state.material,
      costIsExact: state.costIsExact,
      costAmount: state.costAmount,
      costEstimateRange: state.costEstimateRange,
      fireFightingFacilities: state.fireFightingFacilities,
      fireLoad: state.fireLoad,
    );
    await submissionRepo.updateDoesNotExist(
      state.submissionId,
      doesNotExist: state.doesNotExist,
    );
    await featureRepo.markFeatureStatus(featureId);
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
