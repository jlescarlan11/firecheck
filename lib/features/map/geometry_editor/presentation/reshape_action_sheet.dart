import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

enum ReshapeAction { openForm, reshape, split, merge }

Future<ReshapeAction?> showReshapeActionSheet(
  BuildContext context, {
  required bool locked,
  String? featureType,
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
            if (featureType == 'building') ...[
              ListTile(
                key: const Key('reshape.actionsheet.split'),
                enabled: !locked,
                leading: const Icon(Icons.call_split),
                title: const Text('Split polygon'),
                onTap: locked
                    ? null
                    : () => Navigator.of(ctx).pop(ReshapeAction.split),
              ),
              ListTile(
                key: const Key('reshape.actionsheet.merge'),
                enabled: !locked,
                leading: const Icon(Icons.merge),
                title: const Text('Merge with adjacent polygon'),
                onTap: locked
                    ? null
                    : () => Navigator.of(ctx).pop(ReshapeAction.merge),
              ),
            ],
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
