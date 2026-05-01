// lib/core/sync/shapefile/shapefile_validator.dart
import 'dart:typed_data';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:flutter/foundation.dart';

@immutable
class ShapefileValidator {
  const ShapefileValidator();

  static const _layers = ['boundary', 'buildings', 'roads'];
  static const _extensions = ['.shp', '.dbf', '.shx', '.prj'];
  static const _buildingCols = ['feat_id', 'bldg_use', 'bldg_type'];
  static const _roadCols = ['feat_id', 'road_type'];

  void validate(
    Map<String, Uint8List> files,
    Map<String, List<DbfField>> dbfFields,
  ) {
    for (final layer in _layers) {
      for (final ext in _extensions) {
        if (!files.containsKey('$layer$ext')) {
          throw ShapefileValidationFailure('Missing required file: $layer$ext');
        }
      }
    }

    for (final layer in _layers) {
      final prj = String.fromCharCodes(files['$layer.prj']!);
      if (!prj.contains('32651')) {
        throw ShapefileValidationFailure(
          '$layer.prj does not use EPSG:32651. '
          'Found: ${prj.length > 60 ? prj.substring(0, 60) : prj}',
        );
      }
    }

    _checkColumns('buildings', dbfFields['buildings'] ?? [], _buildingCols);
    _checkColumns('roads', dbfFields['roads'] ?? [], _roadCols);
  }

  void _checkColumns(
    String layer,
    List<DbfField> fields,
    List<String> required,
  ) {
    final names = fields.map((f) => f.name).toSet();
    for (final col in required) {
      if (!names.contains(col)) {
        throw ShapefileValidationFailure(
          "$layer.dbf is missing required column '$col'",
        );
      }
    }
  }
}
