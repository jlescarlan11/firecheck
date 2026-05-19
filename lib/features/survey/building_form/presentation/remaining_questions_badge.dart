// Shows how many applicable fields on the enumerator's current path still
// need an answer. Hides itself when the "does not exist" toggle is on (no
// applicable fields remain to count).
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BuildingRemainingQuestionsBadge extends ConsumerWidget {
  const BuildingRemainingQuestionsBadge({
    required this.submissionId,
    required this.featureId,
    super.key,
  });
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      buildingFormNotifierProvider(
        BuildingFormKey(submissionId: submissionId, featureId: featureId),
      ),
    );
    if (state.doesNotExist) return const SizedBox.shrink();
    final variant = ref.watch(currentFormVariantProvider);
    final reqs = ref.watch(fieldRequirementsProvider);
    return RemainingQuestionsChip(
      remaining: remainingQuestionCount(
        state,
        hidden: variant.hideBuildingFields,
        requirements: reqs,
      ),
    );
  }
}

class RemainingQuestionsChip extends StatelessWidget {
  const RemainingQuestionsChip({required this.remaining, super.key});
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final allDone = remaining == 0;
    return Container(
      key: const Key('form.remainingQuestionsBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: allDone ? const Color(0xFFE9F7EF) : const Color(0xFFEFF4FA),
        border: Border.all(
          color: allDone ? const Color(0xFF6CC080) : const Color(0xFFB7C7DC),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            allDone ? Icons.check_circle : Icons.help_outline,
            size: 18,
            color: allDone ? const Color(0xFF2F855A) : const Color(0xFF2B6CB0),
          ),
          const SizedBox(width: 8),
          Text(
            allDone
                ? l.remainingQuestionsAllDone
                : l.remainingQuestionsRemaining(remaining),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
