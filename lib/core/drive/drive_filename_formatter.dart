import 'package:path/path.dart' as p;

String formatPhotoFilename(String assignmentId, String originalFilename) {
  final ext = p.extension(originalFilename).toLowerCase();
  final stem = p.basenameWithoutExtension(originalFilename);
  final sanitized = _sanitizeStem(stem);
  return '${assignmentId}_$sanitized$ext';
}

String formatShapefileFilename(String assignmentId) => '$assignmentId.zip';

String _sanitizeStem(String stem) {
  var result = stem.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  result = result.replaceAll(RegExp(r'_+'), '_');
  result = result.replaceAll(RegExp(r'^_+|_+$'), '');
  return result.isEmpty ? 'file' : result;
}
