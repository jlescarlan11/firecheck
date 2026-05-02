import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class ProjectionRule extends ShapefileValidationRule {
  const ProjectionRule();

  static const _layers = ['boundary', 'buildings', 'roads'];

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    var hasWarning = false;
    for (final layer in _layers) {
      final prjBytes = files['$layer.prj'];
      if (prjBytes == null) {
        hasWarning = true;
        continue;
      }
      final prj = String.fromCharCodes(prjBytes);
      if (!prj.contains('32651')) {
        return const RuleFatal(
          ruleName: 'projection',
          userMessage: 'Map uses an unsupported coordinate system.',
        );
      }
    }
    if (hasWarning) {
      return const RuleWarning(
        userMessage: 'Projection file missing — map may not align correctly.',
      );
    }
    return const RulePassed();
  }
}
