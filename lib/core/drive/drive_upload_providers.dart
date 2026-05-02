// lib/core/drive/drive_upload_providers.dart
import 'package:firecheck/core/drive/drive_upload_controller.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/enqueue_assignment_use_case.dart';
import 'package:firecheck/core/drive/google_drive_upload_api.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Overridden in main.dart with a real GoogleSignIn instance.
final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  throw UnimplementedError('Override googleSignInProvider in main.dart');
});

final driveUploadRepoProvider = Provider<DriveUploadRepository>((ref) {
  return DriveUploadRepository(ref.watch(appDatabaseProvider));
});

final driveUploadWorkerProvider = Provider<DriveUploadWorker>((ref) {
  final rootFolderId = dotenv.env['DRIVE_UPLOAD_FOLDER_ID'] ?? '';
  return DriveUploadWorker(
    api: GoogleDriveUploadApi(
      googleSignIn: ref.watch(googleSignInProvider),
    ),
    repo: ref.watch(driveUploadRepoProvider),
    db: ref.watch(appDatabaseProvider),
    rootFolderId: rootFolderId,
  );
});

final driveUploadPreferencesProvider = Provider<DriveUploadPreferences>((ref) {
  return DriveUploadPreferences(ref.watch(secureStorageProvider));
});

final driveUploadNotifierProvider =
    StateNotifierProvider<DriveUploadNotifier, DriveUploadState>((ref) {
  return DriveUploadNotifier(
    repo: ref.watch(driveUploadRepoProvider),
    worker: ref.watch(driveUploadWorkerProvider),
  );
});

final driveUploadControllerProvider = Provider<DriveUploadController>((ref) {
  return DriveUploadController(
    onDrain: () => ref.read(driveUploadWorkerProvider).drain(),
    preferences: ref.watch(driveUploadPreferencesProvider),
  );
});

final enqueueAssignmentUseCaseProvider =
    Provider<EnqueueAssignmentUseCase>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return EnqueueAssignmentUseCase(
    db: db,
    repo: ref.watch(driveUploadRepoProvider),
    exporter: ShapefileExporter(db: db),
  );
});
