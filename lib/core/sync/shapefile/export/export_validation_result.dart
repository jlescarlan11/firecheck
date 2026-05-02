import 'package:flutter/foundation.dart';

enum ExportLayer { buildings, roads }

enum ExportLayerIssue { emptyLayer, missingRequiredFields }

@immutable
class ExportLayerError {
  const ExportLayerError({required this.layer, required this.issue});
  final ExportLayer layer;
  final ExportLayerIssue issue;
}

@immutable
class ExportValidationResult {
  const ExportValidationResult({required this.errors});
  final List<ExportLayerError> errors;
  bool get isValid => errors.isEmpty;
}
