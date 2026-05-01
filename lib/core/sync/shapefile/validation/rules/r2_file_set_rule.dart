import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class FileSetRule extends ShapefileValidationRule {
  const FileSetRule();

  static const _layers = ['boundary', 'buildings', 'roads'];
  static const _extensions = ['.shp', '.dbf', '.shx', '.prj'];
  static const _largeSizeThreshold = 100 * 1024 * 1024; // 100 MB

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final layer in _layers) {
      for (final ext in _extensions) {
        final key = '$layer$ext';
        final bytes = files[key];
        if (bytes == null || bytes.isEmpty) {
          return RuleFatal(
            ruleName: 'file_set',
            userMessage: 'Map files are missing or incomplete.',
          );
        }
      }
    }

    final totalBytes = files.values.fold(0, (sum, b) => sum + b.length);
    if (totalBytes > _largeSizeThreshold) {
      return const RuleWarning(
        userMessage: 'This assignment is unusually large and may be slow to load.',
      );
    }

    return const RulePassed();
  }
}
