import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/google_drive_upload_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/cached_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/google_access_token_cache.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

      // Initialize Supabase in this background isolate.
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL'] ?? '',
        anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
      );

      // Opens the real on-disk Drift database in this background isolate.
      final db = AppDatabase();

      // Bail out if there is no active session — the foreground app will handle
      // the upload once the user signs in again.
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return true;

      final googleAuthRepo = CachedGoogleAuthRepository(
        auth: Supabase.instance.client.auth,
        cache: SecureStorageGoogleAccessTokenCache(
          FlutterSecureStorageAdapter(),
        ),
      );
      final uploadApi = GoogleDriveUploadApi(googleAuthRepo: googleAuthRepo);
      final repo = DriveUploadRepository(db);
      final worker = DriveUploadWorker(
        api: uploadApi,
        repo: repo,
        db: db,
        rootFolderId: rootFolderId,
      );
      try {
        await worker.drain();
      } on AuthFailure {
        // No fresh access token in the cache — foreground app will refresh
        // and the next periodic run will pick up where we left off.
        await db.close();
        return true;
      }
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
