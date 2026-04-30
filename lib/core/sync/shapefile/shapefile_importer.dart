// lib/core/sync/shapefile/shapefile_importer.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/sync/shapefile/shp_parser.dart';

class ImportResult {
  const ImportResult({
    required this.buildingCount,
    required this.roadCount,
    required this.boundaryGeojson,
  });
  final int buildingCount;
  final int roadCount;
  final String boundaryGeojson;
}

class ShapefileImporter {
  ShapefileImporter({
    required this.db,
    required this.validator,
    required this.dbfParser,
    required this.reprojector,
  });

  final AppDatabase db;
  final ShapefileValidator validator;
  final DbfParser dbfParser;
  final Reprojector reprojector;

  final _shpParser = const ShpParser();

  Future<ImportResult> importInputZip(
    Uint8List zipBytes,
    String assignmentId,
    String driveModifiedTime,
    String driveFolderId,
    String enumeratorId,
  ) async {
    // Unzip
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final files = <String, Uint8List>{};
    for (final f in archive) {
      if (f.isFile) {
        files[f.name] = Uint8List.fromList(f.content as List<int>);
      }
    }

    // Parse DBF fields if present; otherwise use empty lists so that the
    // validator's file-presence check fires before any null-dereference.
    final boundaryFields = files.containsKey('boundary.dbf')
        ? dbfParser.parse(files['boundary.dbf']!).fields
        : <DbfField>[];
    final buildingFields = files.containsKey('buildings.dbf')
        ? dbfParser.parse(files['buildings.dbf']!).fields
        : <DbfField>[];
    final roadFields = files.containsKey('roads.dbf')
        ? dbfParser.parse(files['roads.dbf']!).fields
        : <DbfField>[];

    validator.validate(files, {
      'boundary': boundaryFields,
      'buildings': buildingFields,
      'roads': roadFields,
    });

    // Parse all geometries and records
    final boundaryGeoms = _shpParser.parse(files['boundary.shp']!);
    final buildingGeoms = _shpParser.parse(files['buildings.shp']!);
    final roadGeoms = _shpParser.parse(files['roads.shp']!);

    final buildingRecords = dbfParser.parse(files['buildings.dbf']!).records;
    final roadRecords = dbfParser.parse(files['roads.dbf']!).records;

    // Reproject boundary (first polygon, all rings)
    final boundaryGeojson = _reprojectGeom(boundaryGeoms.first);

    // Write everything in a single Drift transaction
    await db.transaction(() async {
      await db.into(db.assignments).insertOnConflictUpdate(
            AssignmentsCompanion(
              id: Value(assignmentId),
              enumeratorId: Value(enumeratorId),
              campaignId: Value(assignmentId),
              boundaryPolygonGeojson: Value(jsonEncode(boundaryGeojson)),
              downloadedAt: Value(DateTime.now()),
              driveModifiedTime: Value(driveModifiedTime),
              driveFolderId: Value(driveFolderId),
              createdAt: Value(DateTime.now()),
            ),
          );

      for (var i = 0; i < buildingRecords.length; i++) {
        if (i >= buildingGeoms.length) break;
        final featId = buildingRecords[i]['feat_id'] ?? 'bld-$i';
        await db.into(db.features).insertOnConflictUpdate(
              FeaturesCompanion.insert(
                id: '$assignmentId/$featId',
                assignmentId: assignmentId,
                featureType: 'building',
                geometryGeojson: jsonEncode(_reprojectGeom(buildingGeoms[i])),
                isNew: const Value(false),
                createdAt: DateTime.now(),
              ),
            );
      }

      for (var i = 0; i < roadRecords.length; i++) {
        if (i >= roadGeoms.length) break;
        final featId = roadRecords[i]['feat_id'] ?? 'rd-$i';
        await db.into(db.features).insertOnConflictUpdate(
              FeaturesCompanion.insert(
                id: '$assignmentId/$featId',
                assignmentId: assignmentId,
                featureType: 'road',
                geometryGeojson: jsonEncode(_reprojectGeom(roadGeoms[i])),
                isNew: const Value(false),
                createdAt: DateTime.now(),
              ),
            );
      }
    });

    return ImportResult(
      buildingCount: buildingRecords.length,
      roadCount: roadRecords.length,
      boundaryGeojson: jsonEncode(boundaryGeojson),
    );
  }

  Map<String, dynamic> _reprojectGeom(ShpGeometry geom) {
    return switch (geom) {
      ShpPolygon(:final rings) => {
          'type': 'Polygon',
          'coordinates': rings.map(reprojector.reprojectRing).toList(),
        },
      ShpPolyline(:final parts) when parts.length == 1 => {
          'type': 'LineString',
          'coordinates': reprojector.reprojectRing(parts.first),
        },
      ShpPolyline(:final parts) => {
          'type': 'MultiLineString',
          'coordinates': parts.map(reprojector.reprojectRing).toList(),
        },
    };
  }
}
