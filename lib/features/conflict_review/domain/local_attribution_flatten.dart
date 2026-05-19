import 'dart:convert';

import 'package:firecheck/core/db/database.dart';

/// Loads a local [Submission] together with its typed child rows and
/// returns a single label → value map shaped the same way as
/// `flattenRemoteAttributionForDisplay`, so the side-by-side compare
/// can diff matching keys.
Future<Map<String, Object?>> flattenLocalAttributionForDisplay({
  required AppDatabase db,
  required String submissionId,
}) async {
  final sub = await (db.select(db.submissions)
        ..where((t) => t.id.equals(submissionId)))
      .getSingleOrNull();
  if (sub == null) return const {};
  final feature = await (db.select(db.features)
        ..where((t) => t.id.equals(sub.featureId)))
      .getSingleOrNull();

  final out = <String, Object?>{};
  if (sub.doesNotExist) out['Does not exist'] = true;
  if (sub.remarks != null && sub.remarks!.isNotEmpty) {
    out['Remarks'] = sub.remarks;
  }

  if (feature?.featureType == 'building') {
    final b = await (db.select(db.buildingAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    if (b != null) {
      out.addAll({
        'CBMS ID': b.cbmsId,
        'Building name': b.buildingName,
        'RA 9514 type': b.ra9514Type,
        'Storeys': b.storeys,
        'Material': b.material,
        if (b.costIsExact)
          'Estimated cost': b.costAmount
        else if (b.costEstimateRange != null)
          'Cost range': b.costEstimateRange,
        'Fire-fighting facilities': _decodeArray(b.fireFightingFacilitiesJson),
        'Fire load': _decodeArray(b.fireLoadJson),
      });
    }
    final h = await (db.select(db.householdSurveys)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    if (h != null) {
      out['Homeowner acknowledged'] = h.homeownerAcknowledged;
      out['Lebel ng kahinaan'] = h.lebelNgKahinaan;
      if (h.safetySuggestions != null) {
        out['Safety suggestions'] = h.safetySuggestions;
      }
    }
  } else if (feature?.featureType == 'road') {
    final r = await (db.select(db.roadAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    if (r != null) {
      out.addAll({
        'Road name': r.roadName,
        'Is bridge': r.isBridge,
        'Width (m)': r.widthMeters,
        'Road features': _decodeArray(r.roadFeaturesJson),
        if (r.othersDescription != null)
          'Other description': r.othersDescription,
      });
    }
  }

  out.removeWhere((_, v) => v == null);
  return out;
}

List<dynamic> _decodeArray(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : const [];
  } on Object {
    return const [];
  }
}

/// Compares two flattened attribution maps and returns the set of keys
/// whose values differ. List comparisons are unordered (cookie-sorted).
Set<String> diffAttributionKeys(
  Map<String, Object?> mine,
  Map<String, Object?> theirs,
) {
  final keys = {...mine.keys, ...theirs.keys};
  final differ = <String>{};
  for (final k in keys) {
    if (!_attrEqual(mine[k], theirs[k])) differ.add(k);
  }
  return differ;
}

bool _attrEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    final aa = [...a]..sort((x, y) => '$x'.compareTo('$y'));
    final bb = [...b]..sort((x, y) => '$x'.compareTo('$y'));
    for (var i = 0; i < aa.length; i++) {
      if (!_attrEqual(aa[i], bb[i])) return false;
    }
    return true;
  }
  return a == b;
}
