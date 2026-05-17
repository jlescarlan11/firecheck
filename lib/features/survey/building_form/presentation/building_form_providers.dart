import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final submissionRepositoryProvider = Provider<SubmissionRepository>((ref) {
  return SubmissionRepository(ref.watch(appDatabaseProvider));
});

final buildingAttributesRepositoryProvider =
    Provider<BuildingAttributesRepository>((ref) {
  return BuildingAttributesRepository(ref.watch(appDatabaseProvider));
});

@immutable
class BuildingFormKey {
  const BuildingFormKey({
    required this.submissionId,
    required this.featureId,
  });
  final String submissionId;
  final String featureId;

  @override
  bool operator ==(Object other) =>
      other is BuildingFormKey &&
      other.submissionId == submissionId &&
      other.featureId == featureId;

  @override
  int get hashCode => Object.hash(submissionId, featureId);
}

final buildingFormNotifierProvider = StateNotifierProvider.autoDispose
    .family<BuildingFormNotifier, BuildingFormState, BuildingFormKey>(
  (ref, key) {
    final variant = ref.watch(currentFormVariantProvider);
    return BuildingFormNotifier(
      submissionId: key.submissionId,
      featureId: key.featureId,
      submissionRepo: ref.watch(submissionRepositoryProvider),
      attrsRepo: ref.watch(buildingAttributesRepositoryProvider),
      featureRepo: ref.watch(featureRepositoryProvider),
      hiddenFields: variant.hideBuildingFields,
    );
  },
);
