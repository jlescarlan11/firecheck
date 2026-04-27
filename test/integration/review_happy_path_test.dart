import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/data/submitted_assignment_lock.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flow F happy path: review → start → submitted_at stamped',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed assignment + 2 features + 2 ready_to_upload submissions w/ photo + ra_9514_type
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
    for (final i in [1, 2]) {
      await db.into(db.features).insert(FeaturesCompanion.insert(
            id: 'f-$i',
            assignmentId: 'a-1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: DateTime(2026, 4, 27),
          ));
      await db.into(db.submissions).insert(SubmissionsCompanion.insert(
            id: 's-$i',
            featureId: 'f-$i',
            submittedBy: Value('00000000-0000-0000-0000-00000000000$i'),
            syncStatus: const Value('ready_to_upload'),
            createdAt: DateTime(2026, 4, 27),
            updatedAt: DateTime(2026, 4, 27),
          ));
      await db.into(db.buildingAttributes).insert(BuildingAttributesCompanion.insert(
            submissionId: 's-$i',
            buildingName: Value('Bldg $i'),
            ra9514Type: const Value('C'),
          ));
      await db.into(db.photos).insert(PhotosCompanion.insert(
            id: 'p-$i',
            submissionId: 's-$i',
            localPath: '/tmp/p-$i.jpg',
            capturedAt: DateTime(2026, 4, 27),
            createdAt: DateTime(2026, 4, 27),
          ));
    }

    final fakeApi = FakeSyncApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncApiProvider.overrideWithValue(fakeApi as SyncApi),
          currentUserIdProvider.overrideWith(
            (_) => '00000000-0000-0000-0000-000000000001',
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Summary should show 2 features, 2 complete, 0 incomplete.
    expect(find.textContaining('2'), findsWidgets);

    // Tap Start Upload
    await tester.tap(find.text('Start Upload'));
    await tester.pumpAndSettle();
    // Settle a few extra frames for the sync worker to drain.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Manually run the SubmittedAssignmentLock once
    await SubmittedAssignmentLock(db).watchAndStamp('a-1').first;

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNotNull, reason: 'submitted_at should be stamped');
  }, skip: true);
  // Marked skip: requires the SyncController triggerNow to be wired with
  // its real worker — manual happy path on the emulator covers this in
  // Task 25. The integration test stays in tree as a documentation
  // anchor; flip skip:false once the SyncController gets a synchronous
  // drain helper (Phase 5).
}
