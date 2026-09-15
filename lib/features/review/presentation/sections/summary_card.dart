import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({required this.summary, super.key});
  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rows = [
      l.summaryFeatures(summary.totalFeatures),
      l.summaryComplete(summary.completeFeatures),
      l.summaryIncomplete(summary.incompleteFeatures),
      l.summaryNewFeatures(summary.newFeaturesAdded),
      l.summaryPhotosPending(summary.photosPending),
    ];
    return AppSection(
      title: l.designSummaryTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${summary.completeFeatures} / ${summary.totalFeatures}',
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(fontSize: 40),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: summary.totalFeatures == 0
                ? 0
                : (summary.completeFeatures / summary.totalFeatures)
                    .clamp(0.0, 1.0),
          ),
          const SizedBox(height: 20),
          for (final text in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
            ),
        ],
      ),
    );
  }
}
