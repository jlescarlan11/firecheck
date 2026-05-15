import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

enum ReshapeAction { openForm, reshape }

Future<ReshapeAction?> showReshapeActionSheet(
  BuildContext context, {
  required bool locked,
}) {
  final l = AppLocalizations.of(context)!;
  return showModalBottomSheet<ReshapeAction>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l.reshapeActionSheetTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              dense: true,
            ),
            ListTile(
              key: const Key('reshape.actionsheet.openForm'),
              leading: const Icon(Icons.edit_document),
              title: Text(l.reshapeActionSheetOpenForm),
              onTap: () => Navigator.of(ctx).pop(ReshapeAction.openForm),
            ),
            ListTile(
              key: const Key('reshape.actionsheet.reshape'),
              enabled: !locked,
              leading: const Icon(Icons.share_location),
              title: Text(l.reshapeActionSheetReshape),
              onTap: locked
                  ? null
                  : () => Navigator.of(ctx).pop(ReshapeAction.reshape),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l.cancelLabel),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    },
  );
}
