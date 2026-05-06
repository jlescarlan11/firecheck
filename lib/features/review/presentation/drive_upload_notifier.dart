import 'dart:typed_data';

import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DriveUploadNotifier extends StateNotifier<DriveUploadState> {
  DriveUploadNotifier({
    required DriveApi driveApi,
    required AssignmentRepository assignmentRepository,
  })  : _driveApi = driveApi,
        _assignmentRepository = assignmentRepository,
        super(const DriveUploadIdle());

  final DriveApi _driveApi;
  final AssignmentRepository _assignmentRepository;
  String? _assignmentId;
  String? _enumeratorId;

  String _formatReferenceId(String id) =>
      'ASN-${id.substring(0, id.length.clamp(0, 8)).toUpperCase()}';

  /// Reads persisted Drive upload result from DB. Call once after construction.
  Future<void> initFromDb(String assignmentId, String enumeratorId) async {
    _assignmentId = assignmentId;
    _enumeratorId = enumeratorId;
    try {
      final result =
          await _assignmentRepository.getDriveUploadResult(assignmentId);
      if (!mounted) return;
      if (result != null) {
        state = DriveUploadSuccess(
          folderPath: result.folderPath,
          folderUrl: result.folderUrl,
          referenceId: _formatReferenceId(assignmentId),
          confirmedAt: result.confirmedAt,
        );
      }
    } catch (_) {
      if (!mounted) return;
      state = const DriveUploadFailure(
        message: 'Could not load upload status. Please try again.',
        canRetry: true,
      );
    }
  }

  Future<void> startUpload(
      List<({String filename, Uint8List bytes})> files) async {
    final assignmentId = _assignmentId;
    final enumeratorId = _enumeratorId;
    if (assignmentId == null || enumeratorId == null) return;

    if (files.isEmpty) {
      state = const DriveUploadFailure(
        message: 'No files collected for upload. '
            'Ensure field data is saved and try again.',
        canRetry: true,
      );
      return;
    }

    state = const DriveUploadInProgress(0.0);
    try {
      final result = await _driveApi.uploadAssignmentFiles(
        enumeratorId: enumeratorId,
        assignmentId: assignmentId,
        files: files,
      );
      final confirmedAt = DateTime.now();
      await _assignmentRepository.setDriveUploadResult(
        assignmentId: assignmentId,
        driveFolderPath: result.folderPath,
        driveFolderUrl: result.folderUrl,
        driveUploadConfirmedAt: confirmedAt,
      );
      if (!mounted) return;
      state = DriveUploadSuccess(
        folderPath: result.folderPath,
        folderUrl: result.folderUrl,
        referenceId: _formatReferenceId(assignmentId),
        confirmedAt: confirmedAt,
      );
    } on AuthFailure {
      if (!mounted) return;
      state = const DriveUploadFailure(
        message: 'Google Drive authentication expired. Please sign in again.',
        canRetry: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = DriveUploadFailure(
        message:
            'Could not reach Google Drive. Check your Wi-Fi and try again.',
        canRetry: true,
      );
    }
  }

  Future<void> retry(List<({String filename, Uint8List bytes})> files) async {
    state = const DriveUploadIdle();
    await startUpload(files);
  }

  /// Called by the queue-based upload path after DriveUploadWorker.drain().
  void applyQueueSuccess({
    required String folderPath,
    required DateTime confirmedAt,
    required String assignmentId,
  }) {
    state = DriveUploadSuccess(
      folderPath: folderPath,
      folderUrl: '',
      referenceId: _formatReferenceId(assignmentId),
      confirmedAt: confirmedAt,
    );
  }

  void applyQueueFailure(String message, {bool canRetry = true}) {
    state = DriveUploadFailure(message: message, canRetry: canRetry);
  }

  /// Test-only: force a specific state.
  void debugSetState(DriveUploadState s) => state = s;
}
