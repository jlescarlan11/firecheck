// test/core/db/migration_v7_to_v9_test.dart
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion is at least 9', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(9));
  });

  test(
      'assignments.driveFolderPath, driveFolderUrl, driveUploadConfirmedAt are nullable and default to null',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('a1')))
        .getSingle();
    expect(row.driveFolderPath, isNull);
    expect(row.driveFolderUrl, isNull);
    expect(row.driveUploadConfirmedAt, isNull);
  });

  test(
      'assignments.driveFolderPath, driveFolderUrl, driveUploadConfirmedAt can be set and read back',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final confirmedAt = DateTime(2026, 5, 2, 20, 42);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a2',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            driveFolderPath: const Value('FieldData/enum-1/2026-05-02/'),
            driveFolderUrl: const Value(
              'https://drive.google.com/drive/folders/abc123',
            ),
            driveUploadConfirmedAt: Value(confirmedAt),
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('a2')))
        .getSingle();
    expect(row.driveFolderPath, 'FieldData/enum-1/2026-05-02/');
    expect(
      row.driveFolderUrl,
      'https://drive.google.com/drive/folders/abc123',
    );
    expect(row.driveUploadConfirmedAt, confirmedAt);
  });
}
