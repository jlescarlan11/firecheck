import 'package:drift/drift.dart';

/// Decisions queued by the conflict / dedup review UI, waiting for the
/// sync worker to call the corresponding `resolve_*` RPC. One row per
/// pending submission (kind=`attribution`) or feature (kind=`new_feature`).
///
/// Rows survive process restarts so the user can resolve offline and the
/// worker drains the queue once connectivity returns.
class PendingResolutions extends Table {
  /// The submission UUID (kind=attribution) or feature UUID
  /// (kind=new_feature) being resolved.
  TextColumn get targetId => text()();

  /// `attribution` | `new_feature`.
  TextColumn get kind => text()();

  /// Wire-form decision: `keep_theirs`, `force_overwrite`, `keep_both`,
  /// `replace_theirs`, `discard_mine`.
  TextColumn get decision => text()();

  /// Optional free-text note attached to the audit log on the server.
  TextColumn get resolutionNote => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {targetId, kind};
}
