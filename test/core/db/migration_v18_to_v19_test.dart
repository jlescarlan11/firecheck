import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'v18 migration preserves existing drafts/jobs and creates isolated sync state',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute(
          'CREATE TABLE submissions(id TEXT PRIMARY KEY, remarks TEXT)');
      raw.execute("INSERT INTO submissions VALUES ('draft','saved work')");
      raw.execute('CREATE TABLE sync_jobs(id TEXT PRIMARY KEY,status TEXT)');
      raw.execute("INSERT INTO sync_jobs VALUES ('job','in_progress')");
      raw.execute('PRAGMA user_version=18');
    }));
    addTearDown(db.close);
    final draft =
        await db.customSelect('SELECT * FROM submissions').getSingle();
    expect(draft.read<String>('remarks'), 'saved work');
    expect(draft.read<int>('is_additional_observation'), 0);
    final job = await db.customSelect('SELECT * FROM sync_jobs').getSingle();
    expect(job.read<String>('status'), 'pending');
    expect(job.data['payload_json'], isNull);
    expect(await db.select(db.sharedMapFeatures).get(), isEmpty);
    expect(await db.select(db.sharedMapCursors).get(), isEmpty);
  });
}
