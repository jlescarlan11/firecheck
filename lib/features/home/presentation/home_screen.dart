import 'package:firecheck/core/security/biometric_gate_provider.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/submitted_banner.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final asyncSnap = ref.watch(progressProvider);
    final lock = ref.watch(assignmentLockStateProvider).value;
    final isLocked = lock is Submitted || lock is ClosedRemotely;
    final exportState = ref.watch(shapefileExportNotifierProvider);
    final isExporting = exportState is ExportExporting;

    ref.listen<ExportState>(shapefileExportNotifierProvider, (prev, next) {
      if (next is ExportFailed) {
        final msg = switch (next.failure) {
          NoCompletedFeatures() => l.exportErrorNoFeatures,
          WriteError()          => l.exportErrorWriteFailed,
          ShareError()          => l.exportErrorShareFailed,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('FireCheck')),
      body: asyncSnap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (snap) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (lock is Submitted)
                SubmittedBanner(submittedAt: lock.submittedAt)
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.assignmentProgress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.featuresLabel(
                            snap.completedFeatures,
                            snap.totalFeatures,
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        LinearProgressIndicator(
                          value: snap.totalFeatures == 0
                              ? 0
                              : snap.completedFeatures / snap.totalFeatures,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.jobCountsLabel(
                            snap.queuedJobs,
                            snap.failedJobs,
                            snap.deadJobs,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _ActionTile(
                title: l.gatherData,
                subtitle: l.gatherDataSubtitle,
                onTap: () => context.go('/map'),
              ),
              _ActionTile(
                title: l.getMaps,
                subtitle: l.getMapsSubtitle,
                onTap: () => context.go('/get-maps'),
              ),
              if (!isLocked)
                _ActionTile(
                  title: l.uploadData,
                  subtitle: l.uploadDataSubtitle,
                  onTap: () => _onUploadDataTap(context, ref, l),
                ),
              _ActionTile(
                title: isExporting
                    ? l.exportShapefileExporting
                    : l.exportShapefile,
                subtitle: l.exportShapefileSubtitle,
                trailing: isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: (snap.completedFeatures == 0 || isExporting)
                    ? null
                    : () => ref
                        .read(shapefileExportNotifierProvider.notifier)
                        .export(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onUploadDataTap(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final biometric = ref.read(biometricGateProvider);
    final available = await biometric.isAvailable();
    if (!available) {
      if (context.mounted) context.go('/review');
      return;
    }
    final ok = await biometric.authenticate(reason: l.biometricGateReason);
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.biometricFailedSnackbar)),
        );
      }
      return;
    }
    if (context.mounted) context.go('/review');
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
