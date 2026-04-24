import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late OfflineTilePackRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OfflineTilePackRepository(db);
  });

  tearDown(() async => db.close());

  test('upsert then watchForAssignment emits one row', () async {
    await repo.upsert(
      id: 'p1',
      assignmentId: 'a1',
      regionBoundsGeojson: '{"type":"Polygon","coordinates":[]}',
    );
    final snap = await repo.watchForAssignment('a1').first;
    expect(snap, isNotNull);
    expect(snap!.id, 'p1');
    expect(snap.status, 'downloading');
  });

  test('updateProgress updates byte counts', () async {
    await repo.upsert(
      id: 'p1',
      assignmentId: 'a1',
      regionBoundsGeojson: '{}',
    );
    await repo.updateProgress('p1', 500, 1000);
    final snap = await repo.watchForAssignment('a1').first;
    expect(snap!.downloadedBytes, 500);
    expect(snap.totalBytes, 1000);
  });

  test('markReady transitions status to ready', () async {
    await repo.upsert(
      id: 'p1',
      assignmentId: 'a1',
      regionBoundsGeojson: '{}',
    );
    await repo.markReady('p1');
    final snap = await repo.watchForAssignment('a1').first;
    expect(snap!.status, 'ready');
  });

  test('markError transitions status to error', () async {
    await repo.upsert(
      id: 'p1',
      assignmentId: 'a1',
      regionBoundsGeojson: '{}',
    );
    await repo.markError('p1', 'boom');
    final snap = await repo.watchForAssignment('a1').first;
    expect(snap!.status, 'error');
  });

  test('watchForAssignment emits null for unknown assignment', () async {
    final snap = await repo.watchForAssignment('nope').first;
    expect(snap, isNull);
  });
}
