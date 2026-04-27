import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion is at least 5', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(5));
  });

  test('assignments.closedRemotely defaults to false', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('a1')))
        .getSingle();
    expect(row.closedRemotely, isFalse);
  });
}
