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
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'firecheck.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
