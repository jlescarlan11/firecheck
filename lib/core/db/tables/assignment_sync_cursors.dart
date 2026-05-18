import 'package:drift/drift.dart';

/// One row per assignment that this client has ever pulled remote state for.
/// `*LastSyncAt` is the `max(updated_at)` of the last successful pull
/// response — **not** `now()`. Using the server-supplied timestamp avoids
/// gaps from replication lag and client/server clock skew.
class AssignmentSyncCursors extends Table {
  TextColumn get assignmentId => text()();
  DateTimeColumn get attributionsLastSyncAt => dateTime().nullable()();
  DateTimeColumn get newFeaturesLastSyncAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {assignmentId};
}
