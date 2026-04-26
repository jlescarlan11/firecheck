import 'package:firecheck/features/survey/olp_survey/domain/olp_form_validator.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MarkCompleteButton extends ConsumerWidget {
  const MarkCompleteButton({
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
    final notifier = ref.read(olpSectionNotifierProvider(key).notifier);
    final canComplete = validateOlpForFinalize(state).canMarkComplete;

    return Tooltip(
      message: canComplete ? '' : l.olpAcknowledgmentRequiredTooltip,
      child: FilledButton(
        onPressed: canComplete
            ? () async {
                await notifier.markComplete();
                if (context.mounted) context.pop();
              }
            : null,
        child: Text(l.olpMarkComplete),
      ),
    );
  }
}
