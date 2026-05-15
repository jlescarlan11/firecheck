import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;

enum PolylineValidationError {
  notEnoughVertices,
  zeroLengthEdge,
}

PolylineValidationError? validatePolyline(List<LngLat> coords) {
  if (coords.length < 2) return PolylineValidationError.notEnoughVertices;
  for (var i = 1; i < coords.length; i++) {
    final a = coords[i - 1];
    final b = coords[i];
    if (a.lng == b.lng && a.lat == b.lat) {
      return PolylineValidationError.zeroLengthEdge;
    }
  }
  return null;
}
