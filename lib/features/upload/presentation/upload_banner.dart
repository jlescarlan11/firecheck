// lib/features/upload/presentation/upload_banner.dart
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class UploadBanner extends ConsumerWidget {
  const UploadBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driveUploadNotifierProvider);
    if (state.pendingCount == 0) return const SizedBox.shrink();

    final totalMb =
        (state.totalPendingBytes / 1024 / 1024).toStringAsFixed(1);

    return Card(
      color: Theme.of(context).colorScheme.primary,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          Icons.cloud_upload,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        title: Text(
          '${state.pendingCount} file${state.pendingCount == 1 ? '' : 's'} ready to upload',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '$totalMb MB',
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onPrimary
                .withValues(alpha: 0.8),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        onTap: () => context.push('/uploads'),
      ),
    );
  }
}
