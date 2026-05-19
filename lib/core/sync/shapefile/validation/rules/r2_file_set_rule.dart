import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

/// Checks that every required shapefile component is present in the
/// downloaded set and non-empty. A shapefile *layer* is the trio
/// `.shp + .dbf + .shx` plus a `.prj` for projection metadata; an
/// assignment ships three layers (boundary / buildings / roads), so the
/// complete set is 3 × 4 = 12 files.
///
/// Returns [RuleFatal] if any required file is missing or zero bytes,
/// [RuleWarning] if the total size exceeds 100 MB (slow-to-load hint),
/// otherwise [RulePassed].
@immutable
class FileSetRule extends ShapefileValidationRule {
  const FileSetRule();

  static const _largeSizeThreshold = 100 * 1024 * 1024; // 100 MB

  static const _layers = ['boundary', 'buildings', 'roads'];
  static const _extensions = ['.shp', '.dbf', '.shx', '.prj'];

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final layer in _layers) {
      for (final ext in _extensions) {
        final name = '$layer$ext';
        final bytes = files[name];
        if (bytes == null) {
          return RuleFatal(
            ruleName: 'file_set',
            userMessage:
                'Map files are missing or incomplete (missing $name).',
          );
        }
        if (bytes.isEmpty) {
          return RuleFatal(
            ruleName: 'file_set',
            userMessage:
                'Map files are missing or incomplete ($name is empty).',
          );
        }
      }
    }

    final totalBytes = files.values.fold(0, (sum, b) => sum + b.length);
    if (totalBytes > _largeSizeThreshold) {
      return const RuleWarning(
        userMessage:
            'This assignment is unusually large and may be slow to load.',
      );
    }

    return const RulePassed();
  }
}
