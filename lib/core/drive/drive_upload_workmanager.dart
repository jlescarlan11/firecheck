import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
// TODO(task-10): replace FakeDriveUploadApi with GoogleDriveUploadApi once
// lib/core/drive/google_drive_upload_api.dart is implemented.
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';

const _periodicTaskName = 'firecheck.drive_upload.periodic';

@pragma('vm:entry-point')
void driveUploadCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Only proceed if Wi-Fi is available.
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity != ConnectivityResult.wifi) return true;

      await dotenv.load();
      final rootFolderId = dotenv.env['DRIVE_UPLOAD_FOLDER_ID'] ?? '';
      if (rootFolderId.isEmpty) return false;

      // Opens the real on-disk Drift database in this background isolate.
      final db = AppDatabase();
      // TODO(task-10): replace with GoogleDriveUploadApi(googleSignIn: signIn)
      // once the real upload API is implemented.
      final uploadApi = FakeDriveUploadApi();
      final repo = DriveUploadRepository(db);
      final worker = DriveUploadWorker(
        api: uploadApi,
        repo: repo,
        db: db,
        rootFolderId: rootFolderId,
      );
      await worker.drain();
      await db.close();
      return true;
    } on Object {
      return false;
    }
  });
}

Future<void> registerPeriodicDriveUpload() async {
  await Workmanager().initialize(driveUploadCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _periodicTaskName,
    'firecheck.drive_upload',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> cancelPeriodicDriveUpload() async {
  await Workmanager().cancelByUniqueName(_periodicTaskName);
}
