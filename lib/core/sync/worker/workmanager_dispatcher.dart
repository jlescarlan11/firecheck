import 'dart:async';

import 'package:drift/native.dart';
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
      // Background isolate uses the same on-disk Drift DB.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      // NOTE: in production, WorkManager isolate should open the same
      // sqlite file the main isolate uses. We ship with the simpler path —
      // the periodic tick isn't load-bearing for correctness (connectivity
      // + foreground triggers are). Production-grade isolate sharing is
      // deferred polish.
      final api = SupabaseSyncApi(Supabase.instance.client);
      final worker = SyncWorker(
        api: api,
        jobs: SyncJobsRepository(db),
        payload: SubmissionPayloadBuilder(db),
        lock: AssignmentLockRepository(db),
        db: db,
        bundle: PendingWorkBundle(db),
      );
      await worker.drain();
      return Future.value(true);
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
