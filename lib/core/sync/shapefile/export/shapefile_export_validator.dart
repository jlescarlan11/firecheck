import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';

class ShapefileExportValidator {
  const ShapefileExportValidator({required this.db});
  final AppDatabase db;

  Future<ExportValidationResult> validate(String assignmentId) async {
    final errors = <ExportLayerError>[];

    for (final layer in ExportLayer.values) {
      final featureType =
          layer == ExportLayer.buildings ? 'building' : 'road';

      final totalComplete = await _countComplete(assignmentId, featureType);
      if (totalComplete == 0) {
        errors.add(
          ExportLayerError(layer: layer, issue: ExportLayerIssue.emptyLayer),
        );
        continue;
      }

      final exportable =
          await _countExportable(assignmentId, featureType, layer);
      if (exportable < totalComplete) {
        errors.add(
          ExportLayerError(
            layer: layer,
            issue: ExportLayerIssue.missingRequiredFields,
          ),
        );
      }
    }

    return ExportValidationResult(errors: errors);
  }

  Future<int> _countComplete(
    String assignmentId,
    String featureType,
  ) async {
    final countExpr = db.features.id.count();
    final query = db.selectOnly(db.features)
      ..addColumns([countExpr])
      ..where(
        db.features.assignmentId.equals(assignmentId) &
            db.features.featureType.equals(featureType) &
            db.features.status.equals('complete'),
      );
    return query.map((row) => row.read(countExpr)!).getSingle();
  }

  Future<int> _countExportable(
    String assignmentId,
    String featureType,
    ExportLayer layer,
  ) async {
    final countExpr = db.features.id.count();

    if (layer == ExportLayer.buildings) {
      final query = db.selectOnly(db.features).join([
        innerJoin(
          db.submissions,
          db.submissions.featureId.equalsExp(db.features.id),
        ),
        innerJoin(
          db.buildingAttributes,
          db.buildingAttributes.submissionId.equalsExp(db.submissions.id),
        ),
      ])
        ..addColumns([countExpr])
        ..where(
          db.features.assignmentId.equals(assignmentId) &
              db.features.featureType.equals(featureType) &
              db.features.status.equals('complete'),
        );
      return query.map((row) => row.read(countExpr)!).getSingle();
    } else {
      final query = db.selectOnly(db.features).join([
        innerJoin(
          db.submissions,
          db.submissions.featureId.equalsExp(db.features.id),
        ),
        innerJoin(
          db.roadAttributes,
          db.roadAttributes.submissionId.equalsExp(db.submissions.id),
        ),
      ])
        ..addColumns([countExpr])
        ..where(
          db.features.assignmentId.equals(assignmentId) &
              db.features.featureType.equals(featureType) &
              db.features.status.equals('complete'),
        );
      return query.map((row) => row.read(countExpr)!).getSingle();
    }
  }
}
