import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/road_form/data/road_attributes_repository.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final roadAttributesRepositoryProvider =
    Provider<RoadAttributesRepository>((ref) {
  return RoadAttributesRepository(ref.watch(appDatabaseProvider));
});

@immutable
class RoadFormKey {
  const RoadFormKey({required this.submissionId, required this.featureId});
  final String submissionId;
  final String featureId;

  @override
  bool operator ==(Object other) =>
      other is RoadFormKey &&
      other.submissionId == submissionId &&
      other.featureId == featureId;

  @override
  int get hashCode => Object.hash(submissionId, featureId);
}

final roadFormNotifierProvider = StateNotifierProvider.autoDispose
    .family<RoadFormNotifier, RoadFormState, RoadFormKey>((ref, key) {
  final variant = ref.watch(currentFormVariantProvider);
  return RoadFormNotifier(
    submissionId: key.submissionId,
    featureId: key.featureId,
    attrsRepo: ref.watch(roadAttributesRepositoryProvider),
    submissionRepo: ref.watch(submissionRepositoryProvider),
    hiddenFields: variant.hideRoadFields,
  );
});
