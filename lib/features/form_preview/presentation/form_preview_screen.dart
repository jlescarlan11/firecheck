import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FormPreviewScreen extends ConsumerStatefulWidget {
  const FormPreviewScreen({super.key});

  @override
  ConsumerState<FormPreviewScreen> createState() => _FormPreviewScreenState();
}

class _FormPreviewScreenState extends ConsumerState<FormPreviewScreen> {
  double _areaSqMeters = 100;
  bool _doesNotExist = false;

  @override
  Widget build(BuildContext context) {
    final definitionAsync = ref.watch(currentFormDefinitionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Form behavior preview')),
      body: definitionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Invalid definition: $error')),
        data: (definition) {
          final formContext = FormEvaluationContext(
            answers: {
              'building.doesNotExist': _doesNotExist,
              'road.doesNotExist': _doesNotExist,
            },
            geometry: GeometrySignal(
              featureType: 'building',
              vertexCount: 4,
              areaSqMeters: _areaSqMeters,
            ),
          );
          final result = previewFormDefinition(definition, formContext);
          final targets =
              definition.visibilityRules.map((rule) => rule.target).toSet();
          return ListView(
            padding: appPageInsets(context),
            children: [
              AppPageIntro(
                  title: AppLocalizations.of(context)!.formRulesTitle,
                  subtitle: AppLocalizations.of(context)!.designFormRulesBody),
              Text(
                '${definition.name} · ${definition.version}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                key: const Key('form-preview-does-not-exist'),
                title: const Text('Does not exist / demolished'),
                value: _doesNotExist,
                onChanged: (value) => setState(() => _doesNotExist = value),
              ),
              Text('Geometry area: ${_areaSqMeters.round()} m²'),
              Slider(
                key: const Key('form-preview-area'),
                value: _areaSqMeters,
                max: 1000,
                divisions: 100,
                onChanged: (value) => setState(() => _areaSqMeters = value),
              ),
              const Divider(),
              if (targets.isEmpty)
                const ListTile(
                  title: Text('No conditional sections'),
                  subtitle:
                      Text('Every section uses the default visible state.'),
                ),
              for (final target in targets)
                ListTile(
                  key: Key('form-preview-target-$target'),
                  leading: Icon(
                    result.visibleTargets.contains(target)
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  title: Text(target),
                  subtitle: Text(
                    result.visibleTargets.contains(target)
                        ? 'Visible'
                        : 'Hidden',
                  ),
                ),
              const Divider(),
              for (final constraint in definition.constraints)
                ListTile(
                  leading: const Icon(Icons.rule),
                  title: Text(constraint.field),
                  subtitle: Text(constraint.hint ?? 'Validation constraint'),
                ),
            ],
          );
        },
      ),
    );
  }
}
