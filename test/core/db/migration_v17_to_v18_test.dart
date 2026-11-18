import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v17 keeps existing data and introduces no implicit selection',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE assignments(id TEXT PRIMARY KEY)');
      raw.execute("INSERT INTO assignments VALUES ('cebu'), ('guadalupe')");
      raw.execute(
          'CREATE TABLE submissions(id TEXT PRIMARY KEY, feature_id TEXT)');
      raw.execute(
          "INSERT INTO submissions VALUES ('saved-draft', 'building-1')");
      raw.execute('PRAGMA user_version = 17');
    }));
    addTearDown(db.close);
    expect(await db.select(db.assignmentSelections).get(), isEmpty);
    expect(
        await db.customSelect('SELECT * FROM assignments').get(), hasLength(2));
    expect(
        (await db.customSelect('SELECT id FROM submissions').getSingle())
            .read<String>('id'),
        'saved-draft');
  });
}
