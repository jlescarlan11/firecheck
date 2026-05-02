// lib/core/sync/shapefile/export/export_validation_result.dart

enum ExportLayer { buildings, roads }

enum ExportLayerIssue { emptyLayer, missingRequiredFields }

class ExportLayerError {
  const ExportLayerError({required this.layer, required this.issue});
  final ExportLayer layer;
  final ExportLayerIssue issue;
}

class ExportValidationResult {
  const ExportValidationResult({required this.errors});
  final List<ExportLayerError> errors;
  bool get isValid => errors.isEmpty;
}
