import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

class AssignmentLockRepository {
  AssignmentLockRepository(this._db);
  final AppDatabase _db;

  Future<bool> isLocked(String assignmentId) async {
    final row = await (_db.select(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    return row?.closedRemotely ?? false;
  }

  Future<void> markClosed(String assignmentId) async {
    await (_db.update(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .write(const AssignmentsCompanion(closedRemotely: Value(true)));
  }

  Stream<bool> lockStateStream(String assignmentId) {
    return (_db.select(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .watchSingleOrNull()
        .map((row) => row?.closedRemotely ?? false);
  }
}
