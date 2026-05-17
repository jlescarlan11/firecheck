import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r1_checksum_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r2_file_set_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r3_header_integrity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r4_index_consistency_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r7_projection_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/validation_report.dart';

class ShapefileValidator {
  ShapefileValidator({List<ShapefileValidationRule>? rules})
      : _rules = rules ??
            const [
              ChecksumRule(),
              FileSetRule(),
              HeaderIntegrityRule(),
              IndexConsistencyRule(),
              AttributeIntegrityRule(),
              GeometrySanityRule(),
              ProjectionRule(),
            ];

  final List<ShapefileValidationRule> _rules;

  /// Runs every rule against the candidate file set.
  ///
  /// [relaxedMode] (Issue #46): when true, fatal rule outcomes are demoted
  /// to warnings so the import proceeds regardless of source format,
  /// projection, or file-set completeness. The GIS specialist still sees
  /// the warning list — they just aren't blocked from continuing. The
  /// default (false) preserves the strict-shapefile pipeline used by the
  /// Google Drive path.
  ValidationReport validate(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s, {
    bool relaxedMode = false,
  }) {
    final warnings = <RuleWarning>[];
    for (final rule in _rules) {
      final outcome = rule.check(files, expectedMd5s);
      switch (outcome) {
        case RulePassed():
          continue;
        case RuleFatal():
          if (relaxedMode) {
            warnings.add(
              RuleWarning(
                userMessage:
                    '${outcome.userMessage} (allowed by unrestricted mode)',
              ),
            );
            continue;
          }
          return ValidationReport(fatal: outcome, warnings: warnings);
        case RuleWarning():
          warnings.add(outcome);
      }
    }
    return ValidationReport(warnings: warnings);
  }
}
