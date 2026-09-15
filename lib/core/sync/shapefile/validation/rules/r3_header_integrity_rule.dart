import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class HeaderIntegrityRule extends ShapefileValidationRule {
  const HeaderIntegrityRule();

  static const _shpFileCode = 9994;

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    if (!files.keys.any((name) => name.endsWith('.shp'))) {
      return const RuleFatal(
        ruleName: 'header_integrity',
        userMessage: 'No readable map layers were found in this download.',
      );
    }
    for (final entry in files.entries.where((e) => e.key.endsWith('.shp'))) {
      final shp = entry.value;

      if (shp.length < 100) {
        return const RuleFatal(
          ruleName: 'header_integrity',
          userMessage: 'Map geometry file is corrupted.',
        );
      }

      final bd = ByteData.sublistView(shp);
      final fileCode = bd.getUint32(0, Endian.big);
      if (fileCode != _shpFileCode) {
        return const RuleFatal(
          ruleName: 'header_integrity',
          userMessage: 'Map geometry file is corrupted.',
        );
      }

      final declaredWords = bd.getUint32(24, Endian.big);
      if (declaredWords * 2 != shp.length) {
        return const RuleFatal(
          ruleName: 'header_integrity',
          userMessage: 'Map geometry file is corrupted.',
        );
      }
    }
    return const RulePassed();
  }
}
