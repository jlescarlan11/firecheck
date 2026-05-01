import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class IndexConsistencyRule extends ShapefileValidationRule {
  const IndexConsistencyRule();

  static const _layers = ['boundary', 'buildings', 'roads'];

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final layer in _layers) {
      final shp = files['$layer.shp'];
      final shx = files['$layer.shx'];
      if (shp == null || shx == null) continue; // R2 handles missing files

      // Count records in .shx: (fileLength - 100) / 8
      if (shx.length < 100) continue;
      final shxRecordCount = (shx.length - 100) ~/ 8;

      // Count records in .shp by walking content records from byte 100
      var shpRecordCount = 0;
      var offset = 100;
      while (offset + 8 <= shp.length) {
        final bd = ByteData.sublistView(shp);
        final contentWords = bd.getUint32(offset + 4, Endian.big);
        offset += 8 + contentWords * 2;
        shpRecordCount++;
      }

      if (shxRecordCount != shpRecordCount) {
        return const RuleFatal(
          ruleName: 'index_consistency',
          userMessage: 'Map index is inconsistent with geometry.',
        );
      }

      // Verify each .shx offset × 2 falls within .shp bounds
      final shxBd = ByteData.sublistView(shx);
      for (var i = 0; i < shxRecordCount; i++) {
        final offsetWords = shxBd.getUint32(100 + i * 8, Endian.big);
        final byteOffset = offsetWords * 2;
        if (byteOffset < 0 || byteOffset >= shp.length) {
          return const RuleFatal(
            ruleName: 'index_consistency',
            userMessage: 'Map index is inconsistent with geometry.',
          );
        }
      }
    }
    return const RulePassed();
  }
}
