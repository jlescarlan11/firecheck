import 'package:firecheck/features/map/presentation/zoom_button_state.dart';
import 'package:firecheck/features/map/presentation/zoom_direction.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class ZoomButton extends StatelessWidget {
  const ZoomButton({
    required this.direction,
    required this.state,
    required this.onTap,
    super.key,
  });

  final ZoomDirection direction;
  final ZoomButtonState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final isDisabled = state == ZoomButtonState.disabled;
    final isInteractive = !isDisabled;

    final icon = direction == ZoomDirection.zoomIn ? Icons.add : Icons.remove;
    final label = direction == ZoomDirection.zoomIn
        ? l.zoomInButtonSemanticLabel
        : l.zoomOutButtonSemanticLabel;

    final child = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: colors.primary,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isInteractive ? onTap : null,
          child: Center(
            child: Icon(icon, color: colors.onPrimary, size: 24),
          ),
        ),
      ),
    );

    return Semantics(
      label: label,
      button: true,
      enabled: isInteractive,
      child: Opacity(opacity: isDisabled ? 0.5 : 1.0, child: child),
    );
  }
}
