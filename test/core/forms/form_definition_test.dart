import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final definition = FormDefinition.fromJson({
    'version': '2026.08.1',
    'name': 'Pilot form',
    'editPolicy': {
      'featureTypes': ['building'],
      'fields': {'building.storeys': false},
    },
    'visibilityRules': [
      {
        'target': 'building.section.large_building',
        'match': 'all',
        'conditions': [
          {
            'source': 'answer',
            'key': 'building.material',
            'operator': 'equals',
            'value': 'wood',
          },
          {
            'source': 'geometry',
            'key': 'areaSqMeters',
            'operator': 'gte',
            'value': 100,
          },
        ],
      },
    ],
    'constraints': [
      {
        'field': 'building.yearBuilt',
        'maxCurrentYear': true,
        'hint': 'Must not be in the future',
      },
    ],
  });

  test('published definition requires a non-empty version', () {
    expect(
      () => FormDefinition.fromJson({'version': '', 'name': 'Broken'}),
      throwsFormatException,
    );
  });

  test('skip rules combine answers and geometry attributes', () {
    final context = FormEvaluationContext(
      answers: const {'building.material': 'wood'},
      geometry: const GeometrySignal(
        featureType: 'building',
        vertexCount: 4,
        areaSqMeters: 120,
      ),
    );
    expect(
      definition.isVisible('building.section.large_building', context),
      isTrue,
    );
    expect(
      definition.isVisible(
        'building.section.large_building',
        const FormEvaluationContext(
          answers: {'building.material': 'wood'},
          geometry: GeometrySignal(
            featureType: 'building',
            vertexCount: 4,
            areaSqMeters: 99,
          ),
        ),
      ),
      isFalse,
    );
  });

  test('edit policy independently controls feature types and fields', () {
    expect(definition.isFeatureEditable('building'), isTrue);
    expect(definition.isFeatureEditable('road'), isFalse);
    expect(definition.isFieldEditable('building.storeys'), isFalse);
    expect(definition.isFieldEditable('building.material'), isTrue);
  });

  test('preview exposes visibility and shared constraint failures', () {
    final result = previewFormDefinition(
      definition,
      const FormEvaluationContext(
        answers: {'building.yearBuilt': 2027, 'building.material': 'wood'},
        geometry: GeometrySignal(
          featureType: 'building',
          vertexCount: 4,
          areaSqMeters: 120,
        ),
      ),
      now: DateTime(2026),
    );
    expect(result.visibleTargets, contains('building.section.large_building'));
    expect(
      result.validationErrors['building.yearBuilt'],
      'max_current_year',
    );
  });

  test('unknown operators fail closed during preview parsing', () {
    expect(
      () => FormDefinition.fromJson({
        'version': 'bad',
        'name': 'Bad',
        'visibilityRules': [
          {
            'target': 'x',
            'conditions': [
              {
                'source': 'answer',
                'key': 'x',
                'operator': 'execute',
                'value': true,
              },
            ],
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
