// lib/core/forms/field_requirements_providers.dart
//
// Riverpod providers that load the [FieldRequirements] from the bundled .txt
// asset (Issue #43). Loader falls back to [FieldRequirements.allRequired]
// when the asset can't be read or parses to an empty config — see the
// fallback contract in [field_requirements.dart].
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _fieldRequirementsAssetPath = 'assets/field_requirements.txt';

/// Async load of the requirements config. Never throws — a missing or
/// malformed asset resolves to [FieldRequirements.allRequired].
final fieldRequirementsConfigProvider =
    FutureProvider<FieldRequirements>((ref) async {
  try {
    final body = await rootBundle.loadString(_fieldRequirementsAssetPath);
    return parseFieldRequirements(body);
  } catch (_) {
    return FieldRequirements.allRequired;
  }
});

/// Sync accessor used inside `build()` of widgets that need the requirements.
/// Falls back to [FieldRequirements.allRequired] while the FutureProvider is
/// in flight so the form is always usable.
final fieldRequirementsProvider = Provider<FieldRequirements>((ref) {
  return ref.watch(fieldRequirementsConfigProvider).valueOrNull ??
      FieldRequirements.allRequired;
});
