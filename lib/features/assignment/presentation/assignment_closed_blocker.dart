import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class AssignmentClosedBlocker extends ConsumerWidget {
  const AssignmentClosedBlocker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final lock = ref.watch(assignmentLockStateProvider).value;
    if (lock is! ClosedRemotely) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: Color(0xFFC53030)),
                const SizedBox(height: 12),
                Text(
                  l.assignmentClosedTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(l.assignmentClosedBody, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (lock.bundleFile != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.share),
                    label: Text(l.shareBundleAction),
                    onPressed: () async {
                      await SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(lock.bundleFile!.path)],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
