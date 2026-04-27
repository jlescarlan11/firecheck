import 'package:firecheck/features/survey/olp_survey/domain/olp_classification.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_score.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ScoreFooter extends ConsumerWidget {
  const ScoreFooter({
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
    final result = computeOlpScore(state);
    final color = _badgeColor(result.classification);
    final label = _classLabel(l, result.classification);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Text(
            l.olpScoreFraction(result.totalScore, OlpRubric.items.length),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => context.push(
              '/feature/$featureId/olp/result?submissionId=$submissionId',
            ),
            child: Text(l.olpViewBreakdown),
          ),
        ],
      ),
    );
  }

  Color _badgeColor(OlpClassification c) => switch (c) {
        Ligtas() => const Color(0xFF276749),
        MayroongDapatIpangamba() => const Color(0xFFB7791F),
        LabisNaMapanganib() => const Color(0xFFC53030),
      };

  String _classLabel(AppLocalizations l, OlpClassification c) => switch (c) {
        Ligtas() => l.olpClassLigtas,
        MayroongDapatIpangamba() => l.olpClassMayroong,
        LabisNaMapanganib() => l.olpClassLabis,
      };
}
