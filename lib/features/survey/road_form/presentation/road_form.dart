import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/forms/constraint_hints.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/core/forms/geometry_signal_providers.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_context.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_providers.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_remaining_questions_badge.dart';
import 'package:firecheck/features/survey/road_form/presentation/sections/_road_dimensions_section.dart';
import 'package:firecheck/features/survey/road_form/presentation/sections/_road_features_section.dart';
import 'package:firecheck/features/survey/road_form/presentation/sections/_road_identity_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoadForm extends ConsumerWidget {
  const RoadForm({
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
    final key = RoadFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(roadFormNotifierProvider(key));
    final notifier = ref.read(roadFormNotifierProvider(key).notifier);
    final disabled = state.doesNotExist || readOnly;
    final definition = ref.watch(currentFormDefinitionProvider).valueOrNull ??
        FormDefinition.legacy;
    final geometry = ref.watch(geometrySignalProvider(featureId)).valueOrNull ??
        GeometrySignal.empty;
    final formContext = roadFormContext(state, geometry);
    bool visible(String section) =>
        definition.isVisible('road.section.$section', formContext);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8ED),
            border: Border.all(color: const Color(0xFFF6D68E)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.doesNotExistTitleRoad,
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
                    : (v) => notifier.update(
                          (s) => s.copyWith(doesNotExist: v),
                        ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        RoadRemainingQuestionsBadge(
          submissionId: submissionId,
          featureId: featureId,
        ),
        ConstraintHints(definition: definition, fieldPrefix: 'road.'),
        const SizedBox(height: 8),
        if (visible('identity'))
          RoadIdentitySection(
            submissionId: submissionId,
            featureId: featureId,
            disabled: disabled,
          ),
        const SizedBox(height: 8),
        if (visible('dimensions'))
          RoadDimensionsSection(
            submissionId: submissionId,
            featureId: featureId,
            disabled: disabled,
          ),
        const SizedBox(height: 8),
        if (visible('features'))
          RoadFeaturesSection(
            submissionId: submissionId,
            featureId: featureId,
            disabled: disabled,
          ),
      ],
    );
  }
}
