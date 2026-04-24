import 'dart:async';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';

class ProgressRepository {
  ProgressRepository(this._db);
  final AppDatabase _db;

  Stream<ProgressSnapshot> watchProgress() {
    final featuresStream = _db.select(_db.features).watch();
    final jobsStream = _db.select(_db.syncJobs).watch();

    return Rx.combineLatest(
      featuresStream,
      jobsStream,
      (features, jobs) {
        final total = features.length;
        final completed = features.where((f) => f.status == 'complete').length;
        final inProgress =
            features.where((f) => f.status == 'in_progress').length;
        final queued = jobs
            .where((j) => j.status == 'pending' || j.status == 'in_progress')
            .length;
        final failed = jobs.where((j) => j.status == 'failed').length;
        final dead = jobs.where((j) => j.status == 'dead').length;

        return ProgressSnapshot(
          totalFeatures: total,
          completedFeatures: completed,
          inProgressFeatures: inProgress,
          queuedJobs: queued,
          failedJobs: failed,
          deadJobs: dead,
        );
      },
    );
  }
}

/// Minimal combineLatest so we don't pull in rxdart just for this.
/// Single-listener (non-broadcast). Consumers should subscribe only once —
/// e.g. via a Riverpod StreamProvider.
class Rx {
  static Stream<R> combineLatest<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A, B) combine,
  ) async* {
    A? latestA;
    B? latestB;
    var hasA = false;
    var hasB = false;
    var doneA = false;
    var doneB = false;

    final controller = StreamController<R>();

    Future<void> closeIfBothDone() async {
      if (doneA && doneB && !controller.isClosed) {
        await controller.close();
      }
    }

    final subA = a.listen(
      (event) {
        latestA = event;
        hasA = true;
        if (hasB) controller.add(combine(latestA as A, latestB as B));
      },
      onError: controller.addError,
      onDone: () {
        doneA = true;
        closeIfBothDone();
      },
    );

    final subB = b.listen(
      (event) {
        latestB = event;
        hasB = true;
        if (hasA) controller.add(combine(latestA as A, latestB as B));
      },
      onError: controller.addError,
      onDone: () {
        doneB = true;
        closeIfBothDone();
      },
    );

    controller.onCancel = () async {
      await subA.cancel();
      await subB.cancel();
      if (!controller.isClosed) await controller.close();
    };

    yield* controller.stream;
  }
}
