import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScoredSectionWidget extends ConsumerWidget {
  const ScoredSectionWidget({
    required this.section,
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final OlpSection section;
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key =
        OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final notifier = ref.read(olpSectionNotifierProvider(key).notifier);
    final items = OlpRubric.items.where((i) => i.section == section).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _sectionLabel(l, section),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        for (final item in items)
          CheckboxListTile(
            key: Key('olp.item.${item.code}'),
            title: Text(resolveOlpKey(l, item.statementKey)),
            value: state.checkedCodes.contains(item.code),
            onChanged: (_) => notifier.toggleItem(item.code),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
      ],
    );
  }

  String _sectionLabel(AppLocalizations l, OlpSection s) {
    switch (s) {
      case OlpSection.b:
        return l.olpSectionB;
      case OlpSection.c:
        return l.olpSectionC;
      case OlpSection.d:
        return l.olpSectionD;
      case OlpSection.e:
        return l.olpSectionE;
    }
  }
}

/// Resolves an OLP item statement or suggestion ARB key by name. The 70
/// per-item keys are too many to inline as a switch elsewhere, so this helper
/// is reused here + in the result-screen suggestions list.
String resolveOlpKey(AppLocalizations l, String key) {
  switch (key) {
    case 'olpItemB01Statement':
      return l.olpItemB01Statement;
    case 'olpItemB02Statement':
      return l.olpItemB02Statement;
    case 'olpItemB03Statement':
      return l.olpItemB03Statement;
    case 'olpItemB04Statement':
      return l.olpItemB04Statement;
    case 'olpItemB05Statement':
      return l.olpItemB05Statement;
    case 'olpItemB06Statement':
      return l.olpItemB06Statement;
    case 'olpItemB07Statement':
      return l.olpItemB07Statement;
    case 'olpItemB08Statement':
      return l.olpItemB08Statement;
    case 'olpItemB09Statement':
      return l.olpItemB09Statement;
    case 'olpItemB10Statement':
      return l.olpItemB10Statement;
    case 'olpItemB11Statement':
      return l.olpItemB11Statement;
    case 'olpItemB12Statement':
      return l.olpItemB12Statement;
    case 'olpItemB13Statement':
      return l.olpItemB13Statement;
    case 'olpItemB14Statement':
      return l.olpItemB14Statement;
    case 'olpItemB15Statement':
      return l.olpItemB15Statement;
    case 'olpItemC10Statement':
      return l.olpItemC10Statement;
    case 'olpItemC11Statement':
      return l.olpItemC11Statement;
    case 'olpItemC12Statement':
      return l.olpItemC12Statement;
    case 'olpItemC13Statement':
      return l.olpItemC13Statement;
    case 'olpItemC14Statement':
      return l.olpItemC14Statement;
    case 'olpItemC15Statement':
      return l.olpItemC15Statement;
    case 'olpItemC16Statement':
      return l.olpItemC16Statement;
    case 'olpItemC17Statement':
      return l.olpItemC17Statement;
    case 'olpItemC18Statement':
      return l.olpItemC18Statement;
    case 'olpItemD25Statement':
      return l.olpItemD25Statement;
    case 'olpItemD26Statement':
      return l.olpItemD26Statement;
    case 'olpItemD27Statement':
      return l.olpItemD27Statement;
    case 'olpItemD28Statement':
      return l.olpItemD28Statement;
    case 'olpItemD29Statement':
      return l.olpItemD29Statement;
    case 'olpItemE30Statement':
      return l.olpItemE30Statement;
    case 'olpItemE31Statement':
      return l.olpItemE31Statement;
    case 'olpItemE32Statement':
      return l.olpItemE32Statement;
    case 'olpItemE33Statement':
      return l.olpItemE33Statement;
    case 'olpItemE34Statement':
      return l.olpItemE34Statement;
    case 'olpItemE35Statement':
      return l.olpItemE35Statement;
    case 'olpItemB01Suggestion':
      return l.olpItemB01Suggestion;
    case 'olpItemB02Suggestion':
      return l.olpItemB02Suggestion;
    case 'olpItemB03Suggestion':
      return l.olpItemB03Suggestion;
    case 'olpItemB04Suggestion':
      return l.olpItemB04Suggestion;
    case 'olpItemB05Suggestion':
      return l.olpItemB05Suggestion;
    case 'olpItemB06Suggestion':
      return l.olpItemB06Suggestion;
    case 'olpItemB07Suggestion':
      return l.olpItemB07Suggestion;
    case 'olpItemB08Suggestion':
      return l.olpItemB08Suggestion;
    case 'olpItemB09Suggestion':
      return l.olpItemB09Suggestion;
    case 'olpItemB10Suggestion':
      return l.olpItemB10Suggestion;
    case 'olpItemB11Suggestion':
      return l.olpItemB11Suggestion;
    case 'olpItemB12Suggestion':
      return l.olpItemB12Suggestion;
    case 'olpItemB13Suggestion':
      return l.olpItemB13Suggestion;
    case 'olpItemB14Suggestion':
      return l.olpItemB14Suggestion;
    case 'olpItemB15Suggestion':
      return l.olpItemB15Suggestion;
    case 'olpItemC10Suggestion':
      return l.olpItemC10Suggestion;
    case 'olpItemC11Suggestion':
      return l.olpItemC11Suggestion;
    case 'olpItemC12Suggestion':
      return l.olpItemC12Suggestion;
    case 'olpItemC13Suggestion':
      return l.olpItemC13Suggestion;
    case 'olpItemC14Suggestion':
      return l.olpItemC14Suggestion;
    case 'olpItemC15Suggestion':
      return l.olpItemC15Suggestion;
    case 'olpItemC16Suggestion':
      return l.olpItemC16Suggestion;
    case 'olpItemC17Suggestion':
      return l.olpItemC17Suggestion;
    case 'olpItemC18Suggestion':
      return l.olpItemC18Suggestion;
    case 'olpItemD25Suggestion':
      return l.olpItemD25Suggestion;
    case 'olpItemD26Suggestion':
      return l.olpItemD26Suggestion;
    case 'olpItemD27Suggestion':
      return l.olpItemD27Suggestion;
    case 'olpItemD28Suggestion':
      return l.olpItemD28Suggestion;
    case 'olpItemD29Suggestion':
      return l.olpItemD29Suggestion;
    case 'olpItemE30Suggestion':
      return l.olpItemE30Suggestion;
    case 'olpItemE31Suggestion':
      return l.olpItemE31Suggestion;
    case 'olpItemE32Suggestion':
      return l.olpItemE32Suggestion;
    case 'olpItemE33Suggestion':
      return l.olpItemE33Suggestion;
    case 'olpItemE34Suggestion':
      return l.olpItemE34Suggestion;
    case 'olpItemE35Suggestion':
      return l.olpItemE35Suggestion;
    default:
      return key;
  }
}
