import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';

/// Network surface area required by SyncWorker. Real impl in
/// supabase_sync_api.dart; in-memory fake in fake_sync_api.dart.
abstract class SyncApi {
  Future<SyncOutcome> uploadSubmission(Map<String, dynamic> payload);

  /// Uploads a photo file to Storage, returning the storage_path on success.
  /// Encoded as a SyncOutcome to handle 401/409/permanent/transient uniformly.
  Future<({SyncOutcome outcome, String? storagePath})> uploadPhotoFile({
    required String submissionId,
    required String photoId,
    required File file,
  });

  Future<SyncOutcome> markPhotoUploaded({
    required String photoId,
    required String storagePath,
  });

  Future<SyncOutcome> uploadNewFeature(Feature feature);
}
