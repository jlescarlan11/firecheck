import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<File> _snapshot(String id) async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(
      dir.path, 'assignment_forms', Uri.encodeComponent(id), 'config.json'));
}

/// One atomic snapshot keeps requirements, current definition and history together.
Future<void> writeAssignmentForms(String id,
    {Uint8List? requirements, Uint8List? definition}) async {
  final file = await _snapshot(id);
  final previous = file.existsSync()
      ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
      : <String, dynamic>{};
  final versions =
      Map<String, dynamic>.from(previous['versions'] as Map? ?? {});
  String? body;
  if (definition != null) {
    body = utf8.decode(definition);
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final version = decoded['version'] as String?;
    if (version == null || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(version)) {
      throw const FormatException('Unsafe or missing form version');
    }
    versions[version] = body;
  }
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(
      jsonEncode({
        'requirements': requirements == null ? null : utf8.decode(requirements),
        'definition': body,
        'versions': versions,
      }),
      flush: true);
  await temporary.rename(file.path);
}

Future<String?> readAssignmentForm(String id,
    {bool requirements = false, String? version}) async {
  final file = await _snapshot(id);
  if (File('${file.path}.pending').existsSync()) {
    throw StateError(
        'Refresh this map in Download maps to finish loading its form settings.');
  }
  if (!file.existsSync()) {
    final dir = await getApplicationDocumentsDirectory();
    if (File(p.join(dir.path, 'field_requirements.txt')).existsSync() ||
        File(p.join(dir.path, 'form_definition.json')).existsSync()) {
      throw StateError(
          'Refresh this map in Download maps to load its form settings. Your saved work is kept.');
    }
    return null;
  }
  final config = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  if (requirements) return config['requirements'] as String?;
  if (version != null) return (config['versions'] as Map?)?[version] as String?;
  return config['definition'] as String?;
}

Future<void> markAssignmentFormsPending(String id,
    {required bool pending}) async {
  final snapshot = await _snapshot(id);
  final marker = File('${snapshot.path}.pending');
  if (pending) {
    await marker.parent.create(recursive: true);
    await marker.writeAsString('Refresh required', flush: true);
  } else if (marker.existsSync()) {
    await marker.delete();
  }
}
