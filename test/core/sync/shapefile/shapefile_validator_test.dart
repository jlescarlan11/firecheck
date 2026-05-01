// test/core/sync/shapefile/shapefile_validator_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const _validPrj =
    'PROJCS["WGS_1984_UTM_Zone_51N",...AUTHORITY["EPSG","32651"]]';

Map<String, Uint8List> _baseFiles() => {
      'boundary.shp': Uint8List(1),
      'boundary.dbf': Uint8List(1),
      'boundary.shx': Uint8List(1),
      'boundary.prj': Uint8List.fromList(_validPrj.codeUnits),
      'buildings.shp': Uint8List(1),
      'buildings.dbf': Uint8List(1),
      'buildings.shx': Uint8List(1),
      'buildings.prj': Uint8List.fromList(_validPrj.codeUnits),
      'roads.shp': Uint8List(1),
      'roads.dbf': Uint8List(1),
      'roads.shx': Uint8List(1),
      'roads.prj': Uint8List.fromList(_validPrj.codeUnits),
    };

Map<String, List<DbfField>> _validFields() => {
      'boundary': [DbfField(name: 'feat_id', type: 'C', length: 10)],
      'buildings': [
        DbfField(name: 'feat_id', type: 'C', length: 10),
        DbfField(name: 'bldg_use', type: 'C', length: 50),
        DbfField(name: 'bldg_type', type: 'C', length: 50),
      ],
      'roads': [
        DbfField(name: 'feat_id', type: 'C', length: 10),
        DbfField(name: 'road_type', type: 'C', length: 50),
      ],
    };

void main() {
  const v = ShapefileValidator();

  test('valid files and fields → does not throw', () {
    expect(() => v.validate(_baseFiles(), _validFields()), returnsNormally);
  });

  test('missing buildings.shp → throws ShapefileValidationFailure', () {
    final files = _baseFiles()..remove('buildings.shp');
    expect(
      () => v.validate(files, _validFields()),
      throwsA(isA<ShapefileValidationFailure>()
          .having((f) => f.message, 'message', contains('buildings.shp'))),
    );
  });

  test('wrong CRS in boundary.prj → throws with CRS info', () {
    final files = _baseFiles();
    files['boundary.prj'] =
        Uint8List.fromList('GEOGCS["GCS_WGS_1984"...]'.codeUnits);
    expect(
      () => v.validate(files, _validFields()),
      throwsA(isA<ShapefileValidationFailure>()
          .having((f) => f.message, 'message', contains('32651'))),
    );
  });

  test('missing bldg_use column → throws citing column', () {
    final fields = _validFields();
    fields['buildings'] = [DbfField(name: 'feat_id', type: 'C', length: 10)];
    expect(
      () => v.validate(_baseFiles(), fields),
      throwsA(isA<ShapefileValidationFailure>()
          .having((f) => f.message, 'message', contains('bldg_use'))),
    );
  });

  test('missing road_type column → throws citing column', () {
    final fields = _validFields();
    fields['roads'] = [DbfField(name: 'feat_id', type: 'C', length: 10)];
    expect(
      () => v.validate(_baseFiles(), fields),
      throwsA(isA<ShapefileValidationFailure>()
          .having((f) => f.message, 'message', contains('road_type'))),
    );
  });
}
