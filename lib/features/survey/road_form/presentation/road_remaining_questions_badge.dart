// lib/features/survey/road_form/presentation/road_remaining_questions_badge.dart
//
// US-8 (road variant): shows applicable-but-unanswered count for the road
// form. Shares the chip widget with the building variant for visual parity.
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/remaining_questions_badge.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_applicability.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoadRemainingQuestionsBadge extends ConsumerWidget {
  const RoadRemainingQuestionsBadge({
    required this.submissionId,
    required this.featureId,
    super.key,
  });
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      roadFormNotifierProvider(
        RoadFormKey(submissionId: submissionId, featureId: featureId),
      ),
    );
    if (state.doesNotExist) return const SizedBox.shrink();
    final variant = ref.watch(currentFormVariantProvider);
    return RemainingQuestionsChip(
      remaining: remainingQuestionCount(
        state,
        hidden: variant.hideRoadFields,
      ),
    );
  }
}
