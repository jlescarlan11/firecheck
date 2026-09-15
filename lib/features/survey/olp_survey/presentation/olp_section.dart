import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/construction_details_subform.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/disclaimer_callout.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/score_footer.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/scored_section_widget.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OlpSurveySection extends ConsumerWidget {
  const OlpSurveySection({
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        title: Text(
          l.olpSectionTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        childrenPadding: const EdgeInsets.only(bottom: 24),
        children: [
          DisclaimerCallout(submissionId: submissionId, featureId: featureId),
          const SizedBox(height: 12),
          ConstructionDetailsSubform(
            submissionId: submissionId,
            featureId: featureId,
          ),
          const SizedBox(height: 12),
          for (final section in OlpSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ScoredSectionWidget(
                section: section,
                submissionId: submissionId,
                featureId: featureId,
              ),
            ),
          ScoreFooter(submissionId: submissionId, featureId: featureId),
        ],
      ),
    );
  }
}
