import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class AttributeIntegrityRule extends ShapefileValidationRule {
  const AttributeIntegrityRule();

  static const _buildingCols = ['feat_id', 'bldg_use', 'bldg_type'];
  static const _roadCols = ['feat_id', 'road_type'];
  static const _validVersionBytes = {0x03, 0x83};

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final layer in ['boundary', 'buildings', 'roads']) {
      final dbf = files['$layer.dbf'];
      final shp = files['$layer.shp'];
      if (dbf == null || shp == null) continue; // R2 handles missing files

      if (dbf.length < 32) {
        return const RuleFatal(
          ruleName: 'attribute_integrity',
          userMessage: 'Map attribute table is corrupted or mismatched.',
        );
      }

      final dbfBd = ByteData.sublistView(dbf);
      if (!_validVersionBytes.contains(dbf[0])) {
        return const RuleFatal(
          ruleName: 'attribute_integrity',
          userMessage: 'Map attribute table is corrupted or mismatched.',
        );
      }

      // DBF record count (bytes 4-7, LE)
      final dbfRecordCount = dbfBd.getInt32(4, Endian.little);

      // .shp record count (walk from byte 100)
      var shpRecordCount = 0;
      var offset = 100;
      final shpBd = ByteData.sublistView(shp);
      while (offset + 8 <= shp.length) {
        final contentWords = shpBd.getUint32(offset + 4, Endian.big);
        offset += 8 + contentWords * 2;
        shpRecordCount++;
      }

      if (dbfRecordCount != shpRecordCount) {
        return const RuleFatal(
          ruleName: 'attribute_integrity',
          userMessage: 'Map attribute table is corrupted or mismatched.',
        );
      }

      // Check required columns for buildings and roads
      final required = switch (layer) {
        'buildings' => _buildingCols,
        'roads' => _roadCols,
        _ => <String>[],
      };
      if (required.isEmpty) continue;

      final fieldNames = _readFieldNames(dbf);
      for (final col in required) {
        if (!fieldNames.contains(col)) {
          return const RuleFatal(
            ruleName: 'attribute_integrity',
            userMessage: 'Map attribute table is corrupted or mismatched.',
          );
        }
      }
    }
    return const RulePassed();
  }

  // Reads field names from DBF descriptor records starting at byte 32.
  // Each descriptor is 32 bytes; field name is bytes 0–10 (null-terminated ASCII).
  // The descriptor list ends when byte 0 of the next descriptor is 0x0D (terminator).
  List<String> _readFieldNames(Uint8List dbf) {
    final names = <String>[];
    var offset = 32;
    while (offset + 32 <= dbf.length && dbf[offset] != 0x0D) {
      final nameBytes = <int>[];
      for (var i = 0; i < 11; i++) {
        final b = dbf[offset + i];
        if (b == 0) break;
        nameBytes.add(b);
      }
      names.add(String.fromCharCodes(nameBytes));
      offset += 32;
    }
    return names;
  }
}
