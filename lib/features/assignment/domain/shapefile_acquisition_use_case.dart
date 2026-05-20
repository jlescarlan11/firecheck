// lib/features/assignment/domain/shapefile_acquisition_use_case.dart
//
// Coordinates the multi-step shapefile acquisition pipeline:
//   download → persist sidecar → validate → import → publish canonical
// features. Emits ShapefileAcquisitionEvents so the calling notifier can
// map them onto its state machine without owning the pipeline itself.
//
// Extracted from GetMapsNotifier to keep that notifier focused on
// state-machine transitions and user-driven control (cancel, select,
// reset, transport selection). The same use case can serve a future
// FTP-only or background-isolate caller.
import 'dart:async';

import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/forms/field_requirements_store.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
import 'package:firecheck/features/assignment/data/assignment_name_resolver.dart';
import 'package:firecheck/features/assignment/data/canonical_feature_publisher.dart';
import 'package:flutter/foundation.dart';

sealed class ShapefileAcquisitionEvent {
  const ShapefileAcquisitionEvent();
}

class AcquisitionProgress extends ShapefileAcquisitionEvent {
  const AcquisitionProgress({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
}

class AcquisitionValidating extends ShapefileAcquisitionEvent {
  const AcquisitionValidating();
}

/// Validation completed with warnings only. Stream ends here; caller
/// resumes the pipeline via [ShapefileAcquisitionUseCase.importPending]
/// once the user acknowledges.
@immutable
class AcquisitionWarning extends ShapefileAcquisitionEvent {
  AcquisitionWarning({
    required List<String> warnings,
    required Map<String, Uint8List> pendingFiles,
    required Map<String, String> expectedMd5s,
  })  : warnings = List.unmodifiable(warnings),
        pendingFiles = Map.unmodifiable(pendingFiles),
        expectedMd5s = Map.unmodifiable(expectedMd5s);

  final List<String> warnings;
  final Map<String, Uint8List> pendingFiles;
  final Map<String, String> expectedMd5s;
}

class AcquisitionImporting extends ShapefileAcquisitionEvent {
  const AcquisitionImporting();
}

/// Import + canonical publish completed. Caller transitions to the
/// next stage (typically offline tile download).
class AcquisitionImported extends ShapefileAcquisitionEvent {
  const AcquisitionImported();
}

/// Import threw. Treated as non-fatal upstream: the user can still open
/// the map without imported features. Caller decides terminal state.
class AcquisitionImportFailed extends ShapefileAcquisitionEvent {
  const AcquisitionImportFailed();
}

class AcquisitionFailed extends ShapefileAcquisitionEvent {
  const AcquisitionFailed({required this.failure, required this.isRetryable});
  final Failure failure;
  final bool isRetryable;
}

class ShapefileAcquisitionUseCase {
  ShapefileAcquisitionUseCase({
    required this.shapefileImporter,
    required this.validator,
    required this.reporter,
    AssignmentNameResolver? assignmentNameResolver,
    CanonicalFeaturePublisher? canonicalFeaturePublisher,
    this.onRequirementsUpdated,
  })  : assignmentNameResolver =
            assignmentNameResolver ?? const NoopAssignmentNameResolver(),
        canonicalFeaturePublisher =
            canonicalFeaturePublisher ?? const NoopCanonicalFeaturePublisher();

  final ShapefileImporter shapefileImporter;
  final ShapefileValidator validator;
  final ValidationFailureReporter reporter;
  final AssignmentNameResolver assignmentNameResolver;
  final CanonicalFeaturePublisher canonicalFeaturePublisher;
  final void Function()? onRequirementsUpdated;

  /// Full path: download the assignment, persist any sidecar, validate,
  /// and — if validation passes without warnings — import + publish.
  /// Stream terminates with one of: [AcquisitionImported],
  /// [AcquisitionImportFailed], [AcquisitionWarning], or [AcquisitionFailed].
  Stream<ShapefileAcquisitionEvent> acquire({
    required DriveApi source,
    required DriveAssignment assignment,
    required String enumeratorId,
    required int totalBytes,
    bool unrestricted = false,
  }) async* {
    yield AcquisitionProgress(downloaded: 0, total: totalBytes);

    Map<String, Uint8List>? shapefiles;
    var shapeMd5s = <String, String>{};
    try {
      await for (final event in source.downloadShapefiles(assignment.assignmentId)) {
        switch (event) {
          case DriveDownloadProgress(:final downloaded, :final total):
            yield AcquisitionProgress(downloaded: downloaded, total: total);
          case DriveDownloadComplete(:final files, :final expectedMd5s):
            shapefiles = files;
            shapeMd5s = expectedMd5s;
        }
      }
    } catch (e) {
      yield AcquisitionFailed(
        failure: NetworkFailure(e.toString()),
        isRetryable: true,
      );
      return;
    }

    if (shapefiles == null) {
      yield const AcquisitionFailed(
        failure: NetworkFailure('Download completed with no data'),
        isRetryable: true,
      );
      return;
    }

    // Pull `field_requirements.txt` out of the download bundle before
    // validation runs (FileSetRule would otherwise flag it as extra) and
    // persist it so the form layer can re-read updated rules. Skipping
    // a missing sidecar is fine — the form falls back to the bundled
    // asset.
    final configKey = shapefiles.keys.firstWhere(
      (k) => k.toLowerCase() == fieldRequirementsFilename,
      orElse: () => '',
    );
    if (configKey.isNotEmpty) {
      final bytes = shapefiles.remove(configKey);
      shapeMd5s.remove(configKey);
      if (bytes != null) await _persistFieldRequirements(bytes);
    }

    yield const AcquisitionValidating();
    final report = validator.validate(
      shapefiles,
      shapeMd5s,
      relaxedMode: unrestricted,
    );

    if (report.hasFatals) {
      final fatal = report.fatal!;
      unawaited(
        reporter.report(
          assignmentId: assignment.assignmentId,
          enumeratorId: enumeratorId,
          failedRule: fatal.ruleName,
          message: fatal.userMessage,
          fileChecksum: fatal.computedChecksum,
        ),
      );
      yield AcquisitionFailed(
        failure: ShapefileValidationFailure(
          fatal.userMessage,
          ruleName: fatal.ruleName,
        ),
        isRetryable: false,
      );
      return;
    }

    if (report.hasWarnings) {
      yield AcquisitionWarning(
        warnings: report.warnings.map((w) => w.userMessage).toList(),
        pendingFiles: shapefiles,
        expectedMd5s: shapeMd5s,
      );
      return;
    }

    yield* _importAndPublish(
      assignment: assignment,
      enumeratorId: enumeratorId,
      files: shapefiles,
    );
  }

  /// Resumes the pipeline after the user acknowledges an
  /// [AcquisitionWarning]. Re-uses the bytes already downloaded so we
  /// don't pay the network round-trip again.
  Stream<ShapefileAcquisitionEvent> importPending({
    required DriveAssignment assignment,
    required String enumeratorId,
    required Map<String, Uint8List> files,
  }) =>
      _importAndPublish(
        assignment: assignment,
        enumeratorId: enumeratorId,
        files: files,
      );

  /// Delta-skip path: the assignment is already on disk, but we still
  /// want to refresh the `field_requirements.txt` sidecar because Drive
  /// doesn't reliably bump the folder modifiedTime when only the sidecar
  /// changes. Errors are swallowed — the caller should always proceed to
  /// the next stage regardless.
  Future<void> refreshSidecar({
    required DriveApi source,
    required String assignmentId,
  }) async {
    try {
      final bytes = await source.fetchFieldRequirementsSidecar(assignmentId);
      if (bytes != null) await _persistFieldRequirements(bytes);
    } catch (_) {
      // Non-fatal.
    }
  }

  Stream<ShapefileAcquisitionEvent> _importAndPublish({
    required DriveAssignment assignment,
    required String enumeratorId,
    required Map<String, Uint8List> files,
  }) async* {
    yield const AcquisitionImporting();

    // Resolve canonical Supabase UUID by name so local records line up
    // with the remote DB. Falls back to the locally-derived id when
    // offline or when no remote assignment matches.
    final resolvedId =
        await assignmentNameResolver.resolveId(assignment.assignmentId) ??
            assignment.localAssignmentId;

    try {
      await shapefileImporter.importShapefiles(
        files,
        resolvedId,
        assignment.inputZipModifiedTime,
        assignment.driveFolderId,
        enumeratorId,
        assignmentDisplayName: resolvedId != assignment.assignmentId
            ? assignment.assignmentId
            : null,
      );
    } catch (_) {
      yield const AcquisitionImportFailed();
      return;
    }

    // Publish canonical shapefile features so subsequent attribution
    // uploads pass the features → assignments membership join.
    // Idempotent via ON CONFLICT; safe under re-imports / concurrent
    // enumerators. Publisher swallows its own errors.
    await canonicalFeaturePublisher.publish(resolvedId);

    yield const AcquisitionImported();
  }

  Future<void> _persistFieldRequirements(Uint8List bytes) async {
    try {
      await writeFieldRequirements(bytes);
      onRequirementsUpdated?.call();
    } catch (_) {
      // Non-fatal — the form falls back to the bundled asset.
    }
  }
}
