// lib/core/drive/fake_drive_api.dart
import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

class FakeDriveApi implements DriveApi {
  FakeDriveApi({
    List<DriveAssignment>? assignments,
    int zipSize = 1024,
    Uint8List? downloadComplete,
    List<DriveDownloadEvent>? downloadEvents,
    Exception? listError,
    Exception? downloadError,
  })  : _assignments = assignments ?? [],
        _zipSize = zipSize,
        _downloadComplete = downloadComplete,
        _downloadEvents = downloadEvents,
        _listError = listError,
        _downloadError = downloadError;

  final List<DriveAssignment> _assignments;
  final int _zipSize;
  final Uint8List? _downloadComplete;
  final List<DriveDownloadEvent>? _downloadEvents;
  final Exception? _listError;
  final Exception? _downloadError;

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    if (_listError != null) throw _listError;
    return List.unmodifiable(_assignments);
  }

  @override
  Future<int> getInputZipSize(String assignmentId) async => _zipSize;

  @override
  Stream<DriveDownloadEvent> downloadInputZip(String assignmentId) async* {
    if (_downloadError != null) throw _downloadError;
    if (_downloadEvents != null) {
      for (final e in _downloadEvents) {
        yield e;
      }
      return;
    }
    yield DriveDownloadComplete(_downloadComplete ?? Uint8List(0));
  }
}
