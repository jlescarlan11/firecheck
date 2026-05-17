import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

class FakeDriveApi implements DriveApi {
  FakeDriveApi({
    List<DriveAssignment>? assignments,
    int totalSize = 1024,
    Map<String, Uint8List>? downloadComplete,
    Map<String, String>? expectedMd5s,
    List<DriveDownloadEvent>? downloadEvents,
    Exception? listError,
    Exception? downloadError,
    Exception? uploadError,
    ({String folderPath, String folderUrl})? uploadResult,
    Uint8List? fieldRequirementsSidecar,
  })  : _assignments = assignments ?? [],
        _totalSize = totalSize,
        _downloadComplete = downloadComplete,
        _expectedMd5s = expectedMd5s ?? {},
        _downloadEvents = downloadEvents,
        _listError = listError,
        _downloadError = downloadError,
        _uploadError = uploadError,
        _uploadResult = uploadResult,
        _fieldRequirementsSidecar = fieldRequirementsSidecar;

  final List<DriveAssignment> _assignments;
  final int _totalSize;
  final Map<String, Uint8List>? _downloadComplete;
  final Map<String, String> _expectedMd5s;
  final List<DriveDownloadEvent>? _downloadEvents;
  final Exception? _listError;
  final Exception? _downloadError;
  final Exception? _uploadError;
  final ({String folderPath, String folderUrl})? _uploadResult;
  final Uint8List? _fieldRequirementsSidecar;

  /// True after [fetchFieldRequirementsSidecar] runs at least once. Lets
  /// notifier tests assert the delta-skip path still refreshes the sidecar.
  bool fetchFieldRequirementsSidecarCalled = false;

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    if (_listError != null) throw _listError;
    return List.unmodifiable(_assignments);
  }

  @override
  Future<int> getTotalSize(String assignmentId) async {
    assert(
      _assignments.any((a) => a.assignmentId == assignmentId),
      'FakeDriveApi: unknown assignmentId "$assignmentId"',
    );
    return _totalSize;
  }

  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    assert(
      _assignments.any((a) => a.assignmentId == assignmentId),
      'FakeDriveApi: unknown assignmentId "$assignmentId"',
    );
    if (_downloadError != null) throw _downloadError;
    if (_downloadEvents != null) {
      for (final e in _downloadEvents) {
        yield e;
      }
      return;
    }
    yield DriveDownloadComplete(_downloadComplete ?? {}, _expectedMd5s);
  }

  @override
  Future<Uint8List?> fetchFieldRequirementsSidecar(String assignmentId) async {
    fetchFieldRequirementsSidecarCalled = true;
    return _fieldRequirementsSidecar;
  }

  @override
  Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
    required String enumeratorId,
    required String assignmentId,
    required List<({String filename, Uint8List bytes})> files,
  }) async {
    if (_uploadError != null) throw _uploadError;
    return _uploadResult ??
        (
          folderPath: 'FieldData/$enumeratorId/2026-05-02/',
          folderUrl: 'https://drive.google.com/drive/folders/fake-folder-id',
        );
  }
}
