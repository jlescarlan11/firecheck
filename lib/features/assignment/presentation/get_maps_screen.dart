// lib/features/assignment/presentation/get_maps_screen.dart

import 'package:firecheck/core/drive/ftp_credentials.dart';
import 'package:firecheck/core/drive/transport_source.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/theme/app_layout.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GetMapsScreen extends ConsumerStatefulWidget {
  const GetMapsScreen({super.key});

  @override
  ConsumerState<GetMapsScreen> createState() => _GetMapsScreenState();
}

class _GetMapsScreenState extends ConsumerState<GetMapsScreen> {
  @override
  void initState() {
    super.initState();
    // The GetMaps notifier outlives this screen (not autoDispose). If the
    // user finished, cancelled, or errored on a previous visit, they're
    // returning to start a new download — drop the stale terminal state so
    // they don't land on the success/error screen with no way forward.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(getMapsNotifierProvider);
      if (s is Ready ||
          s is Cancelled ||
          s is GetMapsError ||
          s is InsufficientStorage) {
        ref.read(getMapsNotifierProvider.notifier).reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(getMapsNotifierProvider);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l.getMapsTitle)),
      body: Padding(
        padding: appPageInsets(context),
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
                  ? () =>
                      ref.read(getMapsNotifierProvider.notifier).retryDownload()
                  : () => ref.read(getMapsNotifierProvider.notifier).reset(),
            ),
        },
      ),
    );
  }
}

class _IdleView extends ConsumerStatefulWidget {
  const _IdleView({required this.onStart});
  final VoidCallback onStart;

  @override
  ConsumerState<_IdleView> createState() => _IdleViewState();
}

class _IdleViewState extends ConsumerState<_IdleView> {
  // Issue #45: which transport the user picked for this download.
  TransportSource _source = TransportSource.googleDrive;
  // Issue #45 — credentials are kept in-memory only for the current
  // download. Persisting them would require secure storage and a
  // permissions UX that's out of scope for this batch.
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _remotePath = TextEditingController(text: '/');

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    _remotePath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageIntro(title: l.designMapsTitle, subtitle: l.designMapsBody),
          Text(
            l.designDownloadSource,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          SegmentedButton<TransportSource>(
            segments: const [
              ButtonSegment(
                value: TransportSource.googleDrive,
                label: Text('Google Drive'),
                icon: Icon(Icons.cloud),
              ),
              ButtonSegment(
                value: TransportSource.ftp,
                label: Text('FTP'),
                icon: Icon(Icons.dns),
              ),
            ],
            selected: {_source},
            onSelectionChanged: (s) => setState(() => _source = s.first),
          ),
          if (_source == TransportSource.ftp) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'FTP host (e.g. ftp.example.org)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remotePath,
              decoration: const InputDecoration(
                labelText: 'Remote folder (path on server)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () {
              ref.read(getMapsNotifierProvider.notifier).setTransport(
                    _source,
                    ftp: _source == TransportSource.ftp
                        ? FtpCredentials(
                            host: _host.text.trim(),
                            user: _user.text,
                            password: _pass.text,
                            remotePath: _remotePath.text.trim().isEmpty
                                ? '/'
                                : _remotePath.text.trim(),
                          )
                        : null,
                  );
              widget.onStart();
            },
            child: Text(l.startDownload),
          ),
        ],
      ),
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
    if (state.assignments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              l.noAssignmentsTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.noAssignmentsBody,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(getMapsNotifierProvider.notifier).reset(),
              icon: const Icon(Icons.refresh),
              label: Text(l.retryAction),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.pickAssignmentTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: state.assignments.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final a = state.assignments[i];
              final selected = a.assignmentId == state.selectedId;
              return InkWell(
                onTap: () => ref
                    .read(getMapsNotifierProvider.notifier)
                    .selectAssignment(a.assignmentId),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.displayName ?? a.assignmentId,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                      const SizedBox(width: 12),
                      Icon(
                        selected
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
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

class _InsufficientStorageView extends ConsumerWidget {
  const _InsufficientStorageView({required this.state});
  final InsufficientStorage state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final needed = (state.requiredBytes / 1048576).ceil();
    final available = (state.availableBytes / 1048576).floor();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          l.insufficientStorageTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l.insufficientStorageBody(needed, available),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => ref.read(getMapsNotifierProvider.notifier).reset(),
          child: Text(l.retryAction),
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
    final progress = state.total <= 0
        ? null
        : (state.downloaded / state.total).clamp(0.0, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.downloadingShapefiles, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(
          progress == null
              ? l.downloadProgressUnknown
              : '${(progress * 100).round()}%',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => ref.read(getMapsNotifierProvider.notifier).cancel(),
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
    final (downloaded, total) = switch (state) {
      DownloadingTiles(:final downloadedBytes, :final totalBytes) => (
          downloadedBytes,
          totalBytes
        ),
      _ => (0, 0),
    };
    final progress = total <= 0 ? null : (downloaded / total).clamp(0.0, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.downloadingTiles, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(
          progress == null
              ? l.downloadProgressUnknown
              : '${(progress * 100).round()}%',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => ref.read(getMapsNotifierProvider.notifier).cancel(),
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
          onPressed: () => context.pushReplacement('/map'),
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
        Icon(
          Icons.warning_amber_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.tertiary,
        ),
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
          failure is AuthFailure
              ? failure.message
              : '${l.downloadFailed} ${failure.message}',
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
