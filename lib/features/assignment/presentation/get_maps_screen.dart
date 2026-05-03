// lib/features/assignment/presentation/get_maps_screen.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GetMapsScreen extends ConsumerWidget {
  const GetMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(getMapsNotifierProvider);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l.getMapsTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (state) {
          Idle() => _IdleView(
              onStart: () => ref.read(getMapsNotifierProvider.notifier).start(),
            ),
          DiscoveringAssignments() => const _DiscoveringView(),
          PreparingDownload() => const _DiscoveringView(),
          PickingAssignment() => _PickingAssignmentView(state: state),
          InsufficientStorage() => _InsufficientStorageView(state: state),
          DownloadingShapefiles() => _DownloadingShapefilesView(state: state),
          ImportingShapefiles() => const _ImportingShapefilesView(),
          DownloadingTiles() => _ProgressView(state: state),
          Ready() => _ReadyView(state: state),
          Cancelled() => _IdleView(
              onStart: () => ref.read(getMapsNotifierProvider.notifier).start(),
            ),
          ValidatingShapefiles() => const _ValidatingView(),
          ShapefileWarning() => _ShapefileWarningView(state: state),
          GetMapsError(:final failure, :final isRetryable) => _ErrorView(
              failure: failure,
              isRetryable: isRetryable,
              onAction: isRetryable
                  ? () => ref.read(getMapsNotifierProvider.notifier).retryDownload()
                  : () => ref.read(getMapsNotifierProvider.notifier).reset(),
            ),
        },
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l.getMapsExplainer('~100 MB', 10),
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onStart,
          child: Text(l.startDownload),
        ),
      ],
    );
  }
}

class _DiscoveringView extends StatelessWidget {
  const _DiscoveringView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(l.discoveringAssignments, textAlign: TextAlign.center),
      ],
    );
  }
}

class _PickingAssignmentView extends ConsumerWidget {
  const _PickingAssignmentView({required this.state});
  final PickingAssignment state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.pickAssignmentTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: state.assignments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = state.assignments[i];
              final selected = a.assignmentId == state.selectedId;
              return InkWell(
                onTap: () => ref
                    .read(getMapsNotifierProvider.notifier)
                    .selectAssignment(a.assignmentId),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.assignmentId,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              a.alreadyDownloaded
                                  ? l.alreadyDownloadedBadge
                                  : l.notDownloadedBadge,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () =>
              ref.read(getMapsNotifierProvider.notifier).confirmDownload(),
          child: Text(l.downloadSelected),
        ),
      ],
    );
  }
}

class _InsufficientStorageView extends StatelessWidget {
  const _InsufficientStorageView({required this.state});
  final InsufficientStorage state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final needed = (state.requiredBytes / 1048576).ceil();
    final available = (state.availableBytes / 1048576).floor();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.warning_amber_rounded,
            size: 48, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 12),
        Text(l.insufficientStorageTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l.insufficientStorageBody(needed, available),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: null,
          child: Text(l.downloadSelected),
        ),
        const SizedBox(height: 8),
        Text(l.freeSpaceHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DownloadingShapefilesView extends ConsumerWidget {
  const _DownloadingShapefilesView({required this.state});
  final DownloadingShapefiles state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final progress = state.total == 0 ? null : state.downloaded / state.total;
    final dl = (state.downloaded / 1048576).toStringAsFixed(1);
    final tot = (state.total / 1048576).toStringAsFixed(1);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.downloadingShapefiles, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(
          '$dl / $tot MB',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () =>
              ref.read(getMapsNotifierProvider.notifier).cancel(),
          child: Text(l.cancelLabel),
        ),
      ],
    );
  }
}

class _ImportingShapefilesView extends StatelessWidget {
  const _ImportingShapefilesView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        Text(l.importingShapefiles, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ProgressView extends ConsumerWidget {
  const _ProgressView({required this.state});
  final GetMapsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final progress = state.overallProgress;
    final (downloaded, total) = switch (state) {
      DownloadingTiles(:final downloadedBytes, :final totalBytes) =>
        (downloadedBytes, totalBytes),
      _ => (0, 0),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.downloadingTiles, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(
          '${(downloaded / 1048576).toStringAsFixed(1)} / '
          '${(total / 1048576).toStringAsFixed(1)} MB',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () =>
              ref.read(getMapsNotifierProvider.notifier).cancel(),
          child: Text(l.cancelLabel),
        ),
      ],
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.state});
  final Ready state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 12),
        Text(
          l.readyLabel,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/map'),
          child: Text(l.openMap),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.go('/'),
          child: Text(l.backToHome),
        ),
      ],
    );
  }
}

class _ValidatingView extends StatelessWidget {
  const _ValidatingView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(l.getMapsValidating, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ShapefileWarningView extends ConsumerWidget {
  const _ShapefileWarningView({required this.state});
  final ShapefileWarning state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.warning_amber_rounded,
            size: 48, color: Theme.of(context).colorScheme.tertiary),
        const SizedBox(height: 12),
        Text(
          l.getMapsWarningTitle,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        ...state.warnings.map(
          (w) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(w, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () =>
              ref.read(getMapsNotifierProvider.notifier).acknowledgeWarning(),
          child: Text(l.getMapsWarningContinue),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => ref.read(getMapsNotifierProvider.notifier).reset(),
          child: Text(l.getMapsClose),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.failure,
    required this.isRetryable,
    required this.onAction,
  });
  final Failure failure;
  final bool isRetryable;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isValidation = failure is ShapefileValidationFailure;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 64),
        const SizedBox(height: 12),
        Text(
          '${l.downloadFailed} ${failure.message}',
          textAlign: TextAlign.center,
        ),
        if (isValidation) ...[
          const SizedBox(height: 8),
          Text(
            l.getMapsContactSupervisor,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onAction,
          child: Text(isRetryable ? l.tryAgain : l.getMapsClose),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.backToHome),
        ),
      ],
    );
  }
}
