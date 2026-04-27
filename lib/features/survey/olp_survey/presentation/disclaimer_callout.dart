import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DisclaimerCallout extends ConsumerWidget {
  const DisclaimerCallout({
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
    final notifier = ref.read(olpSectionNotifierProvider(key).notifier);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8ED),
        border: Border.all(color: const Color(0xFFF6D68E)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bullet(l.olpDisclaimerVoluntary),
          _bullet(l.olpDisclaimerSurveyorRole),
          _bullet(l.olpDisclaimerNoSelling),
          const Divider(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.olpHomeownerAgreesLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: state.homeownerAcknowledged,
                onChanged: (v) =>
                    notifier.setHomeownerAcknowledged(acknowledged: v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFF92560A))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF92560A),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
