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
import 'package:flutter/foundation.dart';

@immutable
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

    // Parse each DBF file once; cache the full result so fields (for
    // validation) and records (for insertion) come from the same parse.
    final boundaryDbf = files.containsKey('boundary.dbf')
        ? dbfParser.parse(files['boundary.dbf']!)
        : null;
    final buildingDbf = files.containsKey('buildings.dbf')
        ? dbfParser.parse(files['buildings.dbf']!)
        : null;
    final roadDbf = files.containsKey('roads.dbf')
        ? dbfParser.parse(files['roads.dbf']!)
        : null;

    validator.validate(files, {
      'boundary': boundaryDbf?.fields ?? [],
      'buildings': buildingDbf?.fields ?? [],
      'roads': roadDbf?.fields ?? [],
    });

    // Parse all geometries
    final boundaryGeoms = _shpParser.parse(files['boundary.shp']!);
    final buildingGeoms = _shpParser.parse(files['buildings.shp']!);
    final roadGeoms = _shpParser.parse(files['roads.shp']!);

    final buildingRecords = buildingDbf?.records ?? [];
    final roadRecords = roadDbf?.records ?? [];

    // Reproject boundary (first polygon, all rings)
    final boundaryGeojson = _reprojectGeom(boundaryGeoms.first);

    // Capture a single timestamp for all rows written in this import
    final now = DateTime.now();

    // Write everything in a single Drift transaction
    await db.transaction(() async {
      await db.into(db.assignments).insertOnConflictUpdate(
            AssignmentsCompanion(
              id: Value(assignmentId),
              enumeratorId: Value(enumeratorId),
              campaignId: Value(assignmentId),
              boundaryPolygonGeojson: Value(jsonEncode(boundaryGeojson)),
              downloadedAt: Value(now),
              driveModifiedTime: Value(driveModifiedTime),
              driveFolderId: Value(driveFolderId),
              createdAt: Value(now),
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
                createdAt: now,
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
                createdAt: now,
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
