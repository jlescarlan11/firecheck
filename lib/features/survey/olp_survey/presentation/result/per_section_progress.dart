import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class PerSectionProgress extends StatelessWidget {
  const PerSectionProgress({required this.sectionScores, super.key});
  final Map<OlpSection, int> sectionScores;

  static const _max = {
    OlpSection.b: 15,
    OlpSection.c: 9,
    OlpSection.d: 5,
    OlpSection.e: 6,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final section in OlpSection.values)
          _row(
            context,
            label: _label(l, section),
            score: sectionScores[section] ?? 0,
            max: _max[section]!,
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required int score,
    required int max,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
              Text(
                '$score / $max',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: max == 0 ? 0 : score / max),
        ],
      ),
    );
  }

  String _label(AppLocalizations l, OlpSection s) {
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
