import 'dart:async';
import 'dart:convert';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/forms/assignment_form_store.dart';
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/forms/form_variant.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/form_store_directory.dart';

ReviewSourceData _source({
  String? boundary,
  String formVersion = 'legacy-v1',
}) =>
    ReviewSourceData(
      assignmentId: 'a',
      assignmentBoundaryGeojson: boundary,
      features: [
        Feature(
          id: 'f',
          assignmentId: 'a',
          featureType: 'building',
          geometryGeojson:
              boundary == null ? '{}' : '{"type":"Point","coordinates":[0,0]}',
          isNew: false,
          status: 'complete',
          createdAt: DateTime(2026),
        ),
      ],
      submissions: [
        Submission(
          id: 's',
          featureId: 'f',
          isAdditionalObservation: false,
          doesNotExist: false,
          formVersion: formVersion,
          syncStatus: 'ready_to_upload',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
      buildingAttrs: [
        const BuildingAttribute(
          submissionId: 's',
          ra9514Type: 'C',
          costIsExact: false,
          fireFightingFacilitiesJson: '[]',
          fireLoadJson: '[]',
        ),
      ],
      roadAttrs: [],
      householdSurveys: [],
      photoCountsBySubmission: {'s': 1},
      deadJobs: [],
    );

Future<AsyncValue<ReviewState>> _resolvedReview(
  ProviderContainer container,
) async {
  final result = Completer<AsyncValue<ReviewState>>();
  final subscription = container.listen<AsyncValue<ReviewState>>(
    reviewStateProvider,
    (_, next) {
      if (!next.isLoading && !result.isCompleted) result.complete(next);
    },
    fireImmediately: true,
  );
  final value = await result.future;
  subscription.close();
  return value;
}

void main() {
  for (final missing in [false, true]) {
    test(
        'review resolves historic definition${missing ? ' without fallback when missing' : ' from its assignment history'}',
        () async {
      await useTemporaryFormDirectory();
      final historic = {
        'version': 'historic',
        'name': 'Historic',
        'visibilityRules': [
          {
            'target': 'building.section.identity',
            'conditions': [
              {
                'source': 'answer',
                'key': 'building.costIsExact',
                'operator': 'equals',
                'value': true,
              },
            ],
          }
        ],
      };
      final current = FormDefinition.fromJson(
        const {'version': 'current', 'name': 'Current'},
      );
      await writeAssignmentForms(
        'a',
        definition: utf8.encode(jsonEncode(historic)),
      );
      await writeAssignmentForms(
        'a',
        definition: utf8.encode('{"version":"current","name":"Current"}'),
      );
      await writeAssignmentForms(
        'other',
        definition:
            utf8.encode('{"version":"historic","name":"Other map visible"}'),
      );
      final container = ProviderContainer(
        overrides: [
          currentAssignmentProvider.overrideWith((ref) => Stream.value(null)),
          reviewSourceProvider.overrideWith(
            (ref) => Stream.value(
              _source(formVersion: missing ? 'missing' : 'historic'),
            ),
          ),
          fieldRequirementsConfigProvider.overrideWith(
            (ref) async => parseFieldRequirements('building.cbmsId=required'),
          ),
          currentFormDefinitionProvider.overrideWith((ref) async => current),
          currentFormVariantProvider
              .overrideWithValue(FormVariant.defaultVariant),
          assignmentUploadChangesProvider
              .overrideWith((ref, id) => Stream.value(true)),
          uploadProgressControllerProvider.overrideWith(
            (ref, id) =>
                UploadProgressController(jobsStream: const Stream.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<ReviewState>>(
        reviewStateProvider,
        (_, __) {},
        fireImmediately: true,
      );
      await container.read(reviewSourceProvider.future);
      await container.read(fieldRequirementsConfigProvider.future);
      await container.read(currentFormDefinitionProvider.future);
      await container.read(assignmentUploadChangesProvider('').future);
      final result = await _resolvedReview(container);
      if (missing) {
        expect(result.hasError, isTrue);
        expect(result.valueOrNull?.canStartUpload ?? false, isFalse);
      } else {
        expect(result.requireValue.blockers, isEmpty);
        expect(result.requireValue.canStartUpload, isTrue);
      }
    });
  }

  for (final switched in [false, true]) {
    test(
        'review provider binds snapshot boundary to its map (switched: $switched)',
        () async {
      const boundary =
          '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}';
      final definition = FormDefinition.fromJson(const {
        'version': 'boundary',
        'name': 'Boundary',
        'visibilityRules': [
          {
            'target': 'building.section.fireFightingFacilities',
            'conditions': [
              {
                'source': 'geometry',
                'key': 'distanceFromBoundaryMeters',
                'operator': 'not_equals',
                'value': 0,
              }
            ],
          }
        ],
      });
      final container = ProviderContainer(
        overrides: [
          currentAssignmentProvider.overrideWith(
            (ref) => Stream.value(
              switched
                  ? Assignment(
                      id: 'other',
                      enumeratorId: 'user',
                      campaignId: 'campaign',
                      status: 'downloaded',
                      closedRemotely: false,
                      boundaryPolygonGeojson: '{}',
                      createdAt: DateTime(2026),
                    )
                  : null,
            ),
          ),
          reviewSourceProvider.overrideWith(
            (ref) => Stream.value(
              _source(boundary: boundary, formVersion: definition.version),
            ),
          ),
          fieldRequirementsConfigProvider.overrideWith(
            (ref) async => parseFieldRequirements(
              'building.fireFightingFacilities=required',
            ),
          ),
          currentFormDefinitionProvider.overrideWith((ref) async => definition),
          currentFormVariantProvider
              .overrideWithValue(FormVariant.defaultVariant),
          assignmentUploadChangesProvider
              .overrideWith((ref, id) => Stream.value(true)),
          uploadProgressControllerProvider.overrideWith(
            (ref, id) =>
                UploadProgressController(jobsStream: const Stream.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<ReviewState>>(
        reviewStateProvider,
        (_, __) {},
        fireImmediately: true,
      );
      await container.read(reviewSourceProvider.future);
      await container.read(fieldRequirementsConfigProvider.future);
      await container.read(currentFormDefinitionProvider.future);
      final result = await _resolvedReview(container);
      if (switched) {
        expect(result.hasError, isTrue);
        expect(result.valueOrNull, isNull);
      } else {
        expect(result.requireValue.blockers, isEmpty);
        expect(result.requireValue.canStartUpload, isTrue);
      }
    });
  }
  for (final section in ['identity', 'fireFightingFacilities']) {
    test(
        'review provider applies hidden $section definition to strict requirements',
        () async {
      final definition = FormDefinition.fromJson({
        'version': 'hidden',
        'name': 'Hidden section',
        'visibilityRules': [
          {
            'target': 'building.section.$section',
            'conditions': const [
              {
                'source': 'answer',
                'key': 'building.costIsExact',
                'operator': 'equals',
                'value': true,
              }
            ],
          }
        ],
      });
      final container = ProviderContainer(
        overrides: [
          currentAssignmentProvider.overrideWith((ref) => Stream.value(null)),
          reviewSourceProvider.overrideWith(
            (ref) => Stream.value(_source(formVersion: definition.version)),
          ),
          fieldRequirementsConfigProvider.overrideWith(
            (ref) async => parseFieldRequirements(
              'building.cbmsId=required\nbuilding.fireFightingFacilities=required',
            ),
          ),
          currentFormDefinitionProvider.overrideWith((ref) async => definition),
          currentFormVariantProvider
              .overrideWithValue(FormVariant.defaultVariant),
          assignmentUploadChangesProvider
              .overrideWith((ref, id) => Stream.value(true)),
          uploadProgressControllerProvider.overrideWith(
            (ref, id) =>
                UploadProgressController(jobsStream: const Stream.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<ReviewState>>(
        reviewStateProvider,
        (_, __) {},
        fireImmediately: true,
      );
      await container.read(reviewSourceProvider.future);
      await container.read(fieldRequirementsConfigProvider.future);
      await container.read(currentFormDefinitionProvider.future);
      final state = (await _resolvedReview(container)).requireValue;
      expect(state.blockers.length, 1);
      expect(
        state.blockers.single.code,
        section == 'identity'
            ? 'fire_fighting_facilities_required'
            : 'cbms_id_required',
      );
    });
  }

  for (final error in [false, true]) {
    test(
        'review gates upload while requirements load${error ? ' and fail' : ''}',
        () async {
      final pending = Completer<FieldRequirements>();
      final container = ProviderContainer(
        overrides: [
          currentAssignmentProvider.overrideWith((ref) => Stream.value(null)),
          reviewSourceProvider.overrideWith((ref) => Stream.value(_source())),
          fieldRequirementsConfigProvider.overrideWith((ref) => pending.future),
          currentFormDefinitionProvider
              .overrideWith((ref) async => FormDefinition.legacy),
          currentFormVariantProvider
              .overrideWithValue(FormVariant.defaultVariant),
          assignmentUploadChangesProvider
              .overrideWith((ref, id) => Stream.value(true)),
          uploadProgressControllerProvider.overrideWith(
            (ref, id) =>
                UploadProgressController(jobsStream: const Stream.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<ReviewState>>(
        reviewStateProvider,
        (_, __) {},
        fireImmediately: true,
      );
      await container.read(reviewSourceProvider.future);
      await container.read(assignmentUploadChangesProvider('').future);
      expect(container.read(reviewStateProvider).isLoading, isTrue);
      expect(
        container.read(reviewStateProvider).valueOrNull?.canStartUpload ??
            false,
        isFalse,
      );
      if (error) {
        pending.completeError(StateError('snapshot unavailable'));
        await expectLater(
          container.read(fieldRequirementsConfigProvider.future),
          throwsStateError,
        );
        expect(container.read(reviewStateProvider).hasError, isTrue);
        expect(container.read(reviewStateProvider).valueOrNull, isNull);
      } else {
        pending.complete(
          parseFieldRequirements(
            'building.cbmsId=required\nbuilding.fireFightingFacilities=required',
          ),
        );
        await container.read(fieldRequirementsConfigProvider.future);
        final state = (await _resolvedReview(container)).requireValue;
        expect(state.canStartUpload, isFalse);
        expect(
          state.blockers.map((issue) => issue.code),
          containsAll(
            ['cbms_id_required', 'fire_fighting_facilities_required'],
          ),
        );
      }
    });
  }
}
