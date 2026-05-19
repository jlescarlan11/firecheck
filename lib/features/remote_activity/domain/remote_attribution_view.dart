import 'dart:convert';

import 'package:firecheck/core/db/database.dart';

/// View-model wrapping a `remote_attributions_cache` row for the UI.
/// Decodes the denormalized `attribute_values` JSON once so widgets
/// don't have to.
class RemoteAttributionView {
  RemoteAttributionView({
    required this.id,
    required this.assignmentId,
    required this.featureId,
    required this.featureType,
    required this.attributeValues,
    required this.submittedBy,
    required this.submittedAt,
    required this.supersededAt,
    required this.updatedAt,
  });

  factory RemoteAttributionView.fromRow(RemoteAttributionsCacheData row) {
    final decoded = jsonDecode(row.attributeValuesJson);
    return RemoteAttributionView(
      id: row.id,
      assignmentId: row.assignmentId,
      featureId: row.featureId,
      featureType: row.featureType,
      attributeValues:
          decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{},
      submittedBy: row.submittedBy,
      submittedAt: row.submittedAt,
      supersededAt: row.supersededAt,
      updatedAt: row.updatedAt,
    );
  }

  final String id;
  final String assignmentId;
  final String featureId;
  final String featureType; // 'building' | 'road'
  final Map<String, dynamic> attributeValues;
  final String? submittedBy;
  final DateTime submittedAt;
  final DateTime? supersededAt;
  final DateTime updatedAt;

  bool get isCanonical => supersededAt == null;

  /// Typed sub-shape — only one of these will be non-null for a given
  /// submission, mirroring the typed child-table structure on the server.
  Map<String, dynamic>? get building =>
      _asMap(attributeValues['building']);
  Map<String, dynamic>? get road => _asMap(attributeValues['road']);
  Map<String, dynamic>? get household =>
      _asMap(attributeValues['household']);

  bool get doesNotExist =>
      attributeValues['does_not_exist'] == true;
  String? get remarks => attributeValues['remarks'] as String?;

  static Map<String, dynamic>? _asMap(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}
