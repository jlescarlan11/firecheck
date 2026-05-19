// Form-variant model that lets a form designer push pilot or region-specific
// survey variations without changing app code. Variants live in
// assets/form_variants.json and are loaded once at startup.
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_applicability.dart';

class FormVariant {
  const FormVariant({
    required this.id,
    required this.name,
    this.hideBuildingFields = const {},
    this.hideRoadFields = const {},
  });

  factory FormVariant.fromJson(Map<String, dynamic> json) {
    final hideBuilding = (json['hideBuildingFields'] as List? ?? const [])
        .cast<String>()
        .map(_parseBuildingField)
        .whereType<BuildingFormField>()
        .toSet();
    final hideRoad = (json['hideRoadFields'] as List? ?? const [])
        .cast<String>()
        .map(_parseRoadField)
        .whereType<RoadFormField>()
        .toSet();
    return FormVariant(
      id: json['id'] as String,
      name: json['name'] as String,
      hideBuildingFields: hideBuilding,
      hideRoadFields: hideRoad,
    );
  }

  /// Returned when a survey doesn't match any LGU- or enumerator-scoped
  /// assignment. Equivalent to the legacy "show every field" behavior.
  static const FormVariant defaultVariant =
      FormVariant(id: 'default', name: 'Standard');

  final String id;
  final String name;
  final Set<BuildingFormField> hideBuildingFields;
  final Set<RoadFormField> hideRoadFields;
}

class FormVariantConfig {
  const FormVariantConfig({
    required this.variants,
    required this.lguAssignments,
    required this.enumeratorAssignments,
  });

  factory FormVariantConfig.fromJson(Map<String, dynamic> json) {
    final variantsList = (json['variants'] as List).cast<Map<String, dynamic>>();
    final byId = <String, FormVariant>{};
    for (final v in variantsList) {
      final variant = FormVariant.fromJson(v);
      byId[variant.id] = variant;
    }
    // Ensure default is always present.
    byId.putIfAbsent('default', () => FormVariant.defaultVariant);
    final assignments = json['assignments'] as Map<String, dynamic>? ?? const {};
    return FormVariantConfig(
      variants: byId,
      lguAssignments: (assignments['lgu'] as Map<String, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k, v as String)),
      enumeratorAssignments:
          (assignments['enumerator'] as Map<String, dynamic>? ?? const {})
              .map((k, v) => MapEntry(k, v as String)),
    );
  }

  final Map<String, FormVariant> variants;
  final Map<String, String> lguAssignments;
  final Map<String, String> enumeratorAssignments;

  /// Resolves the variant for the given context. Enumerator-specific
  /// assignment wins over LGU-specific, which wins over the default.
  /// An unknown variant id falls back to default rather than crashing —
  /// stale JSON shouldn't break the form.
  FormVariant resolve({String? enumeratorId, String? lguId}) {
    final byEnum = enumeratorId == null
        ? null
        : variants[enumeratorAssignments[enumeratorId] ?? ''];
    if (byEnum != null) return byEnum;
    final byLgu = lguId == null
        ? null
        : variants[lguAssignments[lguId] ?? ''];
    if (byLgu != null) return byLgu;
    return variants['default'] ?? FormVariant.defaultVariant;
  }

  /// Empty (default-only) config used when the asset can't be loaded —
  /// e.g. in test environments without the rootBundle fixture wired in.
  static const FormVariantConfig empty = FormVariantConfig(
    variants: {'default': FormVariant.defaultVariant},
    lguAssignments: {},
    enumeratorAssignments: {},
  );
}

BuildingFormField? _parseBuildingField(String name) {
  for (final f in BuildingFormField.values) {
    if (f.name == name) return f;
  }
  return null;
}

RoadFormField? _parseRoadField(String name) {
  for (final f in RoadFormField.values) {
    if (f.name == name) return f;
  }
  return null;
}
