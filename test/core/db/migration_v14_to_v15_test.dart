import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('submissions default old rows to legacy-v1', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime(2026);
    await database.into(database.submissions).insert(
          SubmissionsCompanion.insert(
            id: 'submission',
            featureId: 'feature',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final submission = await database.select(database.submissions).getSingle();
    expect(submission.formVersion, 'legacy-v1');
    expect(database.schemaVersion, 17);
  });
}
