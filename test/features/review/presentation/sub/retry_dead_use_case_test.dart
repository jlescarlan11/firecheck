import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/presentation/sub/retry_dead_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyTrigger {
  int triggerCount = 0;
  Future<void> call() async => triggerCount++;
}

void main() {
  late AppDatabase db;
  late _SpyTrigger trigger;
  late RetryDeadUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    trigger = _SpyTrigger();
    useCase = RetryDeadUseCase(db: db, triggerNow: trigger.call);
  });
  tearDown(() async => db.close());

  Future<String> seedDeadJob({String id = 'j-1'}) async {
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: id,
          entityType: 'submission',
          entityId: 's-1',
          createdAt: DateTime(2026, 4, 27),
        ),);
    await (db.update(db.syncJobs)..where((t) => t.id.equals(id))).write(
      SyncJobsCompanion(
        status: const Value('dead'),
        attempts: const Value(5),
        lastError: const Value('boom'),
        nextRetryAt: Value(DateTime(2026, 4, 28)),
      ),
    );
    return id;
  }

  test('retryOne flips dead → pending and resets attempts/error/retry_at', () async {
    final jobId = await seedDeadJob();
    await useCase.retryOne(jobId);

    final row = await (db.select(db.syncJobs)..where((t) => t.id.equals(jobId)))
        .getSingle();
    expect(row.status, 'pending');
    expect(row.attempts, 0);
    expect(row.lastError, isNull);
    expect(row.nextRetryAt, isNull);
    expect(trigger.triggerCount, 1);
  });

  test('retryAll flips every dead job to pending', () async {
    await seedDeadJob();
    await seedDeadJob(id: 'j-2');
    await useCase.retryAll();

    final rows = await db.select(db.syncJobs).get();
    for (final r in rows) {
      expect(r.status, 'pending');
    }
    expect(trigger.triggerCount, 1);
  });

  test('retryOne is a no-op when job is not dead', () async {
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 'j-1',
          entityType: 'submission',
          entityId: 's-1',
          createdAt: DateTime(2026, 4, 27),
        ),);
    await useCase.retryOne('j-1');

    final row = await (db.select(db.syncJobs)..where((t) => t.id.equals('j-1')))
        .getSingle();
    expect(row.status, 'pending'); // already pending; unchanged
    expect(trigger.triggerCount, 1); // still triggers worker
  });
}
