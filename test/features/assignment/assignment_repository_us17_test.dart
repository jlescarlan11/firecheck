// test/features/assignment/assignment_repository_us17_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test('getDriveModifiedTime returns null for unknown assignment', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = AssignmentRepository(db: db);
    expect(await repo.getDriveModifiedTime('unknown'), null);
  });

  test('getDriveModifiedTime returns stored value', () async {
    final db = _db();
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'brgy-001',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            driveModifiedTime: const Value('2026-04-28T10:00:00Z'),
            createdAt: DateTime.now(),
          ),
        );
    final repo = AssignmentRepository(db: db);
    expect(
      await repo.getDriveModifiedTime('brgy-001'),
      '2026-04-28T10:00:00Z',
    );
  });
}
