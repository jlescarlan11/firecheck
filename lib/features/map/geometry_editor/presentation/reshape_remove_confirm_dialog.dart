import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<bool> showReshapeRemoveConfirm(
  BuildContext context, {
  required int currentRingLength,
  // Polygons need ≥3 vertices to remain a valid ring; polylines need ≥2.
  // The controller's removeVertex uses the same floor — keep these in sync
  // or the last allowed delete becomes un-confirmable from this dialog.
  required int minRingLength,
}) async {
  final l = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final canConfirm = currentRingLength > minRingLength;
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
