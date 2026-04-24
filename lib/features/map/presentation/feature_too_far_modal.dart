import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<bool> showFeatureTooFarModal(
  BuildContext context, {
  required double distanceMeters,
}) async {
  final l = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.featureTooFarTitle),
      content: Text(l.featureTooFarBody(distanceMeters.round())),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.continueAnyway),
        ),
      ],
    ),
  );
  return result ?? false;
}
