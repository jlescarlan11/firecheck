import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GeometryEditorBanner extends ConsumerWidget {
  const GeometryEditorBanner({
    required this.editCount,
    required this.undoEnabled,
    required this.saveEnabled,
    super.key,
    this.onCancel,
    this.onUndo,
    this.onSave,
  });

  final int editCount;
  final bool undoEnabled;
  final bool saveEnabled;
  final VoidCallback? onCancel;
  final VoidCallback? onUndo;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(geometryEditorControllerProvider);
    final isSketch = state.isSketchMode;
    final type = state.pendingFeatureType;
    final title = isSketch
        ? l.sketchBannerTitle(editCount, type ?? '')
        : l.reshapeBannerTitle(editCount);
    final primaryLabel = isSketch ? l.sketchBannerFinish : l.reshapeBannerSave;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  TextButton(
                    key: const Key('reshape.banner.cancel'),
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    key: const Key('reshape.banner.save'),
                    onPressed: saveEnabled ? onSave : null,
                    child: Text(primaryLabel),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 6),
                child: TextButton.icon(
                  key: const Key('reshape.banner.undo'),
                  onPressed: undoEnabled ? onUndo : null,
                  icon: const Icon(Icons.undo, size: 20),
                  label: const Text('Undo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
