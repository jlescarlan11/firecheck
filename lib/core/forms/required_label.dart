// lib/core/forms/required_label.dart
//
// Helpers that strip / append the trailing `*` from a form-field label
// based on the active [FieldRequirements]. Lets us flip a field between
// required and optional without touching the localized strings (which
// historically bake the `*` into the label itself).
import 'package:firecheck/core/forms/field_requirements.dart';

/// Decorates [base] with a trailing space + `*` when [requirements] mark
/// [key] as required, and strips any trailing ` *` when it's optional.
/// Whitespace is normalized so repeated calls are idempotent.
String requiredLabel(
  String base,
  FieldRequirements requirements,
  String key,
) {
  final stripped = base.replaceAll(RegExp(r'\s*\*\s*$'), '').trimRight();
  if (requirements.isRequired(key)) {
    return '$stripped *';
  }
  return stripped;
}
