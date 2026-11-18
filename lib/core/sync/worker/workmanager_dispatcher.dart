import 'dart:async';

import 'package:firecheck/core/sync/data/shared_map_sync.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/supabase_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:workmanager/workmanager.dart';

const _periodicTaskName = 'firecheck.sync.periodic';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Initialize a minimal Supabase + Drift in this isolate.
      await dotenv.load();
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );
      final account = Supabase.instance.client.auth.currentUser?.id;
      if (account == null) return true;
      final db = AppDatabase();
      try {
        final api = SupabaseSyncApi(Supabase.instance.client);
        final worker = SyncWorker(
          api: api,
          jobs: SyncJobsRepository(db, ownerId: account),
          payload: SubmissionPayloadBuilder(db),
          lock: AssignmentLockRepository(db),
          db: db,
          bundle: PendingWorkBundle(db),
        );
        await worker.drain();
        final maps = await (db.select(db.sharedMapCursors)
              ..where((t) => t.accountId.equals(account)))
            .get();
        final sync = SharedMapSync(
            db: db,
            accountId: account,
            fetch: SharedMapSync.supabase(Supabase.instance.client));
        for (final map in maps) {
          await sync.pull(map.assignmentId);
        }
        return true;
      } finally {
        await db.close();
      }
    } on Object {
      return Future.value(false);
    }
  });
}

Future<void> registerPeriodicSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _periodicTaskName,
    'firecheck.sync',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> cancelPeriodicSync() async {
  await Workmanager().cancelByUniqueName(_periodicTaskName);
}
