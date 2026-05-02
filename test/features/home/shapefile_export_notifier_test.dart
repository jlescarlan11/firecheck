// test/features/home/shapefile_export_notifier_test.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
import 'package:flutter_test/flutter_test.dart';

ShapefileExportNotifier makeNotifier({
  required String assignmentId,
  required AppDatabase db,
  List<String>? capturedPaths,
}) {
  final exporter = ShapefileExporter(
    db: db,
    shareFile: (path) async {
      capturedPaths?.add(path);
    },
    tempDirOverride: Directory.systemTemp.createTempSync('notifier_test_'),
  );
  return ShapefileExportNotifier(
    assignmentId: assignmentId,
    exporter: exporter,
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('initial state is ExportIdle', () {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    expect(notifier.state, isA<ExportIdle>());
  });

  test('export with no features transitions Exporting then Failed', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add, fireImmediately: false);

    await notifier.export();

    expect(states, [
      isA<ExportExporting>(),
      isA<ExportFailed>(),
      isA<ExportIdle>(),
    ]);
    expect((states[1] as ExportFailed).failure, isA<NoCompletedFeatures>());
  });

  test('tapping export while Exporting is a no-op', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add, fireImmediately: false);

    final first = notifier.export();
    final second = notifier.export();

    await Future.wait([first, second]);

    expect(states.whereType<ExportExporting>(), hasLength(1));
  });

  test('after Failed state, notifier resets to Idle', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    await notifier.export();
    expect(notifier.state, isA<ExportIdle>());
  });
}
