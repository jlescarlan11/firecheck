import 'dart:convert';

import 'package:firecheck/core/forms/assignment_form_store.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const formDefinitionAssetPath = 'assets/form_definition.json';

final formDefinitionRevisionProvider = StateProvider<int>((ref) => 0);
final formDefinitionVersionProvider = Provider<String?>((ref) => null);

final currentFormDefinitionProvider = FutureProvider<FormDefinition>(
  (ref) async {
    ref.watch(formDefinitionRevisionProvider);
    final requestedVersion = ref.watch(formDefinitionVersionProvider);
    final id = ref.watch(currentAssignmentProvider).valueOrNull?.id;
    return loadAssignmentFormDefinition(
      assignmentId: id,
      requestedVersion: requestedVersion,
    );
  },
  dependencies: [formDefinitionVersionProvider],
);

/// Resolves current or pinned definitions using the same assignment-local history.
Future<FormDefinition> loadAssignmentFormDefinition({
  String? assignmentId,
  String? requestedVersion,
}) async {
  final downloaded = assignmentId == null
      ? null
      : await readAssignmentForm(assignmentId, version: requestedVersion);
  if (assignmentId != null &&
      requestedVersion != null &&
      requestedVersion != 'legacy-v1' &&
      downloaded == null) {
    throw StateError(
      'Form version $requestedVersion is unavailable for this map. Refresh the map before editing this draft.',
    );
  }
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
}
