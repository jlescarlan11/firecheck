import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory tmpDir;
  late PendingWorkBundle bundle;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tmpDir = Directory.systemTemp.createTempSync('firecheck-bundle-');
    bundle = PendingWorkBundle(db, downloadsDirOverride: tmpDir);
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value('queued'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('exportFor writes a zip containing data.json with unsynced rows',
      () async {
    final out = await bundle.exportFor('a1');
    expect(out.existsSync(), isTrue);
    final bytes = await out.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final dataFile =
        archive.files.firstWhere((f) => f.name == 'data.json');
    final json = jsonDecode(utf8.decode(dataFile.content as List<int>))
        as Map<String, dynamic>;
    expect(
      ((json['submissions'] as List).first as Map<String, dynamic>)['id'],
      's1',
    );
  });

  test('exportFor includes photo files when photos exist + file present',
      () async {
    final photoFile = File(p.join(tmpDir.path, 'src-photo.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4, 5]);
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph1',
          submissionId: 's1',
          localPath: photoFile.path,
          capturedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),);
    final out = await bundle.exportFor('a1');
    final archive =
        ZipDecoder().decodeBytes(await out.readAsBytes());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, contains('photos/ph1.jpg'));
  });

  test('exportFor skips photo files whose local file is missing', () async {
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph-missing',
          submissionId: 's1',
          localPath: '/does/not/exist.jpg',
          capturedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),);
    final out = await bundle.exportFor('a1');
    final archive =
        ZipDecoder().decodeBytes(await out.readAsBytes());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, isNot(contains('photos/ph-missing.jpg')));
    final data =
        archive.files.firstWhere((f) => f.name == 'data.json');
    final json = jsonDecode(utf8.decode(data.content as List<int>))
        as Map<String, dynamic>;
    expect(
      ((json['photos'] as List).first as Map<String, dynamic>)['id'],
      'ph-missing',
    );
  });
}
