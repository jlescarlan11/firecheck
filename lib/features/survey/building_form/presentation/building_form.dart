import 'package:firecheck/core/forms/constraint_hints.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/core/forms/geometry_signal_providers.dart';
import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_context.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/remaining_questions_badge.dart';
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
    final definition = ref.watch(currentFormDefinitionProvider).valueOrNull ??
        FormDefinition.legacy;
    final geometry = ref.watch(geometrySignalProvider(featureId)).valueOrNull ??
        GeometrySignal.empty;
    final formContext = buildingFormContext(state, geometry);
    bool visible(String section) =>
        definition.isVisible('building.section.$section', formContext);

    return ListView(
      padding: appPageInsets(context),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: state.doesNotExist
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
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
                        fontSize: 13,
                        color: Color(0xFF596166),
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
        BuildingRemainingQuestionsBadge(
          submissionId: submissionId,
          featureId: featureId,
        ),
        ConstraintHints(definition: definition, fieldPrefix: 'building.'),
        const SizedBox(height: 12),
        if (visible('identity'))
          IdentitySection(
            submissionId: submissionId,
            featureId: featureId,
            disabled: disabled,
          ),
        if (visible('construction'))
          ConstructionSection(
            submissionId: submissionId,
            featureId: featureId,
            disabled: disabled,
          ),
        if (visible('cost'))
          CostSection(
            submissionId: submissionId,
            featureId: featureId,
            disabled: disabled,
          ),
        if (visible('fireFightingFacilities'))
          FfFacilitiesSection(
            submissionId: submissionId,
            featureId: featureId,
            disabled: disabled,
          ),
        if (visible('fireLoad'))
          FireLoadSection(
            submissionId: submissionId,
            featureId: featureId,
            disabled: disabled,
          ),
        if (!state.doesNotExist && visible('olp'))
          OlpSurveySection(
            submissionId: submissionId,
            featureId: featureId,
          ),
      ],
    );
  }
}
