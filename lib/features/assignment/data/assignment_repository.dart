import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class AssignmentRepository {
  AssignmentRepository({required this.db, this.client, this.userId});
  final String? userId;
  final SupabaseClient? client;
  final AppDatabase db;

  /// A confirmation survives navigation/restarts. New local fieldwork makes
  /// the assignment uploadable again; another map's edits do not.
  Selectable<QueryRow> _uploadChanges(String assignmentId) => db.customSelect(
        """
        SELECT CASE WHEN EXISTS(SELECT 1 FROM shared_map_cursors c
          WHERE c.assignment_id=? AND c.account_id=?) THEN
          EXISTS(SELECT 1 FROM submissions s JOIN features f ON f.id=s.feature_id
            WHERE f.assignment_id=? AND s.sync_status IN ('ready_to_upload','queued','awaiting_user_resolution'))
          OR EXISTS(SELECT 1 FROM feature_geometry_revisions g JOIN features f ON f.id=g.feature_id
            WHERE f.assignment_id=? AND g.sync_status NOT IN ('uploaded','discarded'))
          OR EXISTS(SELECT 1 FROM photos p JOIN submissions s ON s.id=p.submission_id
            JOIN features f ON f.id=s.feature_id WHERE f.assignment_id=?
            AND s.sync_status='uploaded' AND p.upload_status != 'uploaded')
        ELSE EXISTS (
          SELECT 1 FROM assignments a WHERE a.id = ? AND (
            a.drive_upload_confirmed_at IS NULL
            OR EXISTS (
              SELECT 1 FROM features f WHERE f.assignment_id = a.id AND (
                f.created_at > a.drive_upload_confirmed_at
                OR EXISTS (SELECT 1 FROM submissions s WHERE s.feature_id = f.id
                  AND (s.updated_at > a.drive_upload_confirmed_at OR s.sync_status IN ('in_progress','ready_to_upload','queued','awaiting_user_resolution')))
                OR EXISTS (SELECT 1 FROM feature_geometry_revisions r
                  WHERE r.feature_id = f.id AND (r.edited_at > a.drive_upload_confirmed_at OR r.sync_status NOT IN ('uploaded','discarded')))
                OR EXISTS (SELECT 1 FROM photos p JOIN submissions s ON s.id = p.submission_id
                  WHERE s.feature_id = f.id AND (p.created_at > a.drive_upload_confirmed_at OR p.upload_status != 'uploaded'))
              )
            )
            OR EXISTS (SELECT 1 FROM drive_upload_jobs j WHERE j.assignment_id = a.id
              AND j.created_at > a.drive_upload_confirmed_at AND j.status != 'completed')
          )
        ) END AS needs_upload
        """,
        variables: [
          Variable.withString(assignmentId),
          Variable.withString(userId ?? ''),
          Variable.withString(assignmentId),
          Variable.withString(assignmentId),
          Variable.withString(assignmentId),
          Variable.withString(assignmentId),
        ],
        readsFrom: {
          db.sharedMapCursors,
          db.assignments,
          db.features,
          db.submissions,
          db.photos,
          db.featureGeometryRevisions,
          db.driveUploadJobs,
        },
      );

  bool _needsUpload(QueryRow row) => row.read<int>('needs_upload') != 0;

  Future<bool> hasChangesToUpload(String assignmentId) async =>
      _needsUpload(await _uploadChanges(assignmentId).getSingle());

  Stream<bool> watchHasChangesToUpload(String assignmentId) =>
      _uploadChanges(assignmentId).watchSingle().map(_needsUpload);

  /// Writes an assignment + its features + any ra_9514_types rows in a single
  /// Drift transaction. Exposed separately so tests don't need to wire the
  /// full Supabase query builder chain.
  Future<void> upsertBundle({
    required Map<String, dynamic> assignment,
    required List<Map<String, dynamic>> features,
    required List<Map<String, dynamic>> ra9514Types,
  }) async {
    await db.transaction(() async {
      await db.into(db.assignments).insertOnConflictUpdate(
            AssignmentsCompanion.insert(
              id: assignment['id'] as String,
              enumeratorId: assignment['enumerator_id'] as String,
              campaignId: assignment['campaign_id'] as String,
              // Accept either the legacy `boundary_polygon` raw key (used by
              // tests with hand-crafted maps) or the computed-column key
              // `boundary_polygon_geojson` (used by the production fetch).
              boundaryPolygonGeojson: (assignment['boundary_polygon_geojson'] ??
                      assignment['boundary_polygon'] ??
                      '')
                  .toString(),
              downloadedAt: Value(DateTime.now()),
              status: Value((assignment['status'] ?? 'assigned') as String),
              createdAt: DateTime.parse(assignment['created_at'] as String),
            ),
          );

      for (final f in features) {
        await db.into(db.features).insertOnConflictUpdate(
              FeaturesCompanion.insert(
                id: f['id'] as String,
                assignmentId: f['assignment_id'] as String,
                featureType: f['feature_type'] as String,
                geometryGeojson:
                    (f['geometry_geojson'] ?? f['geometry'] ?? '').toString(),
                isNew: Value((f['is_new'] ?? false) as bool),
                createdAt: DateTime.parse(f['created_at'] as String),
              ),
            );
      }

      for (final t in ra9514Types) {
        await db.into(db.ra9514Types).insertOnConflictUpdate(
              Ra9514TypesCompanion.insert(
                code: t['code'] as String,
                labelEn: t['label_en'] as String,
                labelTl: t['label_tl'] as String,
                sortOrder: Value((t['sort_order'] ?? 0) as int),
              ),
            );
      }
    });
  }

  Future<String?> getDriveModifiedTime(
    String assignmentId, {
    String? driveFolderId,
  }) async {
    // Imports may use a canonical UUID instead of the locally derived UUID.
    // The source folder identity is preserved in either case.
    if (driveFolderId != null && driveFolderId.isNotEmpty) {
      final imported = await (db.select(db.assignments)
            ..where((t) => t.driveFolderId.equals(driveFolderId))
            ..orderBy([(t) => OrderingTerm.desc(t.downloadedAt)])
            ..limit(1))
          .getSingleOrNull();
      if (imported != null) return imported.driveModifiedTime;
    }
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    return row?.driveModifiedTime;
  }

  Future<Assignment?> getAssignment(String id) =>
      (db.select(db.assignments)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Stream<Assignment?> watchAssignment(String id) =>
      (db.select(db.assignments)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  Stream<List<Assignment>> watchDownloadedAssignments() =>
      (db.select(db.assignments)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<void> selectAssignment(String id) async {
    if (userId == null) throw StateError('Sign in to select a map.');
    await db.transaction(() async {
      if (await getAssignment(id) == null) {
        throw StateError('Map is unavailable.');
      }
      await db.into(db.assignmentSelections).insertOnConflictUpdate(
            AssignmentSelectionsCompanion.insert(
              userId: userId!,
              assignmentId: id,
              selectedAt: DateTime.now(),
            ),
          );
    });
  }

  // Compatibility name: current now means explicitly selected, never newest.
  Future<Assignment?> getCurrentAssignment() async {
    if (userId == null) return null;
    final selected = await (db.select(db.assignmentSelections)
          ..where((t) => t.userId.equals(userId!)))
        .getSingleOrNull();
    return selected == null ? null : getAssignment(selected.assignmentId);
  }

  Stream<Assignment?> watchCurrentAssignment() {
    if (userId == null) return Stream.value(null);
    final query = db.select(db.assignments).join([
      innerJoin(
        db.assignmentSelections,
        db.assignmentSelections.assignmentId.equalsExp(db.assignments.id),
      ),
    ])
      ..where(db.assignmentSelections.userId.equals(userId!));
    return query
        .watchSingleOrNull()
        .map((row) => row?.readTable(db.assignments));
  }

  Future<Assignment?> getImportedAssignment(String id, String folderId) async {
    // Gateway maps have no Drive folder ID. An empty ID is not a shared
    // identity: querying it could return an entirely different downloaded map.
    if (folderId.isEmpty) return getAssignment(id);
    final row = await (db.select(db.assignments)
          ..where((t) => t.driveFolderId.equals(folderId))
          ..orderBy([(t) => OrderingTerm.desc(t.downloadedAt)])
          ..limit(1))
        .getSingleOrNull();
    return row ?? await getAssignment(id);
  }

  Future<void> setDriveUploadResult({
    required String assignmentId,
    required String driveFolderPath,
    required String driveFolderUrl,
    required DateTime driveUploadConfirmedAt,
  }) async {
    final affected = await (db.update(db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .write(
      AssignmentsCompanion(
        driveFolderPath: Value(driveFolderPath),
        driveFolderUrl: Value(driveFolderUrl),
        driveUploadConfirmedAt: Value(driveUploadConfirmedAt),
      ),
    );
    if (affected == 0) {
      throw StateError(
        'setDriveUploadResult: no assignment row found for id $assignmentId',
      );
    }
  }

  Future<({String folderPath, String folderUrl, DateTime confirmedAt})?>
      getDriveUploadResult(String assignmentId) async {
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    if (row == null ||
        row.driveFolderPath == null ||
        row.driveFolderUrl == null ||
        row.driveUploadConfirmedAt == null) {
      return null;
    }
    return (
      folderPath: row.driveFolderPath!,
      folderUrl: row.driveFolderUrl!,
      confirmedAt: row.driveUploadConfirmedAt!,
    );
  }
}
