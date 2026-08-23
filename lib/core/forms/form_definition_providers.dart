import 'dart:convert';

import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const formDefinitionAssetPath = 'assets/form_definition.json';

final formDefinitionRevisionProvider = StateProvider<int>((ref) => 0);
final formDefinitionVersionProvider = Provider<String?>((ref) => null);

final currentFormDefinitionProvider = FutureProvider<FormDefinition>(
  (ref) async {
    ref.watch(formDefinitionRevisionProvider);
    final requestedVersion = ref.watch(formDefinitionVersionProvider);
    final downloaded = await readFormDefinition(version: requestedVersion);
    final raw = downloaded ??
        (requestedVersion == null || requestedVersion == 'legacy-v1'
            ? await rootBundle.loadString(formDefinitionAssetPath)
            : null);
    if (raw == null) return FormDefinition.legacy;
    try {
      return FormDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return FormDefinition.legacy;
    }
  },
  dependencies: [formDefinitionVersionProvider],
);
