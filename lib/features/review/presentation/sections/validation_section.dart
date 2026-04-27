import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class ValidationSection extends StatelessWidget {
  const ValidationSection({
    required this.issues,
    required this.severity,
    required this.onGoToFeature,
    super.key,
  });

  final List<ReviewIssue> issues;
  final ReviewSeverity severity;
  final void Function(String featureId) onGoToFeature;

  String _resolveMessage(AppLocalizations l, String key) {
    switch (key) {
      case 'issuePhotoRequired':
        return l.issuePhotoRequired;
      case 'issueRa9514Required':
        return l.issueRa9514Required;
      case 'issueWidthRequired':
        return l.issueWidthRequired;
      case 'issueOlpResidential':
        return l.issueOlpResidential;
      case 'issueCostAmountMissing':
        return l.issueCostAmountMissing;
      case 'issueFeatureNoSubmission':
        return l.issueFeatureNoSubmission;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final isBlocker = severity == ReviewSeverity.blocker;
    final color = isBlocker ? const Color(0xFFC53030) : const Color(0xFFB7791F);
    final title = isBlocker
        ? l.validationBlockersTitle(issues.length)
        : l.validationWarningsTitle(issues.length);

    final byFeature = <String, List<ReviewIssue>>{};
    final labels = <String, String>{};
    for (final i in issues) {
      byFeature.putIfAbsent(i.featureId, () => []).add(i);
      labels[i.featureId] = i.featureLabel;
    }

    return Card(
      color: isBlocker ? const Color(0xFFFFF5F5) : const Color(0xFFFFFAF0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isBlocker ? Icons.error_outline : Icons.warning_amber_outlined,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
              ],
            ),
            const SizedBox(height: 8),
            ...byFeature.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels[entry.key] ?? entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    ...entry.value.map(
                      (i) => Padding(
                        padding: const EdgeInsets.only(left: 12, top: 2),
                        child: Text('• ${_resolveMessage(l, i.messageKey)}'),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => onGoToFeature(entry.key),
                        child: Text(l.goToFeature),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
