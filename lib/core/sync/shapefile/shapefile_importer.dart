// lib/core/sync/shapefile/shapefile_importer.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shp_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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
    required this.dbfParser,
    required this.reprojector,
  });

  final AppDatabase db;
  final DbfParser dbfParser;
  final Reprojector reprojector;

  final _shpParser = const ShpParser();

  // Find a file by preferred exact key, falling back to any file with the extension.
  Uint8List? _findFile(Map<String, Uint8List> files, String preferred, String ext) {
    if (files.containsKey(preferred)) return files[preferred];
    for (final entry in files.entries) {
      if (entry.key.endsWith(ext)) return entry.value;
    }
    return null;
  }

  // Find DBF with the same stem as a given SHP key.
  Uint8List? _dbfForShp(Map<String, Uint8List> files, String preferred, String shpKey) {
    final dbfKey = shpKey.replaceFirst(RegExp(r'\.shp$'), '.dbf');
    if (files.containsKey(dbfKey)) return files[dbfKey];
    if (files.containsKey(preferred)) return files[preferred];
    return null;
  }

  String _shpKeyFor(Map<String, Uint8List> files, String preferred) {
    if (files.containsKey(preferred)) return preferred;
    for (final k in files.keys) {
      if (k.endsWith('.shp')) return k;
    }
    return preferred;
  }

  static const _uuid = Uuid();
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String _toFeatureId(String assignmentId, String rawFeatId) {
    if (_uuidPattern.hasMatch(rawFeatId)) return rawFeatId;
    return _uuid.v5(Namespace.url.value, '$assignmentId/$rawFeatId');
  }

  Future<ImportResult> importShapefiles(
    Map<String, Uint8List> files,
    String assignmentId,
    String driveModifiedTime,
    String driveFolderId,
    String enumeratorId, {
    String? assignmentDisplayName,
  }) async {
    // Locate .shp files by preferred name, falling back to any .shp in the zip.
    final buildingShpKey = _shpKeyFor(files, 'buildings.shp');
    final buildingShp = _findFile(files, 'buildings.shp', '.shp');
    final buildingDbfData = _dbfForShp(files, 'buildings.dbf', buildingShpKey);

    final boundaryShp = files['boundary.shp'];
    final roadShp = files['roads.shp'];
    final roadDbfData = files['roads.dbf'];

    // Parse geometries — boundary and roads are optional.
    final buildingGeoms = buildingShp != null ? _shpParser.parse(buildingShp) : <ShpGeometry>[];
    final roadGeoms = roadShp != null ? _shpParser.parse(roadShp) : <ShpGeometry>[];

    final buildingDbf = buildingDbfData != null ? dbfParser.parse(buildingDbfData) : null;
    final roadDbf = roadDbfData != null ? dbfParser.parse(roadDbfData) : null;

    final buildingRecords = buildingDbf?.records ?? [];
    final roadRecords = roadDbf?.records ?? [];

    // Boundary: use boundary.shp if present, otherwise derive a bbox from
    // buildings. If neither is available, leave the column empty — callers
    // (e.g. the map-screen long-press gate) treat an empty string as
    // "no boundary defined" and skip the containment check. Writing an
    // empty-coords Polygon JSON here would be non-empty but unmatchable,
    // and would silently reject every tap.
    final Map<String, dynamic>? boundaryGeojson;
    if (boundaryShp != null) {
      final geoms = _shpParser.parse(boundaryShp);
      boundaryGeojson = _reprojectGeom(geoms.first);
    } else if (buildingGeoms.isNotEmpty) {
      boundaryGeojson = _bboxFromGeoms(buildingGeoms);
    } else {
      boundaryGeojson = null;
    }
    final boundaryGeojsonStr =
        boundaryGeojson == null ? '' : jsonEncode(boundaryGeojson);

    // Capture a single timestamp for all rows written in this import
    final now = DateTime.now();

    debugPrint(
      '[ShapefileImporter] writing assignment id="$assignmentId" '
      'name="${assignmentDisplayName ?? assignmentId}" '
      'buildings=${buildingGeoms.length} roads=${roadGeoms.length}',
    );

    await db.transaction(() async {
      await db.into(db.assignments).insertOnConflictUpdate(
            AssignmentsCompanion(
              id: Value(assignmentId),
              enumeratorId: Value(enumeratorId),
              campaignId: Value(assignmentId),
              name: Value(assignmentDisplayName),
              boundaryPolygonGeojson: Value(boundaryGeojsonStr),
              downloadedAt: Value(now),
              driveModifiedTime: Value(driveModifiedTime),
              driveFolderId: Value(driveFolderId),
              createdAt: Value(now),
            ),
          );

      for (var i = 0; i < buildingGeoms.length; i++) {
        final rawFeatId = i < buildingRecords.length
            ? (buildingRecords[i]['feat_id']?.toString() ?? 'bld-$i')
            : 'bld-$i';
        final featId = _toFeatureId(assignmentId, rawFeatId);
        debugPrint(
          '[ShapefileImporter] building[$i] rawFeatId="$rawFeatId" → id="$featId"',
        );
        await db.into(db.features).insertOnConflictUpdate(
              FeaturesCompanion.insert(
                id: featId,
                assignmentId: assignmentId,
                featureType: 'building',
                geometryGeojson: jsonEncode(_reprojectGeom(buildingGeoms[i])),
                isNew: const Value(false),
                externalCode: Value(rawFeatId),
                createdAt: now,
              ),
            );
      }

      for (var i = 0; i < roadRecords.length; i++) {
        if (i >= roadGeoms.length) break;
        final rawFeatId = roadRecords[i]['feat_id']?.toString() ?? 'rd-$i';
        final featId = _toFeatureId(assignmentId, rawFeatId);
        debugPrint(
          '[ShapefileImporter] road[$i] rawFeatId="$rawFeatId" → id="$featId"',
        );
        await db.into(db.features).insertOnConflictUpdate(
              FeaturesCompanion.insert(
                id: featId,
                assignmentId: assignmentId,
                featureType: 'road',
                geometryGeojson: jsonEncode(_reprojectGeom(roadGeoms[i])),
                isNew: const Value(false),
                externalCode: Value(rawFeatId),
                createdAt: now,
              ),
            );
      }
    });

    return ImportResult(
      buildingCount: buildingRecords.length,
      roadCount: roadRecords.length,
      boundaryGeojson: boundaryGeojsonStr,
    );
  }

  Map<String, dynamic> _bboxFromGeoms(List<ShpGeometry> geoms) {
    var minLat = 90.0;
    var maxLat = -90.0;
    var minLng = 180.0;
    var maxLng = -180.0;
    for (final geom in geoms) {
      final geojson = _reprojectGeom(geom);
      final type = geojson['type'] as String;
      final coordsRaw = geojson['coordinates'] as List<dynamic>;
      final rings = type == 'Polygon' || type == 'MultiLineString'
          ? coordsRaw.cast<List<dynamic>>()
          : [coordsRaw];
      for (final ring in rings) {
        for (final pt in ring) {
          final coord = pt as List<dynamic>;
          final lng = coord[0] as double;
          final lat = coord[1] as double;
          if (lat < minLat) minLat = lat;
          if (lat > maxLat) maxLat = lat;
          if (lng < minLng) minLng = lng;
          if (lng > maxLng) maxLng = lng;
        }
      }
    }
    return {
      'type': 'Polygon',
      'coordinates': [
        [
          [minLng, minLat],
          [maxLng, minLat],
          [maxLng, maxLat],
          [minLng, maxLat],
          [minLng, minLat],
        ]
      ],
    };
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
