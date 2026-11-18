import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/survey_integration_fixture.dart';

void main() {
  test(
      'private additional building and road drafts on completed features stay out of actual DBF exports',
      () async {
    final h = await SurveyIntegrationFixture.ready(shared: false);
    addTearDown(() async {
      await h.db.close();
      await h.directory.delete(recursive: true);
    });
    final now = DateTime.utc(2026);
    await h.db.into(h.db.features).insert(
          FeaturesCompanion.insert(
            id: 'road',
            assignmentId: 'a1',
            featureType: 'road',
            status: const Value('complete'),
            geometryGeojson:
                '{"type":"LineString","coordinates":[[123.882,10.318],[123.883,10.319]]}',
            createdAt: now,
          ),
        );
    for (final entry in [
      (id: 'accepted-building', feature: 'f1', status: 'uploaded'),
      (id: 'private-building', feature: 'f1', status: 'draft'),
      (id: 'accepted-road', feature: 'road', status: 'queued'),
      (id: 'private-road', feature: 'road', status: 'in_progress'),
    ]) {
      await h.db.into(h.db.submissions).insert(
            SubmissionsCompanion.insert(
              id: entry.id,
              featureId: entry.feature,
              syncStatus: Value(entry.status),
              submittedBy: const Value(integrationActor),
              isAdditionalObservation: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (entry.feature == 'f1') {
        await h.db.into(h.db.buildingAttributes).insert(
              BuildingAttributesCompanion.insert(
                submissionId: entry.id,
                buildingName: Value(
                  entry.id.startsWith('private')
                      ? 'SECRET_BUILDING_DRAFT'
                      : 'Accepted additional',
                ),
                ra9514Type: const Value('C'),
              ),
            );
      } else {
        await h.db.into(h.db.roadAttributes).insert(
              RoadAttributesCompanion.insert(
                submissionId: entry.id,
                roadName: Value(
                  entry.id.startsWith('private')
                      ? 'SECRET_ROAD_DRAFT'
                      : 'Accepted road',
                ),
                widthMeters: const Value(4),
              ),
            );
      }
    }
    await h.db.into(h.db.photos).insert(
          PhotosCompanion.insert(
            id: 'private-photo',
            submissionId: 'private-building',
            localPath: h.source,
            storagePath: const Value('SECRET_DRAFT_PHOTO.jpg'),
            capturedAt: now,
            createdAt: now,
          ),
        );
    final (failure, components) = await ShapefileExporter(
      db: h.db,
      tempDirOverride: h.directory,
      supabaseUrl: 'https://example.test',
    ).exportToFile(assignmentId: 'a1');
    expect(failure, isNull);
    final buildingBytes = await File(
      components!.singleWhere((c) => c.filename == 'buildings.dbf').path,
    ).readAsBytes();
    final roadBytes = await File(
      components.singleWhere((c) => c.filename == 'roads.dbf').path,
    ).readAsBytes();
    expect(ByteData.sublistView(buildingBytes).getUint32(4, Endian.little), 2);
    expect(ByteData.sublistView(roadBytes).getUint32(4, Endian.little), 1);
    expect(latin1.decode(buildingBytes), contains('Hall'));
    expect(latin1.decode(buildingBytes), contains('Accepted additional'));
    expect(latin1.decode(roadBytes), contains('Accepted road'));
    expect(latin1.decode(buildingBytes), isNot(contains('SECRET')));
    expect(latin1.decode(roadBytes), isNot(contains('SECRET')));
  });
}
