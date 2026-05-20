import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/tables/assignment_sync_cursors.dart';
import 'package:firecheck/core/db/tables/assignments.dart';
import 'package:firecheck/core/db/tables/building_attributes.dart';
import 'package:firecheck/core/db/tables/drive_upload_jobs.dart';
import 'package:firecheck/core/db/tables/enumerators.dart';
import 'package:firecheck/core/db/tables/feature_geometry_revisions.dart';
import 'package:firecheck/core/db/tables/features.dart';
import 'package:firecheck/core/db/tables/household_surveys.dart';
import 'package:firecheck/core/db/tables/offline_tile_packs.dart';
import 'package:firecheck/core/db/tables/pending_resolutions.dart';
import 'package:firecheck/core/db/tables/photos.dart';
import 'package:firecheck/core/db/tables/ra_9514_types.dart';
import 'package:firecheck/core/db/tables/remote_attributions_cache.dart';
import 'package:firecheck/core/db/tables/remote_new_features_cache.dart';
import 'package:firecheck/core/db/tables/road_attributes.dart';
import 'package:firecheck/core/db/tables/submissions.dart';
import 'package:firecheck/core/db/tables/sync_jobs.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Enumerators,
    Assignments,
    Features,
    FeatureGeometryRevisions,
    Submissions,
    BuildingAttributes,
    RoadAttributes,
    HouseholdSurveys,
    Photos,
    Ra9514Types,
    SyncJobs,
    OfflineTilePacks,
    DriveUploadJobs,
    RemoteAttributionsCache,
    RemoteNewFeaturesCache,
    AssignmentSyncCursors,
    PendingResolutions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests — pass an in-memory executor.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 → v2:
            // 1. Rename offline_tile_packs.maplibre_pack_id → mapbox_pack_id.
            // 2. Create the five @TableIndex indexes.
            await customStatement(
              'ALTER TABLE offline_tile_packs '
              'RENAME COLUMN maplibre_pack_id TO mapbox_pack_id',
            );
            await m.createIndex(featuresAssignmentIdIdx);
            await m.createIndex(submissionsFeatureIdIdx);
            await m.createIndex(photosSubmissionIdIdx);
            await m.createIndex(syncJobsStatusRetryIdx);
            await m.createIndex(buildingAttrsRa9514TypeIdx);
          }
          if (from < 3) {
            // v2 → v3: distance Override flow records a free-text reason.
            await m.addColumn(submissions, submissions.overrideReason);
          }
          if (from < 4) {
            await m.addColumn(householdSurveys, householdSurveys.homeownerAcknowledged);
            await m.addColumn(householdSurveys, householdSurveys.completedAt);
          }
          if (from < 5) {
            await m.addColumn(assignments, assignments.closedRemotely);
          }
          if (from < 6) {
            // v5 → v6: feature_geometry_revisions table for polygon reshape.
            await m.createTable(featureGeometryRevisions);
            await m.createIndex(fgrFeatureIdIdx);
            await m.createIndex(fgrSyncStatusIdx);
          }
          if (from < 7) {
            // v6 → v7: drive_modified_time and drive_folder_id for Get Maps.
            await m.addColumn(assignments, assignments.driveModifiedTime);
            await m.addColumn(assignments, assignments.driveFolderId);
          }
          if (from < 8) {
            // v7 → v8: drive_upload_jobs table for upload to Drive.
            await m.createTable(driveUploadJobs);
            await m.createIndex(driveUploadJobsStatusIdx);
            await m.createIndex(driveUploadJobsAssignmentIdx);
          }
          if (from < 9) {
            // v8 → v9: Drive upload confirmation columns.
            await m.addColumn(assignments, assignments.driveFolderPath);
            await m.addColumn(assignments, assignments.driveFolderUrl);
            await m.addColumn(assignments, assignments.driveUploadConfirmedAt);
          }
          if (from < 10) {
            // v9 → v10: local mirror of remote canonical state + per-
            // assignment cursors for delta pulls. The cache is populated by
            // cold-open / reconnect pulls and by realtime; the user's own
            // submissions stay in `submissions` — the cache never touches them.
            await m.createTable(remoteAttributionsCache);
            await m.createIndex(remoteAttributionsCacheFeatureIdx);
            await m.createIndex(remoteAttributionsCacheUpdatedAtIdx);
            await m.createTable(remoteNewFeaturesCache);
            await m.createIndex(remoteNewFeaturesCacheAssignmentIdx);
            await m.createTable(assignmentSyncCursors);
          }
          if (from < 11) {
            // v10 → v11: pendingTheirsId tracks the conflicting canonical
            // on a parked submission so the review UI can render side-by-
            // side without re-querying. pending_resolutions stores the
            // chosen decision while it awaits the resolve_* RPC call.
            await m.addColumn(submissions, submissions.pendingTheirsId);
            await m.createTable(pendingResolutions);
          }
          if (from < 12) {
            // v11 → v12: features.pendingDedupOf tracks the candidate
            // duplicate's UUID after a dedup-pending upload. Non-null =
            // needs user review; cleared on resolve. Without this the
            // review list can't surface dedup_pending uploads — they'd
            // look like normal successes.
            await m.addColumn(features, features.pendingDedupOf);
          }
          if (from < 13) {
            // v12 → v13: rewrite any queued sync_jobs that still carry
            // the legacy `submission` / `new_feature` entity_type. The
            // matching worker handlers were removed in this release,
            // so without this update an offline queue from a prior
            // install would dead-letter as "unknown entity_type" on
            // first drain. Idempotent — already-rewritten rows are
            // skipped by the WHERE clause.
            await customStatement(
              "UPDATE sync_jobs SET entity_type = 'attribution_upload' "
              "WHERE entity_type = 'submission'",
            );
            await customStatement(
              "UPDATE sync_jobs SET entity_type = 'new_feature_upload' "
              "WHERE entity_type = 'new_feature'",
            );
          }
          if (from < 14) {
            // v13 → v14: store the Drive folder name as a human-readable
            // display label separate from the UUID assignment id.
            // Also adds features.external_code for the original DBF feat_id.
            // Guard against partial-schema migration tests that seed only
            // a subset of tables.
            final existing = (await customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type='table' AND name IN ('assignments', 'features')",
            ).get())
                .map((r) => r.read<String>('name'))
                .toSet();
            if (existing.contains('assignments')) {
              await m.addColumn(assignments, assignments.name);
            }
            if (existing.contains('features')) {
              await m.addColumn(features, features.externalCode);
            }
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'firecheck.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
