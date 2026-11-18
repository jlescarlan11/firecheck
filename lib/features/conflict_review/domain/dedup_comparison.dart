import 'package:firecheck/core/geo/comparison_geometry.dart';

class ComparedFeature {
  const ComparedFeature({
    required this.id,
    required this.featureType,
    required this.geometry,
  });
  final String id;
  final String featureType;
  final ComparisonGeometry geometry;
}

class DedupComparison {
  const DedupComparison({
    required this.assignmentId,
    required this.accountId,
    required this.mine,
    required this.existing,
  });
  final String assignmentId;
  final String accountId;
  final ComparedFeature mine;
  final ComparedFeature existing;
}
