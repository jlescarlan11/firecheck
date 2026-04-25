import 'package:firecheck/features/survey/building_form/presentation/sections/_persistent_text_field.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_section_card.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

RoadFormKey _key(String s, String f) =>
    RoadFormKey(submissionId: s, featureId: f);

const _features = [
  ('vendor', 'roadFeatureVendor'),
  ('pedestrian', 'roadFeaturePedestrian'),
  ('parking', 'roadFeatureParking'),
  ('others', 'roadFeatureOthers'),
];

String _featureLabel(AppLocalizations l, String key) {
  switch (key) {
    case 'roadFeatureVendor':
      return l.roadFeatureVendor;
    case 'roadFeaturePedestrian':
      return l.roadFeaturePedestrian;
    case 'roadFeatureParking':
      return l.roadFeatureParking;
    case 'roadFeatureOthers':
      return l.roadFeatureOthers;
    default:
      return key;
  }
}

class RoadFeaturesSection extends ConsumerWidget {
  const RoadFeaturesSection({
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

    final selected = state.roadFeatures;
    final hasOthers = selected.contains('others');

    return SectionCard(
      title: l.sectionRoadFeatures,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (code, labelKey) in _features)
            CheckboxListTile(
              title: Text(_featureLabel(l, labelKey)),
              value: selected.contains(code),
              onChanged: disabled
                  ? null
                  : (v) {
                      final next = [...selected];
                      if (v ?? false) {
                        if (!next.contains(code)) next.add(code);
                      } else {
                        next.remove(code);
                      }
                      notifier.update((s) {
                        if (code == 'others' && !(v ?? false)) {
                          return s.copyWith(
                            roadFeatures: next,
                            clearOthersDescription: true,
                          );
                        }
                        return s.copyWith(roadFeatures: next);
                      });
                    },
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          if (hasOthers) ...[
            const SizedBox(height: 8),
            PersistentTextField(
              enabled: !disabled,
              value: state.othersDescription ?? '',
              labelText: l.roadFeatureOthersDescription,
              onChanged: (v) => notifier.update(
                (s) => s.copyWith(othersDescription: v),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
