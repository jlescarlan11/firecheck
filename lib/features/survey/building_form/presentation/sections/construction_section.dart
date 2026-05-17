import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_persistent_text_field.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_section_card.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

BuildingFormKey _key(String s, String f) =>
    BuildingFormKey(submissionId: s, featureId: f);

const _materials = [
  ('Concrete', 'materialConcrete'),
  ('Wood', 'materialWood'),
  ('Mixed', 'materialMixed'),
  ('Light', 'materialLight'),
  ('Steel', 'materialSteel'),
  ('Other', 'materialOther'),
];

String _materialLabel(AppLocalizations l, String key) {
  switch (key) {
    case 'materialConcrete':
      return l.materialConcrete;
    case 'materialWood':
      return l.materialWood;
    case 'materialMixed':
      return l.materialMixed;
    case 'materialLight':
      return l.materialLight;
    case 'materialSteel':
      return l.materialSteel;
    case 'materialOther':
      return l.materialOther;
    default:
      return key;
  }
}

class ConstructionSection extends ConsumerWidget {
  const ConstructionSection({
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

    final storeys = state.storeys;
    final showWarning = storeys != null && storeys > 50;
    final hidden = ref.watch(currentFormVariantProvider).hideBuildingFields;
    bool show(BuildingFormField f) => !hidden.contains(f);

    final children = <Widget>[];
    if (show(BuildingFormField.storeys)) {
      children.add(
        PersistentTextField(
          enabled: !disabled,
          value: storeys?.toString() ?? '',
          keyboardType: TextInputType.number,
          labelText: l.fieldStoreys,
          helperText: showWarning ? l.storeysWarningTooTall : null,
          onChanged: (v) {
            final parsed = int.tryParse(v);
            notifier.update((s) => s.copyWith(storeys: parsed));
          },
        ),
      );
    }
    if (show(BuildingFormField.material)) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        DropdownButtonFormField<String>(
          initialValue: state.material,
          decoration: InputDecoration(labelText: l.fieldMaterial),
          items: [
            for (final (code, labelKey) in _materials)
              DropdownMenuItem<String>(
                value: code,
                child: Text(_materialLabel(l, labelKey)),
              ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v == null) return;
                  notifier.update((s) => s.copyWith(material: v));
                },
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      title: l.sectionConstruction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
