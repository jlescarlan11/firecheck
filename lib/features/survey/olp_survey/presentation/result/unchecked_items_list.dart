import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/scored_section_widget.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class UncheckedItemsList extends StatelessWidget {
  const UncheckedItemsList({required this.items, super.key});
  final List<OlpRubricItem> items;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_box_outline_blank,
                      size: 16,
                      color: Color(0xFFC53030),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        resolveOlpKey(l, item.statementKey),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 2),
                  child: Text(
                    resolveOlpKey(l, item.suggestionKey),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF3B82F6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
