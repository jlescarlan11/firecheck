import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class GeometrySanityRule extends ShapefileValidationRule {
  const GeometrySanityRule();

  static const _layers = ['boundary', 'buildings', 'roads'];

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    var totalFeatures = 0;
    var boundaryFeatures = 0;

    for (final layer in _layers) {
      final shp = files['$layer.shp'];
      if (shp == null || shp.length < 100) continue;

      final bd = ByteData.sublistView(shp);

      // Count records
      var offset = 100;
      var layerFeatures = 0;
      while (offset + 8 <= shp.length) {
        final contentWords = bd.getUint32(offset + 4, Endian.big);
        offset += 8 + contentWords * 2;
        layerFeatures++;
      }
      totalFeatures += layerFeatures;
      if (layer == 'boundary') {
        boundaryFeatures = layerFeatures;
      }

      // Check bbox (bytes 36-67)
      final xmin = bd.getFloat64(36, Endian.little);
      final ymin = bd.getFloat64(44, Endian.little);
      final xmax = bd.getFloat64(52, Endian.little);
      final ymax = bd.getFloat64(60, Endian.little);

      final allZero = xmin == 0 && ymin == 0 && xmax == 0 && ymax == 0;
      if (allZero || xmax <= xmin || ymax <= ymin) {
        return const RuleFatal(
          ruleName: 'geometry_sanity',
          userMessage: 'Map contains no usable features.',
        );
      }
    }

    if (boundaryFeatures == 0) {
      return const RuleFatal(
        ruleName: 'geometry_sanity',
        userMessage: 'Map contains no usable features.',
      );
    }

    return const RulePassed();
  }
}
