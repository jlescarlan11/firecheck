import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<String?> showFeatureTypePicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => const _FeatureTypePicker(),
  );
}

class _FeatureTypePicker extends StatelessWidget {
  const _FeatureTypePicker();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.pickFeatureTypeTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const Key('feature-type-picker.building'),
              onPressed: () => Navigator.of(context).pop('building'),
              icon: const Icon(Icons.domain),
              label: Text(l.pickFeatureTypeBuilding),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const Key('feature-type-picker.road'),
              onPressed: () => Navigator.of(context).pop('road'),
              icon: const Icon(Icons.route),
              label: Text(l.pickFeatureTypeRoad),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancelLabel),
            ),
          ],
        ),
      ),
    );
  }
}
