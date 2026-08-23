import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:flutter/foundation.dart';

enum FormComparison {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  contains,
  isSet,
}

@immutable
class FormCondition {
  const FormCondition({
    required this.source,
    required this.key,
    required this.comparison,
    this.value,
  });

  factory FormCondition.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as String?;
    final key = json['key'] as String?;
    final operator = json['operator'] as String?;
    if (source != 'answer' && source != 'geometry') {
      throw const FormatException(
          'Condition source must be answer or geometry');
    }
    if (key == null || key.trim().isEmpty) {
      throw const FormatException('Condition key is required');
    }
    final comparison = switch (operator) {
      'equals' => FormComparison.equals,
      'not_equals' => FormComparison.notEquals,
      'gt' => FormComparison.greaterThan,
      'gte' => FormComparison.greaterThanOrEqual,
      'lt' => FormComparison.lessThan,
      'lte' => FormComparison.lessThanOrEqual,
      'contains' => FormComparison.contains,
      'is_set' => FormComparison.isSet,
      _ => throw FormatException('Unsupported condition operator: $operator'),
    };
    if (comparison != FormComparison.isSet && !json.containsKey('value')) {
      throw const FormatException('Condition value is required');
    }
    return FormCondition(
      source: source!,
      key: key,
      comparison: comparison,
      value: json['value'],
    );
  }

  final String source;
  final String key;
  final FormComparison comparison;
  final Object? value;

  bool evaluate(FormEvaluationContext context) {
    final actual =
        source == 'answer' ? context.answers[key] : context.geometryValue(key);
    return switch (comparison) {
      FormComparison.equals => actual == value,
      FormComparison.notEquals => actual != value,
      FormComparison.greaterThan =>
        _compareNumbers(actual, value, (a, b) => a > b),
      FormComparison.greaterThanOrEqual =>
        _compareNumbers(actual, value, (a, b) => a >= b),
      FormComparison.lessThan =>
        _compareNumbers(actual, value, (a, b) => a < b),
      FormComparison.lessThanOrEqual =>
        _compareNumbers(actual, value, (a, b) => a <= b),
      FormComparison.contains =>
        actual is Iterable<Object?> && actual.contains(value),
      FormComparison.isSet => actual != null && actual != '' && actual != false,
    };
  }
}

bool _compareNumbers(
  Object? actual,
  Object? expected,
  bool Function(double actual, double expected) compare,
) {
  if (actual is! num || expected is! num) return false;
  return compare(actual.toDouble(), expected.toDouble());
}

@immutable
class FormVisibilityRule {
  const FormVisibilityRule({
    required this.target,
    required this.conditions,
    this.match = 'all',
  });

  factory FormVisibilityRule.fromJson(Map<String, dynamic> json) {
    final target = json['target'] as String?;
    final match = json['match'] as String? ?? 'all';
    if (target == null || target.trim().isEmpty) {
      throw const FormatException('Visibility-rule target is required');
    }
    if (match != 'all' && match != 'any') {
      throw const FormatException('Visibility-rule match must be all or any');
    }
    final raw = json['conditions'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) {
      throw const FormatException(
          'Visibility rule needs at least one condition');
    }
    return FormVisibilityRule(
      target: target,
      match: match,
      conditions: raw
          .map((item) => FormCondition.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final String target;
  final List<FormCondition> conditions;
  final String match;

  bool evaluate(FormEvaluationContext context) => match == 'any'
      ? conditions.any((condition) => condition.evaluate(context))
      : conditions.every((condition) => condition.evaluate(context));
}

@immutable
class FormConstraint {
  const FormConstraint({
    required this.field,
    this.required = false,
    this.min,
    this.max,
    this.maxCurrentYear = false,
    this.hint,
  });

  factory FormConstraint.fromJson(Map<String, dynamic> json) {
    final field = json['field'] as String?;
    if (field == null || field.trim().isEmpty) {
      throw const FormatException('Constraint field is required');
    }
    return FormConstraint(
      field: field,
      required: json['required'] as bool? ?? false,
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      maxCurrentYear: json['maxCurrentYear'] as bool? ?? false,
      hint: json['hint'] as String?,
    );
  }

  final String field;
  final bool required;
  final double? min;
  final double? max;
  final bool maxCurrentYear;
  final String? hint;

  String? validate(Object? value, {required DateTime now}) {
    final missing =
        value == null || value == '' || value is Iterable && value.isEmpty;
    if (missing) return required ? 'required' : null;
    if (min != null && (value is! num || value.toDouble() < min!)) return 'min';
    if (max != null && (value is! num || value.toDouble() > max!)) return 'max';
    if (maxCurrentYear && (value is! num || value.toInt() > now.year)) {
      return 'max_current_year';
    }
    return null;
  }
}

@immutable
class FormDefinition {
  const FormDefinition({
    required this.version,
    required this.name,
    this.visibilityRules = const [],
    this.constraints = const [],
    this.editableFeatureTypes = const {'building', 'road'},
    this.editableFields = const {},
  });

  factory FormDefinition.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as String?;
    final name = json['name'] as String?;
    if (version == null || version.trim().isEmpty) {
      throw const FormatException('Form version is required');
    }
    if (name == null || name.trim().isEmpty) {
      throw const FormatException('Form name is required');
    }
    final editPolicy = json['editPolicy'] as Map<String, dynamic>? ?? const {};
    return FormDefinition(
      version: version,
      name: name,
      visibilityRules: (json['visibilityRules'] as List<dynamic>? ?? const [])
          .map((item) =>
              FormVisibilityRule.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      constraints: (json['constraints'] as List<dynamic>? ?? const [])
          .map((item) => FormConstraint.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      editableFeatureTypes: (editPolicy['featureTypes'] as List<dynamic>? ??
              const ['building', 'road'])
          .cast<String>()
          .toSet(),
      editableFields:
          (editPolicy['fields'] as Map<String, dynamic>? ?? const {})
              .map((key, value) => MapEntry(key, value as bool)),
    );
  }

  static const legacy = FormDefinition(version: 'legacy-v1', name: 'Legacy');

  final String version;
  final String name;
  final List<FormVisibilityRule> visibilityRules;
  final List<FormConstraint> constraints;
  final Set<String> editableFeatureTypes;
  final Map<String, bool> editableFields;

  bool isVisible(String target, FormEvaluationContext context) {
    final rules = visibilityRules.where((rule) => rule.target == target);
    if (rules.isEmpty) return true;
    return rules.every((rule) => rule.evaluate(context));
  }

  bool isFeatureEditable(String featureType) =>
      editableFeatureTypes.contains(featureType);

  bool isFieldEditable(String field) => editableFields[field] ?? true;

  Map<String, String> validate(
    Map<String, Object?> answers, {
    required DateTime now,
  }) {
    final errors = <String, String>{};
    for (final constraint in constraints) {
      final error = constraint.validate(answers[constraint.field], now: now);
      if (error != null) errors[constraint.field] = error;
    }
    return errors;
  }
}

@immutable
class FormEvaluationContext {
  const FormEvaluationContext({
    this.answers = const {},
    this.geometry = GeometrySignal.empty,
  });

  final Map<String, Object?> answers;
  final GeometrySignal geometry;

  Object? geometryValue(String key) => switch (key) {
        'areaSqMeters' => geometry.areaSqMeters,
        'lengthMeters' => geometry.lengthMeters,
        'vertexCount' => geometry.vertexCount,
        'distanceFromBoundaryMeters' => geometry.distanceFromBoundaryMeters,
        'featureType' => geometry.featureType,
        _ => null,
      };
}

@immutable
class FormPreviewResult {
  const FormPreviewResult({
    required this.visibleTargets,
    required this.validationErrors,
  });

  final Set<String> visibleTargets;
  final Map<String, String> validationErrors;
}

FormPreviewResult previewFormDefinition(
  FormDefinition definition,
  FormEvaluationContext context, {
  DateTime? now,
}) {
  final targets = definition.visibilityRules.map((rule) => rule.target).toSet();
  return FormPreviewResult(
    visibleTargets: {
      for (final target in targets)
        if (definition.isVisible(target, context)) target,
    },
    validationErrors:
        definition.validate(context.answers, now: now ?? DateTime.now()),
  );
}
