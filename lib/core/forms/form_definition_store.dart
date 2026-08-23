import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const formDefinitionFilename = 'form_definition.json';

Future<File> writeFormDefinition(Uint8List bytes) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, formDefinitionFilename));
  final decoded =
      jsonDecode(String.fromCharCodes(bytes)) as Map<String, dynamic>;
  final version = decoded['version'] as String?;
  if (version == null || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(version)) {
    throw const FormatException('Unsafe or missing form version');
  }
  final written = await file.writeAsBytes(bytes, flush: true);
  await File(p.join(directory.path, 'form_definition_$version.json'))
      .writeAsBytes(bytes, flush: true);
  return written;
}

Future<String?> readFormDefinition({String? version}) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final filename = version == null
        ? formDefinitionFilename
        : 'form_definition_$version.json';
    final file = File(p.join(directory.path, filename));
    if (!file.existsSync()) return null;
    return file.readAsString();
  } on Object {
    return null;
  }
}
