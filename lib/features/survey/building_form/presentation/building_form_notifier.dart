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
    _latestState = state;
    _initialLoad = _loadInitial();
    // Explicit flushes retain the load error. An abandoned screen must not
    // report an unhandled asynchronous error after its notifier is disposed.
    unawaited(_initialLoad.catchError((Object _) {}));
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
  // Fields the active form variant hides for this user/assignment. Passed
  // through to applyApplicability / remainingQuestionCount so the form
  // behaves as if the hidden fields don't exist.
  final Set<BuildingFormField> hiddenFields;

  Timer? _debounce;
  static const _window = Duration(milliseconds: 500);
  late final Future<void> _initialLoad;
  late BuildingFormState _latestState;
  final _earlyEdits = <BuildingFormState Function(BuildingFormState)>[];
  bool _hydrated = false;
  int _editRevision = 0;
  int _persistedRevision = 0;
  Future<void> _writes = Future.value();

  Future<void> _loadInitial() async {
    final (attrs, submission) = await (
      attrsRepo.watchForSubmission(submissionId).first,
      submissionRepo.findById(submissionId),
    ).wait;
    _latestState = BuildingFormState(
      submissionId: submissionId,
      cbmsId: attrs?.cbmsId,
      buildingName: attrs?.buildingName,
      ra9514Type: attrs?.ra9514Type,
      storeys: attrs?.storeys,
      material: attrs?.material,
      costIsExact: attrs?.costIsExact ?? false,
      costAmount: attrs?.costAmount,
      costEstimateRange: attrs?.costEstimateRange,
      fireFightingFacilities: BuildingAttributesRepository.decodeStringList(
        attrs?.fireFightingFacilitiesJson ?? '[]',
      ),
      fireLoad: BuildingAttributesRepository.decodeStringList(
        attrs?.fireLoadJson ?? '[]',
      ),
      doesNotExist: submission?.doesNotExist ?? false,
      overrideReason: submission?.overrideReason,
    );
    // Defer early transformations instead of merging with constructor defaults:
    // explicit false/empty edits must win, and each transformation runs once.
    for (final edit in _earlyEdits) {
      _applyEdit(edit);
    }
    _earlyEdits.clear();
    _hydrated = true;
    if (mounted) state = _latestState;
  }

  void update(BuildingFormState Function(BuildingFormState) mutate) {
    if (!mounted) return;
    // Sweep inapplicable fields after every mutation so a field that became
    // non-applicable (e.g. cost-range when the user just switched to exact)
    // can't carry a stale value into the database. Visibility and the
    // remaining-questions count read the same predicate.
    _editRevision++;
    if (_hydrated) {
      _applyEdit(mutate);
      if (mounted) state = _latestState;
    } else {
      _earlyEdits.add(mutate);
    }
    _debounce?.cancel();
    _debounce = Timer(_window, _flushQuietly);
  }

  void _applyEdit(BuildingFormState Function(BuildingFormState) mutate) {
    _latestState = applyApplicability(
      mutate(_latestState),
      hidden: hiddenFields,
      geometry: _geometrySignal,
    );
  }

  /// Called when the feature's geometry changes (e.g. reshape commit).
  /// Re-runs applicability against the current form state so any
  /// geometry-dependent skip rule clears or surfaces the affected field
  /// without waiting for the next field edit (Issue #44).
  void onGeometryChanged(GeometrySignal signal) {
    if (!mounted) return;
    if (signal == _geometrySignal) return;
    _geometrySignal = signal;
    if (!_hydrated) return;
    _latestState = applyApplicability(
      _latestState,
      hidden: hiddenFields,
      geometry: signal,
    );
    if (mounted) state = _latestState;
  }

  /// For external triggers (e.g. Done button) that need to wait for the
  /// pending write to land.
  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }

  Future<void> _flush() {
    final next = _writes.then((_) => _persistPendingEdits());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _persistPendingEdits() async {
    await _initialLoad;
    if (_editRevision == _persistedRevision) return;
    final revision = _editRevision;
    await _persist(_latestState);
    _persistedRevision = revision;
  }

  void _flushQuietly() {
    // Keep failed edits pending for a later explicit flush/retry. Completion
    // awaits flushNow, which propagates failures instead of claiming success.
    unawaited(_flush().catchError((Object _) {}));
  }

  Future<void> _persist(BuildingFormState s) async {
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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_editRevision != _persistedRevision) _flushQuietly();
    super.dispose();
  }
}
