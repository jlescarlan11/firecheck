import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class StartUploadButton extends StatelessWidget {
  const StartUploadButton({
    required this.enabled,
    required this.onPressed,
    this.alreadyUploaded = false,
    this.sharedMap = false,
    super.key,
  });
  final bool enabled;
  final bool alreadyUploaded;
  final bool sharedMap;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final btn = SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(sharedMap
              ? (alreadyUploaded ? 'Up to date' : 'Sync changes')
              : alreadyUploaded
                  ? 'Uploaded'
                  : l.startUploadButton),
        ),
      ),
    );
    if (enabled) return btn;
    return Tooltip(
      message: alreadyUploaded
          ? 'No new changes to sync.'
          : l.startUploadDisabledTooltip,
      child: btn,
    );
  }
}
