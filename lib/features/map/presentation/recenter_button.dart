import 'package:firecheck/features/map/presentation/recenter_button_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class RecenterButton extends StatelessWidget {
  const RecenterButton({
    required this.state,
    required this.onTap,
    super.key,
  });

  final RecenterButtonState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final isLoading = state == RecenterButtonState.loading;
    final isDisabled = state == RecenterButtonState.disabled;
    final isInteractive = state == RecenterButtonState.idle;

    final child = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.outlineVariant),
        ),
        elevation: 1,
        child: InkWell(
          customBorder:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: isInteractive ? onTap : null,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colors.onSurface),
                    ),
                  )
                : Icon(Icons.my_location, color: colors.onSurface, size: 24),
          ),
        ),
      ),
    );

    return Semantics(
      label: l.recenterButtonSemanticLabel,
      button: true,
      enabled: isInteractive,
      child: Opacity(opacity: isDisabled ? 0.5 : 1.0, child: child),
    );
  }
}
