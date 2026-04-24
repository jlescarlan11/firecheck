import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

class BuildingAttributesRepository {
  BuildingAttributesRepository(this._db);
  final AppDatabase _db;

  Stream<BuildingAttribute?> watchForSubmission(String submissionId) {
    return (_db.select(_db.buildingAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .watchSingleOrNull();
  }

  Future<void> upsertForSubmission({
    required String submissionId,
    String? cbmsId,
    String? buildingName,
    String? ra9514Type,
    int? storeys,
    String? material,
    bool costIsExact = false,
    double? costAmount,
    String? costEstimateRange,
    List<String> fireFightingFacilities = const [],
    List<String> fireLoad = const [],
  }) {
    return _db.into(_db.buildingAttributes).insertOnConflictUpdate(
          BuildingAttributesCompanion.insert(
            submissionId: submissionId,
            cbmsId: Value(cbmsId),
            buildingName: Value(buildingName),
            ra9514Type: Value(ra9514Type),
            storeys: Value(storeys),
            material: Value(material),
            costIsExact: Value(costIsExact),
            costAmount: Value(costAmount),
            costEstimateRange: Value(costEstimateRange),
            fireFightingFacilitiesJson:
                Value(jsonEncode(fireFightingFacilities)),
            fireLoadJson: Value(jsonEncode(fireLoad)),
          ),
        );
  }

  /// Decodes a JSON-encoded list of strings (used for fire_fighting_facilities
  /// and fire_load). Returns an empty list on any parse failure.
  static List<String> decodeStringList(String json) {
    if (json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList();
    } on Object {
      return const [];
    }
  }
}
