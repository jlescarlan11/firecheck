import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v20 adds claim ownership without discarding legacy upload history',
      () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw
            ..execute(
              'CREATE TABLE drive_upload_jobs(id TEXT PRIMARY KEY,status TEXT,file_path TEXT)',
            )
            ..execute(
              "INSERT INTO drive_upload_jobs VALUES ('upload','uploading','saved.shp')",
            )
            ..execute('PRAGMA user_version=19');
        },
      ),
    );
    addTearDown(db.close);
    final row =
        await db.customSelect('SELECT * FROM drive_upload_jobs').getSingle();
    expect(row.data.containsKey('claim_process_identity'), isTrue);
    expect(row.data['claim_process_identity'], isNull);
    expect(row.read<String>('status'), 'uploading');
    expect(row.read<String>('file_path'), 'saved.shp');
  });
}
