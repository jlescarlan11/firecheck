import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
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
  }) async {
    final existing = await (_db.select(_db.submissions)
          ..where((t) =>
              t.featureId.equals(featureId) & t.syncStatus.equals('draft'),)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing;
    return _createDraft(featureId, enumeratorId);
  }

  /// Always creates a new draft. Used by the "+" tab.
  Future<Submission> createAdditionalSubmission({
    required String featureId,
    required String enumeratorId,
  }) {
    return _createDraft(featureId, enumeratorId);
  }

  Future<Submission> _createDraft(String featureId, String enumeratorId) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    final companion = SubmissionsCompanion.insert(
      id: id,
      featureId: featureId,
      submittedBy: Value(enumeratorId),
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

  Future<int> countSubmissionsForFeature(String featureId) async {
    final rows = await (_db.select(_db.submissions)
          ..where((t) => t.featureId.equals(featureId)))
        .get();
    return rows.length;
  }

  Future<void> updateOverrideReason(String submissionId, String reason) {
    return (_db.update(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .write(SubmissionsCompanion(
      overrideReason: Value(reason),
      updatedAt: Value(DateTime.now()),
    ),);
  }

  Future<void> updateDoesNotExist(
    String submissionId, {
    required bool doesNotExist,
  }) {
    return (_db.update(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .write(SubmissionsCompanion(
      doesNotExist: Value(doesNotExist),
      updatedAt: Value(DateTime.now()),
    ),);
  }

  Future<void> markStatus(String submissionId, String syncStatus) {
    return (_db.update(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .write(SubmissionsCompanion(
      syncStatus: Value(syncStatus),
      updatedAt: Value(DateTime.now()),
    ),);
  }

  Future<void> deleteSubmission(String submissionId) {
    return (_db.delete(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .go();
  }
}
