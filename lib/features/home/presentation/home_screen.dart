import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/navigation/app_bottom_nav.dart';
import 'package:firecheck/core/security/biometric_gate_provider.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/submitted_banner.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_banner.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
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
    final colors = Theme.of(context).colorScheme;
    final uploads = ref.watch(driveUploadNotifierProvider);
    final conflicts = ref.watch(awaitingResolutionCountProvider);
    final uploadCount = uploads.pendingCount + uploads.uploadingCount;
    final failedFiles = uploads.failedCount;
    final uploadSummary = failedFiles > 0
        ? l.homeFailedFiles(failedFiles)
        : uploads.isUploading
            ? l.homeUploadingFiles(uploads.uploadingCount)
            : uploadCount > 0
                ? l.homePendingFiles(uploadCount)
                : l.uploadDataSubtitle;
    final lock = ref.watch(assignmentLockStateProvider).value;
    // Only ClosedRemotely blocks edits/uploads. Submitted is informational
    // (banner only) — enumerators may re-export and re-upload after a
    // submit; conflict resolution is handled server-side via
    // submit_attribution_with_conflict_check.
    final isLocked = lock is ClosedRemotely;
    final exportState = ref.watch(shapefileExportNotifierProvider);
    final isBusy =
        exportState is ExportValidating || exportState is ExportExporting;

    ref.listen<ExportState>(shapefileExportNotifierProvider, (prev, next) {
      if (next is ExportFailed) {
        final msg = switch (next.failure) {
          NoCompletedFeatures() => l.exportErrorNoFeatures,
          WriteError() => l.exportErrorWriteFailed,
          ShareError() => l.exportErrorShareFailed,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 88,
        titleSpacing: 24,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_outlined,
              color: colors.primary,
              size: 30,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l.appTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.uploadsTitle,
            icon: Badge.count(
              count: uploadCount,
              isLabelVisible: uploadCount > 0,
              backgroundColor: colors.primary,
              child: const Icon(Icons.cloud_upload_outlined, size: 28),
            ),
            onPressed: () => context.push('/uploads'),
          ),
          PopupMenuButton<String>(
            tooltip: l.homeMoreActions,
            onSelected: (_) =>
                ref.read(shapefileExportNotifierProvider.notifier).export(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'export',
                enabled: (asyncSnap.valueOrNull?.completedFeatures ?? 0) > 0 &&
                    !isBusy,
                child: Text(
                  switch (exportState) {
                    ExportValidating() => l.exportValidating,
                    ExportExporting() => l.exportShapefileExporting,
                    _ => l.exportShapefile,
                  },
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: asyncSnap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(l.homeLoadError, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(progressProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text(l.retryAction),
                ),
              ],
            ),
          ),
        ),
        data: (snap) => LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth > 728
                      ? (constraints.maxWidth - 680) / 2
                      : 24,
                  12,
                  constraints.maxWidth > 728
                      ? (constraints.maxWidth - 680) / 2
                      : 24,
                  24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.homeFieldwork,
                          style: const TextStyle(
                            fontSize: 32,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.homeIntro,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (conflicts > 0) ...[
                          const SizedBox(height: 20),
                          const ConflictBanner(),
                        ],
                        if (lock is Submitted) ...[
                          const SizedBox(height: 20),
                          SubmittedBanner(submittedAt: lock.submittedAt),
                        ],
                        if (isLocked) ...[
                          const SizedBox(height: 20),
                          Text(
                            l.readOnlyBannerClosed,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                        const SizedBox(height: 28),
                        _AssignmentProgress(snapshot: snap),
                        const SizedBox(height: 22),
                        FilledButton(
                          key: const Key('home-survey-action'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: snap.totalFeatures == 0
                              ? null
                              : () => context.push('/map'),
                          child: Row(
                            children: [
                              const Icon(Icons.map_outlined, size: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  isLocked
                                      ? l.homeViewMap
                                      : snap.completedFeatures +
                                                  snap.inProgressFeatures >
                                              0
                                          ? l.homeContinueSurvey
                                          : l.homeStartSurvey,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                        if (snap.totalFeatures == 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            l.homeEmptyHint,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 36),
                        Text(
                          l.homeManageData,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ActionTile(
                          icon: Icons.map_outlined,
                          title: l.homeGetMaps,
                          subtitle: snap.totalFeatures == 0
                              ? l.noLocalMaps
                              : l.getMapsSubtitle,
                          onTap: () => context.push('/get-maps'),
                        ),
                        if (!isLocked)
                          _ActionTile(
                            icon: Icons.cloud_upload_outlined,
                            title: l.homeReviewUpload,
                            subtitle: uploadSummary,
                            onTap: () => _onUploadDataTap(context, ref, l),
                          ),
                        Divider(height: 1, color: colors.outlineVariant),
                        if (snap.failedJobs + snap.deadJobs > 0 ||
                            snap.queuedJobs > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            snap.failedJobs + snap.deadJobs > 0
                                ? l.homeSyncAttention(
                                    snap.failedJobs + snap.deadJobs,
                                  )
                                : l.homeSyncPending(snap.queuedJobs),
                            style: TextStyle(
                              fontSize: 13,
                              color: snap.failedJobs + snap.deadJobs > 0
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (isBusy) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(
                            exportState is ExportValidating
                                ? l.exportValidating
                                : l.exportShapefileExporting,
                          ),
                        ],
                        if (exportState is ExportValidationFailed)
                          ...exportState.errors.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 18,
                                    color: colors.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _validationErrorMessage(l, e),
                                      style: TextStyle(
                                        color: colors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (snap.totalFeatures > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 32, bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.save_outlined,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                l.homeLocalSaveHint,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.home),
    );
  }

  String _validationErrorMessage(AppLocalizations l, ExportLayerError e) =>
      switch ((e.layer, e.issue)) {
        (ExportLayer.buildings, ExportLayerIssue.emptyLayer) =>
          l.exportValidationBuildingsEmpty,
        (ExportLayer.roads, ExportLayerIssue.emptyLayer) =>
          l.exportValidationRoadsEmpty,
        (ExportLayer.buildings, ExportLayerIssue.missingRequiredFields) =>
          l.exportValidationBuildingsMissingFields,
        (ExportLayer.roads, ExportLayerIssue.missingRequiredFields) =>
          l.exportValidationRoadsMissingFields,
      };

  Future<void> _onUploadDataTap(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final biometric = ref.read(biometricGateProvider);
    final available = await biometric.isAvailable();
    if (!available) {
      if (context.mounted) await context.push<void>('/review');
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
    if (context.mounted) await context.push<void>('/review');
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.icon,
  });
  final String title;
  final IconData icon;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 2),
        minLeadingWidth: 34,
        horizontalTitleGap: 18,
        leading: Icon(icon, color: colors.onSurface, size: 30),
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        onTap: onTap,
        enabled: onTap != null,
      ),
    );
  }
}

class _AssignmentProgress extends StatelessWidget {
  const _AssignmentProgress({required this.snapshot});

  final ProgressSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final progress = snapshot.totalFeatures == 0
        ? 0.0
        : (snapshot.completedFeatures / snapshot.totalFeatures).clamp(0.0, 1.0);
    final remaining = (snapshot.totalFeatures - snapshot.completedFeatures)
        .clamp(0, snapshot.totalFeatures);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.assignmentProgress,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: l.featuresLabel(
            snapshot.completedFeatures,
            snapshot.totalFeatures,
          ),
          excludeSemantics: true,
          child: Text(
            l.homeProgressCount(
              snapshot.completedFeatures,
              snapshot.totalFeatures,
            ),
            style: const TextStyle(
              fontSize: 40,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
        ),
        Text(
          l.homeSurveyed,
          style: TextStyle(fontSize: 17, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final label = Text(
              l.homePercentComplete((progress * 100).round()),
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            );
            final bar = LinearProgressIndicator(
              value: progress,
              color: colors.primary,
              backgroundColor: colors.surfaceContainerHighest,
              minHeight: 10,
              borderRadius: BorderRadius.circular(8),
              semanticsLabel: l.assignmentProgress,
            );
            if (constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 18) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar, const SizedBox(height: 8), label],
              );
            }
            return Row(
              children: [
                Expanded(child: bar),
                const SizedBox(width: 12),
                label,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          l.homeRemaining(remaining),
          style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
