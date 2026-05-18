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
  }) : super(RoadFormState(submissionId: submissionId));

  final String featureId;
  final RoadAttributesRepository attrsRepo;
  final SubmissionRepository submissionRepo;
  // US-41: fields the active form variant hides for this user/assignment.
  final Set<RoadFormField> hiddenFields;

  /// Latest geometry-derived signal for the feature this form is filling.
  /// Updated by [onGeometryChanged] whenever a reshape commit lands so
  /// skip-logic re-evaluates automatically (Issue #44).
  GeometrySignal? _geometrySignal;
  GeometrySignal? get geometrySignal => _geometrySignal;

  Timer? _debounce;
  static const _window = Duration(milliseconds: 500);

  void update(RoadFormState Function(RoadFormState) mutate) {
    // Apply field applicability after the mutation — US-6/US-7 share this
    // hook with the remaining-questions count (US-8).
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
    final s = state;
    try {
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
