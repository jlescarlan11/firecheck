import 'package:drift/drift.dart';

/// Authoritative mirror, separate from editable local features and drafts.
class SharedMapFeatures extends Table {
  TextColumn get accountId => text()();
  TextColumn get assignmentId => text()();
  TextColumn get featureId => text()();
  IntColumn get revision => integer()();
  BoolColumn get pendingProjection =>
      boolean().withDefault(const Constant(true))();
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {accountId, assignmentId, featureId};
}

class SharedMapCursors extends Table {
  TextColumn get accountId => text()();
  TextColumn get assignmentId => text()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {accountId, assignmentId};
}
