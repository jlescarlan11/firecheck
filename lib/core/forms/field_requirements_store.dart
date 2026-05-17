// lib/core/forms/field_requirements_store.dart
//
// On-device store for the `field_requirements.txt` sidecar that ships
// alongside the shapefile on Google Drive / FTP (Issue #43 +
// post-review). Saved here at import time and re-read on every form
// load, so a form designer can update validation rules by replacing
// the file in the assignment folder — no app rebuild.
//
// Resolution order at read time:
//   1. The downloaded file at [_filename] in the app documents dir.
//   2. Bundled `assets/field_requirements.txt` fallback.
//   3. [FieldRequirements.allRequired] — safe default if both are gone.
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String fieldRequirementsFilename = 'field_requirements.txt';

/// Persists the latest copy of the requirements config that came down
/// with an assignment. Overwrites the previous copy so the most recent
/// assignment's rules win — matches the user's mental model of
/// "whatever I uploaded most recently is what the app uses".
Future<File> writeFieldRequirements(Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, fieldRequirementsFilename));
  return file.writeAsBytes(bytes, flush: true);
}

/// Returns the saved body, or null when no file has been imported yet.
/// Never throws on missing/corrupt files — callers treat null as
/// "use the next fallback in the resolution order".
Future<String?> readFieldRequirements() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fieldRequirementsFilename));
    if (!file.existsSync()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

/// Deletes any cached copy. Provided for test cleanup; not wired to any
/// production code path today (an updated config simply overwrites).
Future<void> clearFieldRequirements() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fieldRequirementsFilename));
    if (file.existsSync()) await file.delete();
  } catch (_) {
    // Best-effort.
  }
}
