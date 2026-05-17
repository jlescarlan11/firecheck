import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_persistent_text_field.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_section_card.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_applicability.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

RoadFormKey _key(String s, String f) =>
    RoadFormKey(submissionId: s, featureId: f);

class RoadDimensionsSection extends ConsumerWidget {
  const RoadDimensionsSection({
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
      roadFormNotifierProvider(_key(submissionId, featureId)),
    );
    final notifier = ref.read(
      roadFormNotifierProvider(_key(submissionId, featureId)).notifier,
    );

    final width = state.widthMeters;
    final showWarning = width != null && width > 30;
    final hidden = ref.watch(currentFormVariantProvider).hideRoadFields;
    if (hidden.contains(RoadFormField.widthMeters)) {
      return const SizedBox.shrink();
    }

    return SectionCard(
      title: l.sectionRoadDimensions,
      child: PersistentTextField(
        enabled: !disabled,
        value: width?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        labelText: l.fieldWidthMeters,
        helperText: showWarning ? l.widthMetersUnusual : null,
        onChanged: (v) {
          final parsed = double.tryParse(v);
          notifier.update((s) => s.copyWith(widthMeters: parsed));
        },
      ),
    );
  }
}
