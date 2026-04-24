import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSnap = ref.watch(progressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('FireCheck')),
      body: asyncSnap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (snap) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assignment progress',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${snap.completedFeatures} of ${snap.totalFeatures} features',
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
                        '${snap.queuedJobs} queued · ${snap.failedJobs} failed · ${snap.deadJobs} dead',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                title: 'Gather Data',
                subtitle: 'Resume where you left off',
                onTap: () => _showComingSoon(context, 'Phase 1'),
              ),
              _ActionTile(
                title: 'Get Maps',
                subtitle: 'Download your assignment',
                onTap: () => _showComingSoon(context, 'Phase 1'),
              ),
              _ActionTile(
                title: 'Upload Data',
                subtitle: 'Send completed work',
                onTap: () => _showComingSoon(context, 'Phase 4'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String phase) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Coming in $phase')),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
