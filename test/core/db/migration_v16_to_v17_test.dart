import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v16 exports survive migration without inventing an owner', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE drive_upload_jobs(id TEXT PRIMARY KEY)');
      raw.execute("INSERT INTO drive_upload_jobs(id) VALUES ('legacy-export')");
      raw.execute('PRAGMA user_version = 16');
    }));
    addTearDown(db.close);
    final row = await db
        .customSelect('SELECT id,owner_id,batch_id FROM drive_upload_jobs')
        .getSingle();
    expect(row.read<String>('id'), 'legacy-export');
    expect(row.data['owner_id'], null);
    expect(row.data['batch_id'], null);
  });
}
