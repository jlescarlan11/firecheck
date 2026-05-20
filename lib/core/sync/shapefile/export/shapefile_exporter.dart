// lib/core/sync/shapefile/export/shapefile_exporter.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/ph_epsg.dart';
import 'package:firecheck/core/sync/shapefile/export/dbf_writer.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shp_writer.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

class ShapefileComponentFile {
  const ShapefileComponentFile({required this.filename, required this.path});
  final String filename;
  final String path;
}

// ---------------------------------------------------------------------------
// Serializable structs passed to compute()
// ---------------------------------------------------------------------------

class _FeatureRow {
  const _FeatureRow({
    required this.featureId,
    required this.geometryGeojson,
  });
  final String featureId;
  final String geometryGeojson;
}

class _BuildingRow {
  const _BuildingRow({
    required this.featureId,
    required this.doesNotExist,
    required this.remarks,
    required this.cbmsId,
    required this.buildingName,
    required this.ra9514Type,
    required this.storeys,
    required this.material,
    required this.costIsExact,
    required this.costAmount,
    required this.costEstimateRange,
    required this.fireFightingFacilitiesJson,
    required this.fireLoadJson,
    required this.photoUrls,
  });
  final String featureId;
  final bool doesNotExist;
  final String? remarks;
  final String? cbmsId;
  final String? buildingName;
  final String? ra9514Type;
  final int? storeys;
  final String? material;
  final bool costIsExact;
  final double? costAmount;
  final String? costEstimateRange;
  final String fireFightingFacilitiesJson;
  final String fireLoadJson;
  // Public URLs to objects in the Supabase `photos` bucket, ready for a
  // QGIS user to copy out of the DBF and paste into a browser. When the
  // exporter has no Supabase URL configured (e.g. tests), falls back to
  // raw storage paths.
  final List<String> photoUrls;
}

class _RoadRow {
  const _RoadRow({
    required this.featureId,
    required this.doesNotExist,
    required this.remarks,
    required this.isBridge,
    required this.roadName,
    required this.widthMeters,
    required this.roadFeaturesJson,
    required this.othersDescription,
    required this.photoUrls,
  });
  final String featureId;
  final bool doesNotExist;
  final String? remarks;
  final bool isBridge;
  final String? roadName;
  final double? widthMeters;
  final String roadFeaturesJson;
  final String? othersDescription;
  final List<String> photoUrls;
}

class _LayerInput {
  const _LayerInput({
    required this.layerName,
    required this.isPolygon,
    required this.features,
    required this.buildingRows,
    required this.roadRows,
  });
  final String layerName;
  final bool isPolygon;
  final List<_FeatureRow> features;
  final List<_BuildingRow> buildingRows;
  final List<_RoadRow> roadRows;
}

class _LayerOutput {
  const _LayerOutput({
    required this.layerName,
    required this.shp,
    required this.shx,
    required this.dbf,
  });
  final String layerName;
  final List<int> shp;
  final List<int> shx;
  final List<int> dbf;
}

// ---------------------------------------------------------------------------
// PRJ / CPG constants
// ---------------------------------------------------------------------------

const _cpgContent = 'UTF-8';

// Signed area via the shoelace formula. Positive = CCW, negative = CW.
double _signedArea(List<List<double>> ring) {
  if (ring.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < ring.length - 1; i++) {
    final a = ring[i];
    final b = ring[i + 1];
    sum += (b[0] - a[0]) * (b[1] + a[1]);
  }
  // Shoelace as written gives 2× area; sign here = positive when CW because
  // we used (x2-x1)*(y2+y1). Invert to follow the "positive = CCW" convention.
  return -sum / 2;
}

List<List<double>> _ensureClosed(List<List<double>> ring) {
  if (ring.length < 2) return ring;
  final first = ring.first;
  final last = ring.last;
  if (first[0] == last[0] && first[1] == last[1]) return ring;
  return [...ring, [first[0], first[1]]];
}

/// For polygon parts, normalize to Esri orientation: first ring CW (outer),
/// any subsequent rings CCW (holes). Also ensures rings are closed.
List<List<List<double>>> _normalizePolygonParts(
  List<List<List<double>>> parts,
) {
  if (parts.isEmpty) return parts;
  final out = <List<List<double>>>[];
  for (var i = 0; i < parts.length; i++) {
    final closed = _ensureClosed(parts[i]);
    final area = _signedArea(closed);
    final shouldBeCw = i == 0; // outer ring is CW in Esri spec
    final isCw = area < 0;
    if (shouldBeCw != isCw && closed.length >= 3) {
      out.add(closed.reversed.toList());
    } else {
      out.add(closed);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Top-level function required by compute()
// ---------------------------------------------------------------------------

_LayerOutput _writeLayer(_LayerInput input) {
  const writer = ShpWriter();
  const dbfWriter = DbfWriter();

  // Geometry and record lists are built in lock-step: index i in geometries
  // corresponds to index i in records. Do not reorder either list independently.
  // Both lists are populated from the same ordered source in export() — features
  // is mapped from buildingRows/roadRows in iteration order, preserving alignment.

  // Parse geometries
  final geometries = <List<List<List<double>>>>[];
  for (final f in input.features) {
    final geo = jsonDecode(f.geometryGeojson) as Map<String, dynamic>;
    final type = geo['type'] as String;
    final coords = geo['coordinates'];
    final List<List<List<double>>> parts;

    if (type == 'Polygon') {
      final rings = coords as List<dynamic>;
      parts = rings
          .map(
            (r) => (r as List<dynamic>)
                .map(
                  (pt) => [
                    ((pt as List<dynamic>)[0] as num).toDouble(),
                    (pt[1] as num).toDouble(),
                  ],
                )
                .toList(),
          )
          .toList();
    } else if (type == 'MultiPolygon') {
      final multiParts = <List<List<double>>>[];
      for (final polygon in coords as List<dynamic>) {
        for (final ring in polygon as List<dynamic>) {
          multiParts.add(
            (ring as List<dynamic>)
                .map(
                  (pt) => [
                    ((pt as List<dynamic>)[0] as num).toDouble(),
                    (pt[1] as num).toDouble(),
                  ],
                )
                .toList(),
          );
        }
      }
      parts = multiParts;
    } else if (type == 'LineString') {
      final line = coords as List<dynamic>;
      parts = [
        line
            .map(
              (pt) => [
                (pt as List<dynamic>)[0] as double,
                pt[1] as double,
              ],
            )
            .toList(),
      ];
    } else if (type == 'MultiLineString') {
      final multiParts = <List<List<double>>>[];
      for (final part in coords as List<dynamic>) {
        multiParts.add(
          (part as List<dynamic>)
              .map(
                (pt) => [
                  (pt as List<dynamic>)[0] as double,
                  pt[1] as double,
                ],
              )
              .toList(),
        );
      }
      parts = multiParts;
    } else {
      parts = [];
    }

    geometries.add(input.isPolygon ? _normalizePolygonParts(parts) : parts);
  }

  // Write SHP/SHX
  final shpResult = input.isPolygon
      ? writer.writePolygons(geometries)
      : writer.writePolylines(geometries);

  // Build DBF records
  final List<DbfFieldDef> fields;
  final List<Map<String, String?>> records;

  if (input.isPolygon) {
    fields = _buildingFields();
    records = input.buildingRows
        .map(
          (r) => _buildingRecord(
            r,
            input.features
                .firstWhere((f) => f.featureId == r.featureId)
                .featureId,
          ),
        )
        .toList();
  } else {
    fields = _roadFields();
    records = input.roadRows
        .map(
          (r) => _roadRecord(
            r,
            input.features
                .firstWhere((f) => f.featureId == r.featureId)
                .featureId,
          ),
        )
        .toList();
  }

  final dbf = dbfWriter.write(fields, records);

  return _LayerOutput(
    layerName: input.layerName,
    shp: shpResult.shp,
    shx: shpResult.shx,
    dbf: dbf,
  );
}

// ---------------------------------------------------------------------------
// Field definitions
// ---------------------------------------------------------------------------

List<DbfFieldDef> _buildingFields() => const [
      DbfFieldDef(name: 'FEAT_ID', type: 'C', width: 36),
      DbfFieldDef(name: 'CBMS_ID', type: 'C', width: 20),
      DbfFieldDef(name: 'BLDG_NAME', type: 'C', width: 60),
      // DBF field names are limited to 10 chars (11th byte is the null
      // terminator); QGIS silently truncates anything longer.
      DbfFieldDef(name: 'RA9514_TYP', type: 'C', width: 20),
      DbfFieldDef(name: 'STOREYS', type: 'N', width: 3),
      DbfFieldDef(name: 'MATERIAL', type: 'C', width: 30),
      DbfFieldDef(name: 'COST_EXACT', type: 'L', width: 1),
      DbfFieldDef(name: 'COST_AMT', type: 'N', width: 12, decimals: 2),
      DbfFieldDef(name: 'COST_RANGE', type: 'C', width: 20),
      DbfFieldDef(name: 'FIRE_FACIL', type: 'C', width: 254),
      DbfFieldDef(name: 'FIRE_LOAD', type: 'C', width: 254),
      DbfFieldDef(name: 'NOT_EXIST', type: 'L', width: 1),
      DbfFieldDef(name: 'REMARKS', type: 'C', width: 254),
      // Pipe-joined public URLs to objects in the Supabase `photos`
      // bucket. Truncated at the last full entry that fits 254 chars —
      // extra photos are dropped to stay within the DBF C-field cap.
      // QGIS users copy a URL from this column and paste into a browser.
      DbfFieldDef(name: 'PHOTOS', type: 'C', width: 254),
    ];

List<DbfFieldDef> _roadFields() => const [
      DbfFieldDef(name: 'FEAT_ID', type: 'C', width: 36),
      DbfFieldDef(name: 'IS_BRIDGE', type: 'L', width: 1),
      DbfFieldDef(name: 'ROAD_NAME', type: 'C', width: 60),
      DbfFieldDef(name: 'WIDTH_M', type: 'N', width: 8, decimals: 2),
      DbfFieldDef(name: 'ROAD_FEAT', type: 'C', width: 254),
      DbfFieldDef(name: 'OTHER_DESC', type: 'C', width: 254),
      DbfFieldDef(name: 'NOT_EXIST', type: 'L', width: 1),
      DbfFieldDef(name: 'REMARKS', type: 'C', width: 254),
      DbfFieldDef(name: 'PHOTOS', type: 'C', width: 254),
    ];

// ---------------------------------------------------------------------------
// Record builders
// ---------------------------------------------------------------------------

String? _jsonArrayToPipe(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final list = jsonDecode(json) as List<dynamic>;
    if (list.isEmpty) return null;
    return list.map((e) => e.toString()).join('|');
  } catch (_) {
    return null;
  }
}

Map<String, String?> _buildingRecord(_BuildingRow r, String featureId) => {
      'FEAT_ID': featureId,
      'CBMS_ID': r.cbmsId,
      'BLDG_NAME': r.buildingName,
      'RA9514_TYP': r.ra9514Type,
      'STOREYS': r.storeys?.toString(),
      'MATERIAL': r.material,
      'COST_EXACT': r.costIsExact ? 'T' : 'F',
      'COST_AMT': r.costAmount?.toStringAsFixed(2),
      'COST_RANGE': r.costEstimateRange,
      'FIRE_FACIL': _jsonArrayToPipe(r.fireFightingFacilitiesJson),
      'FIRE_LOAD': _jsonArrayToPipe(r.fireLoadJson),
      'NOT_EXIST': r.doesNotExist ? 'T' : 'F',
      'REMARKS': r.remarks,
      'PHOTOS': _photosToPipe(r.photoUrls),
    };

Map<String, String?> _roadRecord(_RoadRow r, String featureId) => {
      'FEAT_ID': featureId,
      'IS_BRIDGE': r.isBridge ? 'T' : 'F',
      'ROAD_NAME': r.roadName,
      'WIDTH_M': r.widthMeters?.toStringAsFixed(2),
      'ROAD_FEAT': _jsonArrayToPipe(r.roadFeaturesJson),
      'OTHER_DESC': r.othersDescription,
      'NOT_EXIST': r.doesNotExist ? 'T' : 'F',
      'REMARKS': r.remarks,
      'PHOTOS': _photosToPipe(r.photoUrls),
    };

/// Pipe-joins photo URLs, dropping any URL that would push the total past
/// the 254-char DBF C-field cap. Returns null when the list is empty so
/// QGIS sees the field as NULL rather than an empty string.
String? _photosToPipe(List<String> urls) {
  if (urls.isEmpty) return null;
  const cap = 254;
  final buf = StringBuffer();
  for (final url in urls) {
    final prospective = buf.isEmpty ? url : '${buf.toString()}|$url';
    if (prospective.length > cap) break;
    if (buf.isNotEmpty) buf.write('|');
    buf.write(url);
  }
  final out = buf.toString();
  return out.isEmpty ? null : out;
}

// ---------------------------------------------------------------------------
// ShapefileExporter
// ---------------------------------------------------------------------------

class ShapefileExporter {
  ShapefileExporter({
    required this.db,
    this.shareFile,
    this.tempDirOverride,
    this.targetEpsg = 4326,
    this.supabaseUrl,
  }) : _targetCrs = requirePhCrs(targetEpsg);

  final AppDatabase db;
  final Future<void> Function(String path)? shareFile;
  final Directory? tempDirOverride;

  /// Base Supabase project URL (e.g. `https://abc.supabase.co`). When
  /// non-null, raw `photos`-bucket storage paths are rewritten into full
  /// public URLs (`<supabaseUrl>/storage/v1/object/public/photos/<path>`)
  /// in the exported DBF's PHOTOS column. When null (tests, or env not
  /// configured), the raw storage path is written instead.
  final String? supabaseUrl;

  /// EPSG code for the output coordinates. Defaults to 4326 (WGS 84
  /// lng/lat), matching how geometries are stored in the database — in
  /// that case the export pipeline writes coordinates straight through
  /// with no reprojection. Setting this to a projected PH CRS (e.g.
  /// 32651 for UTM 51N) reprojects every vertex before SHP write and
  /// emits the matching .prj.
  final int targetEpsg;
  final PhCrs _targetCrs;

  Future<ExportFailure?> export({required String assignmentId}) async {
    final destDir = tempDirOverride ?? await getTemporaryDirectory();
    final (failure, zipPath) = await _buildAndWriteZip(
      assignmentId: assignmentId,
      destDir: destDir,
    );
    if (failure != null || zipPath == null) return failure;
    if (shareFile != null) {
      try {
        await shareFile!(zipPath);
      } catch (e) {
        return ShareError(e.toString());
      }
    }
    return null;
  }

  /// Exports loose shapefile components (.shp/.shx/.dbf/.prj) for each layer
  /// to a stable directory. Returns the list of component files on success.
  /// Callers must not delete the files until uploads confirm.
  Future<(ExportFailure?, List<ShapefileComponentFile>?)> exportToFile({
    required String assignmentId,
  }) async {
    final destDir = tempDirOverride ?? await getApplicationDocumentsDirectory();
    return _buildAndWriteComponents(
      assignmentId: assignmentId,
      destDir: destDir,
    );
  }

  Future<(ExportFailure?, List<_LayerOutput>?)> _buildLayerOutputs({
    required String assignmentId,
  }) async {
    // Query all completed features with their submissions and attributes.
    final buildingRows = await _queryBuildings(assignmentId);
    final roadRows = await _queryRoads(assignmentId);

    if (buildingRows.isEmpty && roadRows.isEmpty) {
      return (const NoCompletedFeatures(), null);
    }

    // Geometries are stored in EPSG:4326. When the user asks for a
    // projected output CRS, reproject every vertex here on the main
    // isolate — proj4dart's Projection cache lives per-isolate, so doing
    // it before the compute() handoff keeps the worker pure.
    String reproject(String geojson) =>
        targetEpsg == 4326 ? geojson : _reprojectGeojson(geojson, _targetCrs);

    // Build layer inputs
    final inputs = <_LayerInput>[];

    if (buildingRows.isNotEmpty) {
      final featureRows = buildingRows
          .map(
            (r) => _FeatureRow(
              featureId: r.featureId,
              geometryGeojson: reproject(r.geometryGeojson),
            ),
          )
          .toList();
      inputs.add(
        _LayerInput(
          layerName: 'buildings',
          isPolygon: true,
          features: featureRows,
          buildingRows: buildingRows.map((r) => r.buildingRow).toList(),
          roadRows: const [],
        ),
      );
    }

    if (roadRows.isNotEmpty) {
      final featureRows = roadRows
          .map(
            (r) => _FeatureRow(
              featureId: r.featureId,
              geometryGeojson: reproject(r.geometryGeojson),
            ),
          )
          .toList();
      inputs.add(
        _LayerInput(
          layerName: 'roads',
          isPolygon: false,
          features: featureRows,
          buildingRows: const [],
          roadRows: roadRows.map((r) => r.roadRow).toList(),
        ),
      );
    }

    // Write each layer via compute
    List<_LayerOutput> outputs;
    try {
      outputs = await Future.wait(
        inputs.map((input) => compute(_writeLayer, input)),
      );
    } catch (e) {
      return (WriteError(e.toString()), null);
    }

    // Guard against exporter bugs producing empty file components.
    for (final out in outputs) {
      if (out.shp.isEmpty || out.shx.isEmpty || out.dbf.isEmpty) {
        return (WriteError('Layer ${out.layerName} produced empty components'), null);
      }
    }

    return (null, outputs);
  }

  Future<(ExportFailure?, String?)> _buildAndWriteZip({
    required String assignmentId,
    required Directory destDir,
  }) async {
    final (failure, outputs) =
        await _buildLayerOutputs(assignmentId: assignmentId);
    if (failure != null || outputs == null) return (failure, null);

    final archive = Archive();
    final prjContent = _targetCrs.wkt;
    final prjBytes = utf8.encode(prjContent);
    for (final out in outputs) {
      final name = out.layerName;
      archive
        ..addFile(ArchiveFile('$name.shp', out.shp.length, out.shp))
        ..addFile(ArchiveFile('$name.shx', out.shx.length, out.shx))
        ..addFile(ArchiveFile('$name.dbf', out.dbf.length, out.dbf))
        ..addFile(ArchiveFile('$name.prj', prjBytes.length, prjBytes))
        ..addFile(
          ArchiveFile(
            '$name.cpg',
            _cpgContent.length,
            _cpgContent.codeUnits,
          ),
        );
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) return (const WriteError('ZIP encoding produced no output'), null);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final zipName = 'firecheck_${assignmentId}_$timestamp.zip';
    final zipPath = p.join(destDir.path, zipName);

    try {
      await File(zipPath).writeAsBytes(zipBytes);
    } catch (e) {
      return (WriteError(e.toString()), null);
    }

    return (null, zipPath);
  }

  Future<(ExportFailure?, List<ShapefileComponentFile>?)>
      _buildAndWriteComponents({
    required String assignmentId,
    required Directory destDir,
  }) async {
    final (failure, outputs) =
        await _buildLayerOutputs(assignmentId: assignmentId);
    if (failure != null || outputs == null) return (failure, null);

    // Per-export subdirectory so concurrent or repeat exports never clobber
    // a file an upload worker is currently streaming.
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final exportDirPath =
        p.join(destDir.path, 'firecheck_${assignmentId}_$timestamp');
    await Directory(exportDirPath).create(recursive: true);

    final prjBytes = utf8.encode(_targetCrs.wkt);
    final components = <ShapefileComponentFile>[];
    try {
      for (final out in outputs) {
        final layer = out.layerName;
        for (final (ext, bytes) in <(String, List<int>)>[
          ('shp', out.shp),
          ('shx', out.shx),
          ('dbf', out.dbf),
          ('prj', prjBytes),
        ]) {
          final filename = '$layer.$ext';
          final path = p.join(exportDirPath, filename);
          await File(path).writeAsBytes(bytes);
          components.add(ShapefileComponentFile(filename: filename, path: path));
        }
      }
    } catch (e) {
      return (WriteError(e.toString()), null);
    }

    return (null, components);
  }

  // -------------------------------------------------------------------------
  // DB queries — run on the main isolate
  // -------------------------------------------------------------------------

  Future<List<_BuildingQueryRow>> _queryBuildings(
    String assignmentId,
  ) async {
    final query = db.select(db.features).join([
      innerJoin(
        db.submissions,
        db.submissions.featureId.equalsExp(db.features.id),
      ),
      innerJoin(
        db.buildingAttributes,
        db.buildingAttributes.submissionId.equalsExp(db.submissions.id),
      ),
    ])
      ..where(
        db.features.assignmentId.equals(assignmentId) &
            db.features.featureType.equals('building') &
            db.features.status.equals('complete'),
      );

    final rows = await query.get();
    final submissionIds =
        rows.map((r) => r.readTable(db.submissions).id).toList();
    final photosBySubmission =
        await _photoStoragePathsBySubmission(submissionIds);

    return rows.map((row) {
      final feature = row.readTable(db.features);
      final submission = row.readTable(db.submissions);
      final attr = row.readTable(db.buildingAttributes);
      return _BuildingQueryRow(
        featureId: feature.id,
        geometryGeojson: feature.geometryGeojson,
        buildingRow: _BuildingRow(
          featureId: feature.id,
          doesNotExist: submission.doesNotExist,
          remarks: submission.remarks,
          cbmsId: attr.cbmsId,
          buildingName: attr.buildingName,
          ra9514Type: attr.ra9514Type,
          storeys: attr.storeys,
          material: attr.material,
          costIsExact: attr.costIsExact,
          costAmount: attr.costAmount,
          costEstimateRange: attr.costEstimateRange,
          fireFightingFacilitiesJson: attr.fireFightingFacilitiesJson,
          fireLoadJson: attr.fireLoadJson,
          photoUrls: photosBySubmission[submission.id] ?? const [],
        ),
      );
    }).toList();
  }

  Future<List<_RoadQueryRow>> _queryRoads(String assignmentId) async {
    final query = db.select(db.features).join([
      innerJoin(
        db.submissions,
        db.submissions.featureId.equalsExp(db.features.id),
      ),
      innerJoin(
        db.roadAttributes,
        db.roadAttributes.submissionId.equalsExp(db.submissions.id),
      ),
    ])
      ..where(
        db.features.assignmentId.equals(assignmentId) &
            db.features.featureType.equals('road') &
            db.features.status.equals('complete'),
      );

    final rows = await query.get();
    final submissionIds =
        rows.map((r) => r.readTable(db.submissions).id).toList();
    final photosBySubmission =
        await _photoStoragePathsBySubmission(submissionIds);

    return rows.map((row) {
      final feature = row.readTable(db.features);
      final submission = row.readTable(db.submissions);
      final attr = row.readTable(db.roadAttributes);
      return _RoadQueryRow(
        featureId: feature.id,
        geometryGeojson: feature.geometryGeojson,
        roadRow: _RoadRow(
          featureId: feature.id,
          doesNotExist: submission.doesNotExist,
          remarks: submission.remarks,
          isBridge: attr.isBridge,
          roadName: attr.roadName,
          widthMeters: attr.widthMeters,
          roadFeaturesJson: attr.roadFeaturesJson,
          othersDescription: attr.othersDescription,
          photoUrls: photosBySubmission[submission.id] ?? const [],
        ),
      );
    }).toList();
  }

  /// Returns submissionId → list of viewer-ready photo references. When
  /// [supabaseUrl] is configured, paths are rewritten into public URLs
  /// resolvable by any browser; otherwise the raw `photos`-bucket storage
  /// path is returned (used by tests and environments without Supabase).
  /// Photos without a storage_path (still pending the Supabase upload)
  /// are skipped — they have no URL to surface yet.
  Future<Map<String, List<String>>> _photoStoragePathsBySubmission(
    List<String> submissionIds,
  ) async {
    if (submissionIds.isEmpty) return const {};
    final photos = await (db.select(db.photos)
          ..where((t) =>
              t.submissionId.isIn(submissionIds) & t.storagePath.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
        .get();
    final map = <String, List<String>>{};
    for (final p in photos) {
      final path = p.storagePath;
      if (path == null) continue;
      (map[p.submissionId] ??= <String>[]).add(_photoUrlFor(path));
    }
    return map;
  }

  String _photoUrlFor(String storagePath) {
    final base = supabaseUrl;
    if (base == null || base.isEmpty) return storagePath;
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$trimmed/storage/v1/object/public/photos/$storagePath';
  }
}

// ---------------------------------------------------------------------------
// Internal query result holders (not passed to compute)
// ---------------------------------------------------------------------------

class _BuildingQueryRow {
  const _BuildingQueryRow({
    required this.featureId,
    required this.geometryGeojson,
    required this.buildingRow,
  });
  final String featureId;
  final String geometryGeojson;
  final _BuildingRow buildingRow;
}

class _RoadQueryRow {
  const _RoadQueryRow({
    required this.featureId,
    required this.geometryGeojson,
    required this.roadRow,
  });
  final String featureId;
  final String geometryGeojson;
  final _RoadRow roadRow;
}

/// Reprojects every coordinate inside a GeoJSON geometry from EPSG:4326 to
/// the target CRS. Operates on the parsed structure and re-encodes, so the
/// downstream `_writeLayer` worker sees the same shape of input it already
/// knows how to consume — only the numeric values change.
String _reprojectGeojson(String geojson, PhCrs target) {
  final wgs84 = proj4.Projection.parse(phEpsgRegistry[4326]!.proj4);
  final dst = proj4.Projection.parse(target.proj4);

  List<double> transformPair(List<dynamic> pair) {
    final pt = wgs84.transform(
      dst,
      proj4.Point(x: (pair[0] as num).toDouble(), y: (pair[1] as num).toDouble()),
    );
    return [pt.x, pt.y];
  }

  dynamic walk(dynamic node) {
    // Bottom-out at a [lng, lat] coordinate pair (a 2-element List of nums).
    if (node is List &&
        node.length >= 2 &&
        node.length <= 3 &&
        node.first is num) {
      return transformPair(node);
    }
    if (node is List) return node.map(walk).toList();
    return node;
  }

  final geo = jsonDecode(geojson) as Map<String, dynamic>;
  geo['coordinates'] = walk(geo['coordinates']);
  return jsonEncode(geo);
}
