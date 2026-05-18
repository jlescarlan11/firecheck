import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/core/forms/required_label.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_section_card.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

BuildingFormKey _key(String s, String f) =>
    BuildingFormKey(submissionId: s, featureId: f);

const _all = [
  ('Wood furniture', 'fireLoadWoodFurniture'),
  ('Fabric', 'fireLoadFabric'),
  ('Paper', 'fireLoadPaper'),
  ('Chemicals', 'fireLoadChemicals'),
  ('Cooking gas', 'fireLoadCookingGas'),
  ('Other', 'fireLoadOther'),
];

String _fireLoadLabel(AppLocalizations l, String key) {
  switch (key) {
    case 'fireLoadWoodFurniture':
      return l.fireLoadWoodFurniture;
    case 'fireLoadFabric':
      return l.fireLoadFabric;
    case 'fireLoadPaper':
      return l.fireLoadPaper;
    case 'fireLoadChemicals':
      return l.fireLoadChemicals;
    case 'fireLoadCookingGas':
      return l.fireLoadCookingGas;
    case 'fireLoadOther':
      return l.fireLoadOther;
    default:
      return key;
  }
}

class FireLoadSection extends ConsumerWidget {
  const FireLoadSection({
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
    final state = ref.watch(buildingFormNotifierProvider(
      _key(submissionId, featureId),
    ),);
    final notifier = ref.read(
      buildingFormNotifierProvider(_key(submissionId, featureId)).notifier,
    );
    final selected = state.fireLoad.toSet();
    final hidden = ref.watch(currentFormVariantProvider).hideBuildingFields;
    if (hidden.contains(BuildingFormField.fireLoad)) {
      return const SizedBox.shrink();
    }
    final reqs = ref.watch(fieldRequirementsProvider);

    return SectionCard(
      title: requiredLabel(
        l.sectionFireLoad,
        reqs,
        FieldRequirementKeys.buildingFireLoad,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (value, labelKey) in _all)
            FilterChip(
              label: Text(_fireLoadLabel(l, labelKey)),
              selected: selected.contains(value),
              onSelected: disabled
                  ? null
                  : (v) {
                      final next = {...selected};
                      if (v) {
                        next.add(value);
                      } else {
                        next.remove(value);
                      }
                      notifier.update(
                        (s) => s.copyWith(fireLoad: next.toList()),
                      );
                    },
            ),
        ],
      ),
    );
  }
}
