// lib/core/drive/drive_upload_providers.dart
import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/drive/drive_upload_controller.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/enqueue_assignment_use_case.dart';
import 'package:firecheck/core/drive/finalize_assignment_upload_use_case.dart';
import 'package:firecheck/core/drive/google_drive_upload_api.dart';
import 'package:firecheck/core/supabase/supabase_client_provider.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final driveUploadRepoProvider = Provider<DriveUploadRepository>((ref) {
  return DriveUploadRepository(ref.watch(appDatabaseProvider));
});

final driveUploadWorkerProvider = Provider<DriveUploadWorker>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return DriveUploadWorker(
    api: GoogleDriveUploadApi(
      googleAuthRepo: ref.watch(googleAuthRepositoryProvider),
    ),
    repo: ref.watch(driveUploadRepoProvider),
    db: ref.watch(appDatabaseProvider),
    // Per-enumerator Drive subfolder. Prefer the Google email so the
    // admin can identify each enumerator's submissions at a glance.
    // Falls back to the Supabase user UUID when email is absent.
    enumeratorIdentifier: () =>
        client.auth.currentUser?.email ?? client.auth.currentUser?.id,
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

final driveUploadAuditRepositoryProvider =
    Provider<DriveUploadAuditRepository>((ref) {
  return DriveUploadAuditRepository(ref.watch(supabaseClientProvider));
});

final finalizeAssignmentUploadUseCaseProvider =
    Provider<FinalizeAssignmentUploadUseCase>((ref) {
  return FinalizeAssignmentUploadUseCase(
    db: ref.watch(appDatabaseProvider),
    repo: ref.watch(driveUploadRepoProvider),
    assignmentRepo: ref.watch(assignmentRepositoryProvider),
    auditRepo: ref.watch(driveUploadAuditRepositoryProvider),
  );
});
