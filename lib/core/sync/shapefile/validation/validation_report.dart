import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class ValidationReport {
  const ValidationReport({this.fatal, this.warnings = const []});

  final RuleFatal? fatal;
  final List<RuleWarning> warnings;

  bool get hasFatals => fatal != null;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isClean => !hasFatals && !hasWarnings;
}
