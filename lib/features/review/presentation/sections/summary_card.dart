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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (text) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(text, style: const TextStyle(fontSize: 14)),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
