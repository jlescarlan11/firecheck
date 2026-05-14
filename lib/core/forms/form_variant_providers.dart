// lib/core/forms/form_variant_providers.dart
//
// Loads the form-variant config from the bundled JSON asset and exposes a
// provider that resolves the current variant for the active enumerator
// and assignment.
import 'dart:convert';

import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/forms/form_variant.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _formVariantAssetPath = 'assets/form_variants.json';

/// Reads + parses the variant config from the bundled asset. Falls back to
/// an empty (default-only) config if the asset is missing or unparseable so
/// the form never crashes for a configuration error — it just degrades to
/// the standard variant.
final formVariantConfigProvider = FutureProvider<FormVariantConfig>((ref) async {
  try {
    final raw = await rootBundle.loadString(_formVariantAssetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return FormVariantConfig.fromJson(json);
  } catch (_) {
    return FormVariantConfig.empty;
  }
});

/// The variant in effect for the current enumerator + assignment context.
/// Sync provider — falls back to the default variant while the JSON load
/// is in flight so the form is always usable.
final currentFormVariantProvider = Provider<FormVariant>((ref) {
  final cfg = ref.watch(formVariantConfigProvider).valueOrNull;
  if (cfg == null) return FormVariant.defaultVariant;
  final userId = ref.watch(currentUserIdProvider);
  final assignment = ref.watch(currentAssignmentProvider).valueOrNull;
  // FireCheck doesn't model LGUs as a first-class column today — campaigns
  // are the closest aggregate (one campaign typically covers one LGU /
  // pilot region), so the variant config treats campaignId as the LGU key.
  return cfg.resolve(
    enumeratorId: userId,
    lguId: assignment?.campaignId,
  );
});
