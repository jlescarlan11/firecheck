import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/core/forms/required_label.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/domain/ra_9514_fallback.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_persistent_text_field.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_section_card.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

BuildingFormKey _key(String s, String f) =>
    BuildingFormKey(submissionId: s, featureId: f);

String _ra9514Label(AppLocalizations l, String key) {
  switch (key) {
    case 'ra9514GroupA':
      return l.ra9514GroupA;
    case 'ra9514GroupB':
      return l.ra9514GroupB;
    case 'ra9514GroupC':
      return l.ra9514GroupC;
    case 'ra9514GroupD':
      return l.ra9514GroupD;
    case 'ra9514GroupE':
      return l.ra9514GroupE;
    case 'ra9514GroupF':
      return l.ra9514GroupF;
    case 'ra9514GroupG':
      return l.ra9514GroupG;
    case 'ra9514GroupH':
      return l.ra9514GroupH;
    case 'ra9514GroupI':
      return l.ra9514GroupI;
    case 'ra9514GroupJ':
      return l.ra9514GroupJ;
    default:
      return key;
  }
}

class IdentitySection extends ConsumerWidget {
  const IdentitySection({
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
    final hidden = ref.watch(currentFormVariantProvider).hideBuildingFields;
    final reqs = ref.watch(fieldRequirementsProvider);
    bool show(BuildingFormField f) => !hidden.contains(f);

    final children = <Widget>[];
    if (show(BuildingFormField.cbmsId)) {
      children.add(
        PersistentTextField(
          enabled: !disabled,
          value: state.cbmsId ?? '',
          labelText: l.fieldCbmsId,
          onChanged: (v) => notifier.update(
            (s) => s.copyWith(cbmsId: v),
          ),
        ),
      );
    }
    if (show(BuildingFormField.buildingName)) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        PersistentTextField(
          enabled: !disabled,
          value: state.buildingName ?? '',
          labelText: requiredLabel(
            l.fieldBuildingName,
            reqs,
            FieldRequirementKeys.buildingName,
          ),
          onChanged: (v) => notifier.update(
            (s) => s.copyWith(buildingName: v),
          ),
        ),
      );
    }
    if (show(BuildingFormField.ra9514Type)) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        DropdownButtonFormField<String>(
          initialValue: state.ra9514Type,
          decoration: InputDecoration(
            labelText: requiredLabel(
              l.fieldRa9514Type,
              reqs,
              FieldRequirementKeys.buildingRa9514Type,
            ),
          ),
          items: [
            for (final entry in ra9514Fallback)
              DropdownMenuItem<String>(
                value: entry.code,
                child: Text(
                  '${entry.code} — ${_ra9514Label(l, entry.labelKey)}',
                ),
              ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v == null) return;
                  notifier.update((s) => s.copyWith(ra9514Type: v));
                },
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      title: l.sectionIdentity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
