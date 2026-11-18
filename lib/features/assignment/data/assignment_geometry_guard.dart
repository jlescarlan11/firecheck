import 'dart:convert';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/point_in_polygon.dart';
import 'package:firecheck/core/geo/polygon_bounds.dart';

/// Run inside the same transaction as the geometry write.
Future<void> validateAssignmentGeometry(
    AppDatabase db, String assignmentId, String geometry) async {
  final assignment = await (db.select(db.assignments)
        ..where((t) => t.id.equals(assignmentId)))
      .getSingleOrNull();
  if (assignment == null || assignment.closedRemotely) {
    throw StateError('This map is unavailable or closed.');
  }
  final boundary = assignment.boundaryPolygonGeojson;
  if (boundary.isEmpty || polygonBoundsFromGeojson(boundary) == null) return;
  final decoded = jsonDecode(geometry) as Map<String, dynamic>;
  void check(dynamic coordinates) {
    if (coordinates is! List || coordinates.isEmpty) {
      throw const FormatException('Missing geometry coordinates');
    }
    if (coordinates.first is num) {
      if (coordinates.length < 2 ||
          !pointInPolygonGeojson(
            (coordinates[1] as num).toDouble(),
            (coordinates[0] as num).toDouble(),
            boundary,
          ))
        throw StateError(
            'This drawing is outside ${assignment.name ?? "this map"}’s study area.');
    } else {
      for (final child in coordinates) {
        check(child);
      }
    }
  }

  check(decoded['coordinates']);
}
