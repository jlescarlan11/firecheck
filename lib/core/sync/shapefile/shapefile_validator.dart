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
  /// In [relaxedMode], missing layers, nonstandard survey columns, and
  /// projection differences produce warnings. Corrupt headers, indexes,
  /// and attribute tables still stop the import. The app always uses this
  /// policy; strict mode remains available for validation diagnostics.
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
          if (relaxedMode &&
              !const {
                'header_integrity',
                'index_consistency',
                'attribute_integrity',
              }.contains(outcome.ruleName)) {
            warnings.add(
              RuleWarning(
                userMessage: outcome.userMessage,
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
