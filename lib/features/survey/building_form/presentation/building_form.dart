import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/construction_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/cost_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/ff_facilities_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/fire_load_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/identity_section.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BuildingForm extends ConsumerWidget {
  const BuildingForm({
    required this.submissionId,
    required this.featureId,
    this.readOnly = false,
    super.key,
  });

  final String submissionId;
  final String featureId;

  /// When true, every input is disabled but the form remains scrollable.
  /// Used by `SubmissionDetailScreen` when the assignment is locked
  /// (Submitted or ClosedRemotely). Bug 15.
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key = BuildingFormKey(
      submissionId: submissionId,
      featureId: featureId,
    );
    final state = ref.watch(buildingFormNotifierProvider(key));
    final notifier = ref.read(buildingFormNotifierProvider(key).notifier);
    final disabled = state.doesNotExist || readOnly;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: disabled
                ? const Color(0xFFFFF0F0)
                : const Color(0xFFFFF8ED),
            border: Border.all(
              color: disabled
                  ? const Color(0xFFF0A0A0)
                  : const Color(0xFFF6D68E),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.doesNotExistTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: disabled ? const Color(0xFFC53030) : null,
                      ),
                    ),
                    Text(
                      l.doesNotExistHelper,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: state.doesNotExist,
                activeThumbColor: const Color(0xFFC53030),
                onChanged: readOnly
                    ? null
                    : (v) =>
                        notifier.update((s) => s.copyWith(doesNotExist: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IdentitySection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        ConstructionSection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        CostSection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        FfFacilitiesSection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        FireLoadSection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        if (!state.doesNotExist)
          OlpSurveySection(
            submissionId: submissionId,
            featureId: featureId,
          ),
      ],
    );
  }
}
