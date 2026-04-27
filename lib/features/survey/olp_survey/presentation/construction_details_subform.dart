import 'package:firecheck/features/survey/building_form/presentation/sections/_persistent_text_field.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConstructionDetailsSubform extends ConsumerWidget {
  const ConstructionDetailsSubform({
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key =
        OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final notifier = ref.read(olpSectionNotifierProvider(key).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.olpSectionA,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        for (final element in OlpRubric.constructionElements)
          _ElementRow(
            element: element,
            elementLabel: _elementLabel(l, element),
            current: state.constructionDetails[element]?.material,
            currentOther: state.constructionDetails[element]?.materialOther,
            onMaterialChanged: (mat) {
              if (mat == null) return;
              notifier.setMaterial(element, mat);
            },
            onOtherChanged: (txt) {
              notifier.setMaterial(element, 'others', other: txt);
            },
          ),
      ],
    );
  }

  String _elementLabel(AppLocalizations l, String element) {
    switch (element) {
      case 'roof':
        return l.olpElementRoof;
      case 'ceiling':
        return l.olpElementCeiling;
      case 'roomPartitions':
        return l.olpElementRoomPartitions;
      case 'trusses':
        return l.olpElementTrusses;
      case 'windows':
        return l.olpElementWindows;
      case 'corridorWalls':
        return l.olpElementCorridorWalls;
      case 'columns':
        return l.olpElementColumns;
      case 'mainDoor':
        return l.olpElementMainDoor;
      case 'exteriorWall':
        return l.olpElementExteriorWall;
      case 'beams':
        return l.olpElementBeams;
      default:
        return element;
    }
  }
}

class _ElementRow extends StatelessWidget {
  const _ElementRow({
    required this.element,
    required this.elementLabel,
    required this.current,
    required this.currentOther,
    required this.onMaterialChanged,
    required this.onOtherChanged,
  });

  final String element;
  final String elementLabel;
  final String? current;
  final String? currentOther;
  final ValueChanged<String?> onMaterialChanged;
  final ValueChanged<String> onOtherChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(elementLabel, style: const TextStyle(fontSize: 12)),
          Wrap(
            spacing: 8,
            children: [
              for (final m in OlpRubric.materials)
                ChoiceChip(
                  label: Text(_materialLabel(l, m)),
                  selected: current == m,
                  onSelected: (sel) {
                    if (sel) onMaterialChanged(m);
                  },
                ),
            ],
          ),
          if (current == 'others') ...[
            const SizedBox(height: 4),
            PersistentTextField(
              value: currentOther ?? '',
              labelText: l.olpMaterialOthersHint,
              onChanged: onOtherChanged,
            ),
          ],
        ],
      ),
    );
  }

  String _materialLabel(AppLocalizations l, String code) {
    switch (code) {
      case 'kahoy':
        return l.olpMaterialKahoy;
      case 'semento':
        return l.olpMaterialSemento;
      case 'bakal':
        return l.olpMaterialBakal;
      case 'others':
        return l.olpMaterialOthers;
      default:
        return code;
    }
  }
}
