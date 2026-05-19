import 'dart:io';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/camera_service.dart';
import 'package:firecheck/core/photos/image_processor.dart';
import 'package:firecheck/core/photos/photo_capture_controller.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late InMemoryPhotoStorage storage;
  late String srcPath;
  const submissionId = 'sub-1';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_ctrl_test_');
    final src = img.Image(width: 200, height: 100);
    img.fill(src, color: img.ColorRgb8(128, 128, 128));
    srcPath = p.join(tempDir.path, 'src.jpg');
    await File(srcPath).writeAsBytes(img.encodeJpg(src));

    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = InMemoryPhotoStorage(root: tempDir.path);

    // Seed the FK chain so photos.submission_id has a valid parent. With
    // PRAGMA foreign_keys = ON, an orphan insert would fail.
    final now = DateTime.now();
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'feat-1',
            assignmentId: 'assn-1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: submissionId,
            featureId: 'feat-1',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // already gone
    }
  });

  test('capture inserts a photos row + writes file', () async {
    final controller = PhotoCaptureController(
      camera: FakeCameraService(scriptedPath: srcPath),
      processor: const ImageProcessor(),
      storage: storage,
      repo: PhotoRepository(db: db, storage: storage),
    );
    final id = await controller.capture(submissionId: submissionId);
    expect(id, isNotNull);

    final rows = await db.select(db.photos).get();
    expect(rows, hasLength(1));
    expect(rows.first.submissionId, submissionId);
    expect(File(rows.first.localPath).existsSync(), isTrue);
  });

  test('capture with cancelled camera returns null + no row', () async {
    final controller = PhotoCaptureController(
      camera: FakeCameraService(),
      processor: const ImageProcessor(),
      storage: storage,
      repo: PhotoRepository(db: db, storage: storage),
    );
    final id = await controller.capture(submissionId: submissionId);
    expect(id, isNull);
    final rows = await db.select(db.photos).get();
    expect(rows, isEmpty);
  });
}
