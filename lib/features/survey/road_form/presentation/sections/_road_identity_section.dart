import 'package:firecheck/features/survey/building_form/presentation/sections/_persistent_text_field.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_section_card.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

RoadFormKey _key(String s, String f) =>
    RoadFormKey(submissionId: s, featureId: f);

class RoadIdentitySection extends ConsumerWidget {
  const RoadIdentitySection({
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

    return SectionCard(
      title: l.sectionRoadIdentity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersistentTextField(
            enabled: !disabled,
            value: state.roadName ?? '',
            labelText: l.fieldRoadName,
            onChanged: (v) => notifier.update(
              (s) => s.copyWith(roadName: v),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(l.fieldIsBridge),
            value: state.isBridge,
            onChanged: disabled
                ? null
                : (v) => notifier.update((s) => s.copyWith(isBridge: v)),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
