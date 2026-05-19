import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Small pill placed on the map screen showing "👥 N edited by others".
/// Hidden when the count is zero. Tap opens the remote-activity list.
class RemoteActivityChip extends ConsumerWidget {
  const RemoteActivityChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(remoteActivityCountProvider);
    if (count == 0) return const SizedBox.shrink();

    return Material(
      key: const Key('remote-activity.chip'),
      color: Colors.deepOrange.shade50,
      elevation: 1,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => context.push('/remote-activity'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_alt_outlined,
                  size: 18, color: Colors.deepOrange),
              const SizedBox(width: 8),
              Text(
                count == 1
                    ? '1 feature edited by others'
                    : '$count features edited by others',
                style: TextStyle(
                  color: Colors.deepOrange.shade900,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
