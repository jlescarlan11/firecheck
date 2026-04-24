import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/enumerators.dart';
import 'tables/assignments.dart';
import 'tables/features.dart';
import 'tables/submissions.dart';
import 'tables/building_attributes.dart';
import 'tables/road_attributes.dart';
import 'tables/household_surveys.dart';
import 'tables/photos.dart';
import 'tables/ra_9514_types.dart';
import 'tables/sync_jobs.dart';
import 'tables/offline_tile_packs.dart';

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
  AppDatabase.forTesting(QueryExecutor e) : super(e);

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
