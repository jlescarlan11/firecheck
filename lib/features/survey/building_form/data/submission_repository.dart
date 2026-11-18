import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:uuid/uuid.dart';

class SubmissionRepository {
  SubmissionRepository(this._db);
  final AppDatabase _db;

  /// If a draft exists for this feature, returns it. Otherwise creates one
  /// and returns the new row. Idempotent — always safe to call on first
  /// polygon tap.
  Future<Submission> ensureDraftForFeature({
    required String featureId,
    required String enumeratorId,
    String formVersion = 'legacy-v1',
  }) async {
    final existing = await (_db.select(_db.submissions)
          ..where(
            (t) => t.featureId.equals(featureId) & t.syncStatus.equals('draft'),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing;
    return _createDraft(featureId, enumeratorId, formVersion);
  }

  /// Always creates a new draft. Used by the "+" tab.
  Future<Submission> createAdditionalSubmission({
    required String featureId,
    required String enumeratorId,
    String formVersion = 'legacy-v1',
  }) {
    return _createDraft(featureId, enumeratorId, formVersion, additional: true);
  }

  Future<Submission> _createDraft(
    String featureId,
    String enumeratorId,
    String formVersion, {
    bool additional = false,
  }) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    final companion = SubmissionsCompanion.insert(
      id: id,
      featureId: featureId,
      submittedBy: Value(enumeratorId),
      formVersion: Value(formVersion),
      isAdditionalObservation: Value(additional),
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.submissions).insert(companion);
    return (_db.select(_db.submissions)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Stream<List<Submission>> watchSubmissionsForFeature(String featureId) {
    return (_db.select(_db.submissions)
          ..where((t) => t.featureId.equals(featureId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<Submission?> findById(String submissionId) {
    return (_db.select(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .getSingleOrNull();
  }

  Future<int> countSubmissionsForFeature(String featureId) async {
    final rows = await (_db.select(_db.submissions)
          ..where((t) => t.featureId.equals(featureId)))
        .get();
    return rows.length;
  }

  /// Persists a survey edit atomically and only dirties an accepted/frozen
  /// revision when durable answer values actually change.
  Future<void> persistEdit(String submissionId, Future<void> Function() write) {
    return _db.transaction(() async {
      final before = await SubmissionPayloadBuilder(_db).build(submissionId);
      await write();
      final after = await SubmissionPayloadBuilder(_db).build(submissionId);
      if (SubmissionPayloadBuilder.sameRevision(before, after)) return;
      final current = await findById(submissionId);
      await (_db.update(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(
        SubmissionsCompanion(
          syncStatus: {'uploaded', 'queued', 'ready_to_upload'}
                  .contains(current?.syncStatus)
              ? const Value('in_progress')
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<void> updateOverrideReason(String submissionId, String reason) {
    return persistEdit(submissionId, () async {
      await (_db.update(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(SubmissionsCompanion(overrideReason: Value(reason)));
    });
  }

  Future<void> updateDoesNotExist(
    String submissionId, {
    required bool doesNotExist,
  }) {
    return persistEdit(submissionId, () async {
      await (_db.update(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(SubmissionsCompanion(doesNotExist: Value(doesNotExist)));
    });
  }

  Future<void> markStatus(String submissionId, String syncStatus) {
    return (_db.update(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .write(
      SubmissionsCompanion(
        syncStatus: Value(syncStatus),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteSubmission(String submissionId) {
    return (_db.delete(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .go();
  }
}
