import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<String?> showOverrideReasonDialog(
  BuildContext context, {
  required double distanceMeters,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) =>
        _OverrideReasonDialog(distanceMeters: distanceMeters),
  );
}

class _OverrideReasonDialog extends StatefulWidget {
  const _OverrideReasonDialog({required this.distanceMeters});
  final double distanceMeters;

  @override
  State<_OverrideReasonDialog> createState() => _OverrideReasonDialogState();
}

class _OverrideReasonDialogState extends State<_OverrideReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.overrideTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.overrideBody(widget.distanceMeters.round())),
          const SizedBox(height: 12),
          TextField(
            key: const Key('override.reason'),
            controller: _controller,
            maxLength: 200,
            decoration: InputDecoration(hintText: l.overrideReasonHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancelLabel),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, __) {
            final canContinue = value.text.trim().isNotEmpty;
            return FilledButton(
              onPressed: canContinue
                  ? () => Navigator.of(context).pop(value.text.trim())
                  : null,
              child: Text(l.overrideContinue),
            );
          },
        ),
      ],
    );
  }
}
