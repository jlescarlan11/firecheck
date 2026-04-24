import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PhotoRepository repo;
  late InMemoryPhotoStorage storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = InMemoryPhotoStorage();
    repo = PhotoRepository(db: db, storage: storage);
  });

  tearDown(() async => db.close());

  test('insert + watchForSubmission emits the row', () async {
    final id = await repo.insert(
      submissionId: 'sub-1',
      localPath: '/tmp/p.jpg',
      capturedAt: DateTime.now(),
      gpsLat: 10.3,
      gpsLng: 123.9,
    );
    final list = await repo.watchForSubmission('sub-1').first;
    expect(list, hasLength(1));
    expect(list.first.id, id);
    expect(list.first.gpsLat, 10.3);
  });

  test('countForSubmission returns 0 then 1', () async {
    expect(await repo.countForSubmission('sub-1'), 0);
    await repo.insert(
      submissionId: 'sub-1',
      localPath: '/tmp/p.jpg',
      capturedAt: DateTime.now(),
    );
    expect(await repo.countForSubmission('sub-1'), 1);
  });

  test('delete removes the row + asks storage to delete the file', () async {
    final id = await repo.insert(
      submissionId: 'sub-1',
      localPath: '/tmp/p.jpg',
      capturedAt: DateTime.now(),
    );
    await repo.delete(id);
    expect(await repo.countForSubmission('sub-1'), 0);
    expect(storage.deleted, contains('/tmp/p.jpg'));
  });
}
