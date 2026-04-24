import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/_section_card.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

BuildingFormKey _key(String s, String f) =>
    BuildingFormKey(submissionId: s, featureId: f);

const _all = [
  ('Extinguisher', 'ffExtinguisher'),
  ('Sprinkler', 'ffSprinkler'),
  ('Hose', 'ffHose'),
  ('Smoke alarm', 'ffSmokeAlarm'),
  ('None', 'ffNone'),
];

String _ffLabel(AppLocalizations l, String key) {
  switch (key) {
    case 'ffExtinguisher':
      return l.ffExtinguisher;
    case 'ffSprinkler':
      return l.ffSprinkler;
    case 'ffHose':
      return l.ffHose;
    case 'ffSmokeAlarm':
      return l.ffSmokeAlarm;
    case 'ffNone':
      return l.ffNone;
    default:
      return key;
  }
}

class FfFacilitiesSection extends ConsumerWidget {
  const FfFacilitiesSection({
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
    final selected = state.fireFightingFacilities.toSet();

    return SectionCard(
      title: l.sectionFireFighting,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (value, labelKey) in _all)
            FilterChip(
              label: Text(_ffLabel(l, labelKey)),
              selected: selected.contains(value),
              onSelected: disabled
                  ? null
                  : (v) {
                      final next = {...selected};
                      if (value == 'None') {
                        if (v) {
                          next
                            ..clear()
                            ..add('None');
                        } else {
                          next.remove('None');
                        }
                      } else {
                        next.remove('None');
                        if (v) {
                          next.add(value);
                        } else {
                          next.remove(value);
                        }
                      }
                      notifier.update(
                        (s) =>
                            s.copyWith(fireFightingFacilities: next.toList()),
                      );
                    },
            ),
        ],
      ),
    );
  }
}
