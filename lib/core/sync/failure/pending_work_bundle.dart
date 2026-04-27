import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PendingWorkBundle {
  PendingWorkBundle(this._db, {Directory? downloadsDirOverride})
      : _downloadsDirOverride = downloadsDirOverride;
  final AppDatabase _db;
  final Directory? _downloadsDirOverride;

  /// Builds bundle.zip in app's external Downloads dir (or override) and
  /// returns the file. JSON dump includes all unsynced submissions, photos,
  /// new features, attrs, and household_surveys for the given assignment.
  /// Photos whose local file is missing are skipped from the photos/ tree
  /// but their metadata still appears in data.json.
  Future<File> exportFor(String assignmentId) async {
    final dir = _downloadsDirOverride ??
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final zipPath =
        p.join(dir.path, 'firecheck-pending-$assignmentId-$ts.zip');

    final archive = Archive();
    final json = await _collectUnsynced(assignmentId);
    archive.addFile(ArchiveFile.string('data.json', jsonEncode(json)));

    for (final photo in (json['photos']! as List<dynamic>)) {
      final path = (photo as Map<String, dynamic>)['local_path'] as String;
      final id = photo['id'] as String;
      final f = File(path);
      if (!f.existsSync()) continue;
      final bytes = await f.readAsBytes();
      archive.addFile(ArchiveFile('photos/$id.jpg', bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(archive);
    final out = File(zipPath);
    await out.writeAsBytes(encoded!);
    return out;
  }

  Future<Map<String, dynamic>> _collectUnsynced(String assignmentId) async {
    final features = await (_db.select(_db.features)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .get();
    final featureIds = features.map((f) => f.id).toList();
    final submissions = await (_db.select(_db.submissions)
          ..where(
            (t) =>
                t.featureId.isIn(featureIds) &
                t.syncStatus.isNotIn(['uploaded']),
          ))
        .get();
    final submissionIds = submissions.map((s) => s.id).toList();
    final building = await (_db.select(_db.buildingAttributes)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
    final road = await (_db.select(_db.roadAttributes)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
    final olp = await (_db.select(_db.householdSurveys)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
    final photos = await (_db.select(_db.photos)
          ..where(
            (t) =>
                t.submissionId.isIn(submissionIds) &
                t.uploadStatus.isNotIn(['uploaded']),
          ))
        .get();

    return {
      'assignment_id': assignmentId,
      'exported_at': DateTime.now().toIso8601String(),
      'features': features.map(_toJsonFeature).toList(),
      'submissions': submissions.map(_toJsonSubmission).toList(),
      'building_attributes': building.map(_toJsonBuilding).toList(),
      'road_attributes': road.map(_toJsonRoad).toList(),
      'household_surveys': olp.map(_toJsonOlp).toList(),
      'photos': photos.map(_toJsonPhoto).toList(),
    };
  }

  Map<String, dynamic> _toJsonFeature(Feature f) => {
        'id': f.id,
        'assignment_id': f.assignmentId,
        'feature_type': f.featureType,
        'geometry_geojson': f.geometryGeojson,
        'is_new': f.isNew,
      };

  Map<String, dynamic> _toJsonSubmission(Submission s) => {
        'id': s.id,
        'feature_id': s.featureId,
        'submitted_by': s.submittedBy,
        'does_not_exist': s.doesNotExist,
        'override_reason': s.overrideReason,
        'sync_status': s.syncStatus,
        'created_at': s.createdAt.toIso8601String(),
        'updated_at': s.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _toJsonBuilding(BuildingAttribute b) => {
        'submission_id': b.submissionId,
        'cbms_id': b.cbmsId,
        'building_name': b.buildingName,
        'ra_9514_type': b.ra9514Type,
        'storeys': b.storeys,
        'material': b.material,
        'cost_amount': b.costAmount,
        'cost_estimate_range': b.costEstimateRange,
      };

  Map<String, dynamic> _toJsonRoad(RoadAttribute r) => {
        'submission_id': r.submissionId,
        'road_name': r.roadName,
        'width_meters': r.widthMeters,
        'is_bridge': r.isBridge,
      };

  Map<String, dynamic> _toJsonOlp(HouseholdSurvey h) => {
        'submission_id': h.submissionId,
        'lebel_ng_kahinaan': h.lebelNgKahinaan,
        'homeowner_acknowledged': h.homeownerAcknowledged,
        'completed_at': h.completedAt?.toIso8601String(),
      };

  Map<String, dynamic> _toJsonPhoto(Photo ph) => {
        'id': ph.id,
        'submission_id': ph.submissionId,
        'local_path': ph.localPath,
        'storage_path': ph.storagePath,
        'upload_status': ph.uploadStatus,
        'gps_lat': ph.gpsLat,
        'gps_lng': ph.gpsLng,
        'captured_at': ph.capturedAt.toIso8601String(),
      };
}
