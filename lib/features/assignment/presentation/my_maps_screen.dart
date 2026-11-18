import 'package:drift/drift.dart' show Variable;
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final downloadedAssignmentsProvider = StreamProvider<List<Assignment>>((ref) =>
    ref.watch(assignmentRepositoryProvider).watchDownloadedAssignments());

final mapSummaryProvider =
    StreamProvider.autoDispose.family<String, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db
      .customSelect(
        """
    SELECT
      (SELECT COUNT(*) FROM features WHERE assignment_id = ? AND merged_into_id IS NULL) AS total,
      (SELECT COUNT(*) FROM features WHERE assignment_id = ? AND merged_into_id IS NULL AND status = 'complete') AS completed,
      (SELECT COUNT(*) FROM drive_upload_jobs WHERE assignment_id = ? AND status IN ('pending','uploading','failed')) AS pending,
      (SELECT COUNT(*) FROM offline_tile_packs WHERE assignment_id = ? AND status = 'ready') AS offline
  """,
        variables: List.generate(4, (_) => Variable.withString(id)),
        readsFrom: {db.features, db.driveUploadJobs, db.offlineTilePacks},
      )
      .watchSingle()
      .map((row) =>
          '${row.read<int>('completed')}/${row.read<int>('total')} gathered · '
          '${row.read<int>('pending')} upload files pending · '
          '${row.read<int>('offline') > 0 ? "Offline basemap ready" : "Offline basemap unavailable"}');
});

class MyMapsScreen extends ConsumerStatefulWidget {
  const MyMapsScreen({super.key});
  @override
  ConsumerState<MyMapsScreen> createState() => _MyMapsScreenState();
}

class _MyMapsScreenState extends ConsumerState<MyMapsScreen> {
  bool _selecting = false;

  Future<void> _select(Assignment assignment) async {
    setState(() => _selecting = true);
    try {
      await ref
          .read(assignmentRepositoryProvider)
          .selectAssignment(assignment.id);
      if (!mounted) return;
      ref.invalidate(currentAssignmentProvider);
      await ref.read(currentAssignmentProvider.future);
      if (mounted) context.pushReplacement('/map');
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open this map: $error')),
        );
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(currentAssignmentProvider).valueOrNull;
    final maps = ref.watch(downloadedAssignmentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Maps')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _selecting ? null : () => context.push('/get-maps'),
        icon: const Icon(Icons.download_outlined),
        label: const Text('Download maps'),
      ),
      body: maps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load maps: $error')),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('Download a map to start gathering data.'))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final map = items[index];
                  return ListTile(
                    leading: Icon(map.closedRemotely
                        ? Icons.lock_outline
                        : Icons.map_outlined),
                    title: Text(map.name ?? map.id),
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(map.closedRemotely
                              ? 'Closed · view only'
                              : selected?.id == map.id
                                  ? 'Working on this map'
                                  : 'Available on this device'),
                          Text(ref
                                  .watch(mapSummaryProvider(map.id))
                                  .valueOrNull ??
                              'Loading progress…'),
                          if (map.boundarySource == 'building_extent')
                            const Text(
                                'Study area inferred from imported buildings'),
                          if (map.boundarySource == 'absent')
                            const Text('No study boundary supplied'),
                        ]),
                    trailing: selected?.id == map.id
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.chevron_right),
                    enabled: !_selecting,
                    onTap: () => _select(map),
                  );
                },
              ),
      ),
    );
  }
}
