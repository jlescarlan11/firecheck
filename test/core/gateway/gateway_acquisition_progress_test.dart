import 'dart:async';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/drive/fake_drive_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
import 'package:firecheck/features/assignment/domain/shapefile_acquisition_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnverifiedSource extends FakeDriveApi {
  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    yield const DriveDownloadProgress(downloaded: 1, total: 2);
    yield const DriveDownloadProgress(downloaded: 2, total: 2, verifying: true);
    throw const ValidationFailure('Checksum mismatch');
  }
}

void main() {
  test(
      'persisted final byte enters validation and checksum failure never imports',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final acquire = ShapefileAcquisitionUseCase(
      shapefileImporter: ShapefileImporter(
        db: db,
        dbfParser: const DbfParser(),
        reprojector: Reprojector(),
      ),
      validator: ShapefileValidator(rules: []),
      reporter: FakeValidationFailureReporter(),
    );
    final events = await acquire
        .acquire(
          source: _UnverifiedSource(),
          assignment: const DriveAssignment(
            assignmentId: 'map',
            localAssignmentId: 'map',
            inputZipModifiedTime: 'v1',
            driveFolderId: '',
          ),
          enumeratorId: 'me',
          totalBytes: 2,
        )
        .toList();
    expect(events.map((e) => e.runtimeType), [
      AcquisitionProgress,
      AcquisitionProgress,
      AcquisitionValidating,
      AcquisitionFailed,
    ]);
    expect(
      events.whereType<AcquisitionProgress>().map((e) => e.downloaded),
      [0, 1],
    );
    expect(await db.select(db.assignments).get(), isEmpty);
    expect(await db.select(db.features).get(), isEmpty);
  });
}
