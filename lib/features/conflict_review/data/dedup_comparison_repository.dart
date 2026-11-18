import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/comparison_geometry.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/features/conflict_review/data/conflict_review_repository.dart';
import 'package:firecheck/features/conflict_review/domain/dedup_comparison.dart';

/// Reads only the signed-in account's selected downloaded assignment.
/// Superseded cache rows take precedence over older local snapshots.
class DedupComparisonRepository {
  const DedupComparisonRepository(this.db);
  final AppDatabase db;

  Stream<DedupComparison?> watch({
    required String featureId,
    required String assignmentId,
    required String accountId,
  }) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.features,
            db.remoteNewFeaturesCache,
            db.assignmentSelections,
            db.assignments,
          },
        )
        .watch()
        .asyncMap(
          (_) => load(
            featureId: featureId,
            assignmentId: assignmentId,
            accountId: accountId,
          ),
        );
  }

  Future<DedupComparison?> load({
    required String featureId,
    required String assignmentId,
    required String accountId,
  }) =>
      db.transaction(() async {
        final selected = await (db.select(db.assignmentSelections)
              ..where(
                (t) =>
                    t.userId.equals(accountId) &
                    t.assignmentId.equals(assignmentId),
              ))
            .getSingleOrNull();
        final assignment = await (db.select(db.assignments)
              ..where((t) => t.id.equals(assignmentId)))
            .getSingleOrNull();
        if (selected == null ||
            assignment == null ||
            assignment.downloadedAt == null ||
            assignment.closedRemotely) {
          return null;
        }
        final mine = await (db.select(db.features)
              ..where(
                (t) =>
                    t.id.equals(featureId) &
                    t.assignmentId.equals(assignmentId),
              ))
            .getSingleOrNull();
        if (mine == null ||
            mine.pendingDedupOf == null ||
            mine.pendingDedupOf == mine.id ||
            !_active(mine)) {
          return null;
        }
        final local = await (db.select(db.features)
              ..where(
                (t) =>
                    t.id.equals(mine.pendingDedupOf!) &
                    t.assignmentId.equals(assignmentId),
              ))
            .getSingleOrNull();
        final remote = await (db.select(db.remoteNewFeaturesCache)
              ..where((t) => t.id.equals(mine.pendingDedupOf!)))
            .getSingleOrNull();
        if (remote != null &&
            (remote.assignmentId != assignmentId ||
                remote.supersededAt != null ||
                remote.supersededById != null)) {
          return null;
        }
        if (local != null && !_active(local)) return null;
        final type = remote?.featureType ?? local?.featureType;
        final geometry = remote?.geometryGeojson ?? local?.geometryGeojson;
        if (type == null || geometry == null || type != mine.featureType) {
          return null;
        }
        final mineGeometry = _geometry(mine.featureType, mine.geometryGeojson);
        final existingGeometry = _geometry(type, geometry);
        if (mineGeometry == null || existingGeometry == null) return null;
        return DedupComparison(
          assignmentId: assignmentId,
          accountId: accountId,
          mine: ComparedFeature(
            id: mine.id,
            featureType: mine.featureType,
            geometry: mineGeometry,
          ),
          existing: ComparedFeature(
            id: mine.pendingDedupOf!,
            featureType: type,
            geometry: existingGeometry,
          ),
        );
      });

  Future<void> queueDecision({
    required DedupComparison comparison,
    required DedupDecision decision,
    required ConflictReviewRepository resolutions,
    bool Function()? isCurrentContext,
  }) =>
      db.transaction(() async {
        final latest = await load(
          featureId: comparison.mine.id,
          assignmentId: comparison.assignmentId,
          accountId: comparison.accountId,
        );
        if ((isCurrentContext != null && !isCurrentContext()) ||
            latest == null ||
            latest.existing.id != comparison.existing.id ||
            latest.mine.geometry.source != comparison.mine.geometry.source ||
            latest.existing.geometry.source !=
                comparison.existing.geometry.source) {
          throw StateError('Comparison changed');
        }
        await resolutions.queueDedupDecision(
          featureId: comparison.mine.id,
          decision: decision,
        );
      });

  bool _active(Feature row) =>
      row.mergedIntoId == null &&
      !{'deleted', 'superseded', 'discarded'}.contains(row.status);
  ComparisonGeometry? _geometry(String type, String value) {
    final geometry = ComparisonGeometry.parse(value);
    final allowed = switch (type) {
      'building' => {'Polygon', 'MultiPolygon'},
      'road' => {'LineString'},
      'point' => {'Point'},
      _ => <String>{}
    };
    return geometry != null && allowed.contains(geometry.type)
        ? geometry
        : null;
  }
}
