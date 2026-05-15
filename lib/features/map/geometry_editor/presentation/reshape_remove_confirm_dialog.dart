import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<bool> showReshapeRemoveConfirm(
  BuildContext context, {
  required int currentRingLength,
}) async {
  final l = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final canConfirm = currentRingLength > 3;
      return AlertDialog(
        title: Text(l.reshapeRemoveConfirmTitle),
        content: Text(l.reshapeRemoveConfirmBody),
        actions: [
          TextButton(
            key: const Key('reshape.remove.cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancelLabel),
          ),
          FilledButton(
            key: const Key('reshape.remove.confirm'),
            onPressed:
                canConfirm ? () => Navigator.of(ctx).pop(true) : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC53030),
            ),
            child: Text(l.reshapeRemoveConfirmRemove),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
