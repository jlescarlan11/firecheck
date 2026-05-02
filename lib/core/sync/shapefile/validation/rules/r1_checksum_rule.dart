import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class ChecksumRule extends ShapefileValidationRule {
  const ChecksumRule();

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final entry in expectedMd5s.entries) {
      final bytes = files[entry.key];
      if (bytes == null) continue; // missing files are caught by R2
      final computed = md5.convert(bytes).toString();
      if (computed != entry.value) {
        return RuleFatal(
          ruleName: 'checksum',
          userMessage: 'The map file was damaged during download.',
          computedChecksum: computed,
        );
      }
    }
    return const RulePassed();
  }
}
