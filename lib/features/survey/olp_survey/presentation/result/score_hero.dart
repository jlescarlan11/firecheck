import 'package:firecheck/features/survey/olp_survey/domain/olp_classification.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class ScoreHero extends StatelessWidget {
  const ScoreHero({
    required this.score,
    required this.classification,
    super.key,
  });
  final int score;
  final OlpClassification classification;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final color = switch (classification) {
      Ligtas() => const Color(0xFF276749),
      MayroongDapatIpangamba() => const Color(0xFFB7791F),
      LabisNaMapanganib() => const Color(0xFFC53030),
    };
    final label = switch (classification) {
      Ligtas() => l.olpClassLigtas,
      MayroongDapatIpangamba() => l.olpClassMayroong,
      LabisNaMapanganib() => l.olpClassLabis,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            '$score / ${OlpRubric.items.length}',
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
