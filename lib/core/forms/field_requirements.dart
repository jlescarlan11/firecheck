// lib/core/forms/field_requirements.dart
//
// Field-requirements model + parser (Issue #43). Lets a form designer flip
// individual fields between "required" and "optional" by editing a plain
// .txt file shipped as an asset — no app rebuild needed.
//
// File format: `<field_key> = required|optional` per line. Lines starting
// with `#` and blank lines are ignored. Unknown keys are kept (so the asset
// can carry forward-looking entries) but ignored at validation time.
//
// Fallback contract: when the asset is missing or unparseable, callers see
// a [FieldRequirements.allRequired] config: existing keys default required;
// CBMS ID and fire-fighting facilities default optional for compatibility.
import 'package:flutter/foundation.dart';

@immutable
class FieldRequirements {
  const FieldRequirements(this._byKey);
  const FieldRequirements._allRequired() : _byKey = const {};

  /// Legacy fallback used when the asset is missing/unparseable. Existing
  /// keys remain required; the two historically optional fields stay optional.
  static const FieldRequirements allRequired = FieldRequirements._allRequired();

  final Map<String, bool> _byKey;

  /// Explicit configuration wins. Absent keys default required except CBMS
  /// ID and fire-fighting facilities, which preserve legacy optional behavior.
  bool isRequired(String key) =>
      _byKey[key] ??
      (key != FieldRequirementKeys.buildingCbmsId &&
          key != FieldRequirementKeys.buildingFireFightingFacilities);

  /// Exposed for tests + debug surfaces. Avoid relying on key set in code:
  /// unknown keys are intentionally tolerated.
  Map<String, bool> get raw => Map.unmodifiable(_byKey);
}

/// Parses the .txt body into a [FieldRequirements]. Returns
/// [FieldRequirements.allRequired] when the text yields zero valid lines —
/// the loader treats that as "config effectively absent" and falls back to
/// the safe default rather than silently making every field optional.
FieldRequirements parseFieldRequirements(String body) {
  final out = <String, bool>{};
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim().toLowerCase();
    if (key.isEmpty) continue;
    // Unknown values default to required (safer than silently making the
    // field optional on a typo).
    out[key] = value != 'optional';
  }
  if (out.isEmpty) return FieldRequirements.allRequired;
  return FieldRequirements(out);
}

/// Well-known field keys. Validators and the asset file MUST agree on these
/// strings — the constants live here so a typo on either side fails at the
/// import boundary, not silently at runtime.
class FieldRequirementKeys {
  const FieldRequirementKeys._();

  // Building
  static const buildingCbmsId = 'building.cbmsId';
  static const buildingFireFightingFacilities =
      'building.fireFightingFacilities';
  static const buildingName = 'building.buildingName';
  static const buildingRa9514Type = 'building.ra9514Type';
  static const buildingStoreys = 'building.storeys';
  static const buildingMaterial = 'building.material';
  static const buildingCost = 'building.cost';
  static const buildingFireLoad = 'building.fireLoad';
  static const buildingPhoto = 'building.photo';

  // Road
  static const roadWidthMeters = 'road.widthMeters';
  static const roadFeatures = 'road.roadFeatures';
  static const roadOthersDescription = 'road.othersDescription';
  static const roadPhoto = 'road.photo';
}
