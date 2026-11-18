import 'dart:convert';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';

class RoadAttributesRepository {
  RoadAttributesRepository(this._db);
  final AppDatabase _db;

  Future<void> upsertForSubmission(
    String submissionId,
    RoadAttributesCompanion attrs,
  ) async {
    await SubmissionRepository(_db).persistEdit(submissionId, () async {
      await _db.into(_db.roadAttributes).insertOnConflictUpdate(attrs);
    });
  }

  Future<RoadAttribute?> findBySubmission(String submissionId) {
    return (_db.select(_db.roadAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
  }

  static List<String> decodeStringList(String json) {
    final parsed = jsonDecode(json);
    if (parsed is! List) return const [];
    return parsed.map((e) => e.toString()).toList();
  }

  static String encodeStringList(List<String> values) => jsonEncode(values);
}
