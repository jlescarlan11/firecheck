// lib/core/forms/field_requirements_providers.dart
//
// Riverpod providers that load the [FieldRequirements] (Issue #43).
//
// Resolution order:
//   1. The .txt downloaded with the assignment (writeable, app docs dir).
//   2. The bundled `assets/field_requirements.txt` (build-time default).
//   3. [FieldRequirements.allRequired] — safe fallback so a misconfigured
//      deploy can't silently weaken validation.
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/field_requirements_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _fieldRequirementsAssetPath = 'assets/field_requirements.txt';

/// Bump this provider after writing a fresh `field_requirements.txt` to
/// app-docs (i.e. when an assignment import lands) so the downstream
/// FutureProvider re-reads instead of serving the previously-cached value.
final fieldRequirementsRevisionProvider = StateProvider<int>((_) => 0);

/// Async load of the requirements config. Never throws — a missing or
/// malformed source at every step resolves to [FieldRequirements.allRequired].
final fieldRequirementsConfigProvider =
    FutureProvider<FieldRequirements>((ref) async {
  ref.watch(fieldRequirementsRevisionProvider);
  // 1. Imported-from-assignment file.
  final downloaded = await readFieldRequirements();
  if (downloaded != null) {
    return parseFieldRequirements(downloaded);
  }
  // 2. Bundled asset.
  try {
    final body = await rootBundle.loadString(_fieldRequirementsAssetPath);
    return parseFieldRequirements(body);
  } catch (_) {
    // 3. Safe fallback.
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
