import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AssignmentLockRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AssignmentLockRepository(db);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
  });

  tearDown(() async => db.close());

  test('isLocked returns false initially', () async {
    expect(await repo.isLocked('a1'), isFalse);
  });

  test('markClosed sets closed_remotely=true', () async {
    await repo.markClosed('a1');
    expect(await repo.isLocked('a1'), isTrue);
  });

  test('isLocked returns false for unknown assignment', () async {
    expect(await repo.isLocked('does-not-exist'), isFalse);
  });

  test('lockStateStream emits initial value + change after markClosed',
      () async {
    final emissions = <bool>[];
    final sub = repo.lockStateStream('a1').listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions, [false]);
    await repo.markClosed('a1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions, [false, true]);
    await sub.cancel();
  });
}
