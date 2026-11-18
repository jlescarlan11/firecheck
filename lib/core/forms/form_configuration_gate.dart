import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Avoid mounting editable fields with another version's fallback settings.
class FormConfigurationGate extends ConsumerWidget {
  const FormConfigurationGate({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final definition = ref.watch(currentFormDefinitionProvider);
    final requirements = ref.watch(fieldRequirementsConfigProvider);
    final error = definition.error ?? requirements.error;
    if (error != null)
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('$error'),
      ));
    if (definition.isLoading || requirements.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return child;
  }
}
