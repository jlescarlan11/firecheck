import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/core/forms/required_label.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_persistent_text_field.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_section_card.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

BuildingFormKey _key(String s, String f) =>
    BuildingFormKey(submissionId: s, featureId: f);

const _ranges = [
  ('<100k', 'costRangeUnder100k'),
  ('100k–500k', 'costRange100to500k'),
  ('500k–1M', 'costRange500kto1M'),
  ('1M–5M', 'costRange1to5M'),
  ('5M–10M', 'costRange5to10M'),
  ('>10M', 'costRangeOver10M'),
];

String _rangeLabel(AppLocalizations l, String key) {
  switch (key) {
    case 'costRangeUnder100k':
      return l.costRangeUnder100k;
    case 'costRange100to500k':
      return l.costRange100to500k;
    case 'costRange500kto1M':
      return l.costRange500kto1M;
    case 'costRange1to5M':
      return l.costRange1to5M;
    case 'costRange5to10M':
      return l.costRange5to10M;
    case 'costRangeOver10M':
      return l.costRangeOver10M;
    default:
      return key;
  }
}

class CostSection extends ConsumerWidget {
  const CostSection({
    required this.submissionId,
    required this.featureId,
    required this.disabled,
    super.key,
  });

  final String submissionId;
  final String featureId;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(
      buildingFormNotifierProvider(_key(submissionId, featureId)),
    );
    final notifier = ref.read(
      buildingFormNotifierProvider(_key(submissionId, featureId)).notifier,
    );

    // The cost pair is a single toggle with two mutually-exclusive inputs;
    // hiding only one side would leave a broken radio. Variant hides take
    // effect only when BOTH costAmount and costEstimateRange are listed —
    // anything else is treated as "show cost" to keep the toggle coherent.
    final hidden = ref.watch(currentFormVariantProvider).hideBuildingFields;
    if (hidden.contains(BuildingFormField.costAmount) &&
        hidden.contains(BuildingFormField.costEstimateRange)) {
      return const SizedBox.shrink();
    }
    final reqs = ref.watch(fieldRequirementsProvider);

    return SectionCard(
      title: l.sectionCost,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            ignoring: disabled,
            child: RadioGroup<bool>(
              groupValue: state.costIsExact,
              onChanged: (v) {
                if (disabled || v == null) return;
                if (v) {
                  notifier.update(
                    (s) => s.copyWith(
                      costIsExact: true,
                      clearCostEstimateRange: true,
                    ),
                  );
                } else {
                  notifier.update(
                    (s) => s.copyWith(
                      costIsExact: false,
                      clearCostAmount: true,
                    ),
                  );
                }
              },
              child: Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool>(
                      title: Text(l.fieldCostExact),
                      value: true,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      title: Text(l.fieldCostRange),
                      value: false,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (state.costIsExact)
            PersistentTextField(
              enabled: !disabled,
              value: state.costAmount?.toString() ?? '',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              labelText: requiredLabel(
                l.fieldCostExactInput,
                reqs,
                FieldRequirementKeys.buildingCost,
              ),
              prefixText: '₱ ',
              onChanged: (v) {
                final parsed = double.tryParse(v);
                notifier.update((s) => s.copyWith(costAmount: parsed));
              },
            )
          else
            DropdownButtonFormField<String>(
              initialValue: state.costEstimateRange,
              decoration: InputDecoration(
                labelText: requiredLabel(
                  l.fieldCostRangeInput,
                  reqs,
                  FieldRequirementKeys.buildingCost,
                ),
              ),
              items: [
                for (final (code, labelKey) in _ranges)
                  DropdownMenuItem<String>(
                    value: code,
                    child: Text(_rangeLabel(l, labelKey)),
                  ),
              ],
              onChanged: disabled
                  ? null
                  : (v) {
                      if (v == null) return;
                      notifier.update(
                        (s) => s.copyWith(costEstimateRange: v),
                      );
                    },
            ),
        ],
      ),
    );
  }
}
