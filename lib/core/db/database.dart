import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/tables/assignments.dart';
import 'package:firecheck/core/db/tables/building_attributes.dart';
import 'package:firecheck/core/db/tables/enumerators.dart';
import 'package:firecheck/core/db/tables/features.dart';
import 'package:firecheck/core/db/tables/household_surveys.dart';
import 'package:firecheck/core/db/tables/offline_tile_packs.dart';
import 'package:firecheck/core/db/tables/photos.dart';
import 'package:firecheck/core/db/tables/ra_9514_types.dart';
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
    Submissions,
    BuildingAttributes,
    RoadAttributes,
    HouseholdSurveys,
    Photos,
    Ra9514Types,
    SyncJobs,
    OfflineTilePacks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests — pass an in-memory executor.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 5;

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
