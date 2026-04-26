import 'package:firecheck/features/survey/olp_survey/domain/olp_score.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/mark_complete_button.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/per_section_progress.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/score_hero.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/unchecked_items_list.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OlpResultScreen extends ConsumerWidget {
  const OlpResultScreen({
    required this.submissionId,
    required this.featureId,
    super.key,
  });
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key = OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final result = computeOlpScore(state);

    return Scaffold(
      appBar: AppBar(title: Text(l.olpResultTitle)),
      body: ListView(
        children: [
          ScoreHero(score: result.totalScore, classification: result.classification),
          PerSectionProgress(sectionScores: result.sectionScores),
          const Divider(),
          UncheckedItemsList(items: result.uncheckedItems),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: MarkCompleteButton(
              submissionId: submissionId,
              featureId: featureId,
            ),
          ),
        ),
      ),
    );
  }
}
