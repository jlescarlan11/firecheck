import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<String?> showOverrideReasonDialog(
  BuildContext context, {
  required double distanceMeters,
}) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final canContinue = controller.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(l.overrideTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.overrideBody(distanceMeters.round())),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('override.reason'),
                  controller: controller,
                  onChanged: (_) => setState(() {}),
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: l.overrideReasonHint,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.cancelLabel),
              ),
              FilledButton(
                onPressed: canContinue
                    ? () => Navigator.of(ctx).pop(controller.text.trim())
                    : null,
                child: Text(l.overrideContinue),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}
