// lib/core/sync/shapefile/reprojector.dart
import 'package:proj4dart/proj4dart.dart';

class Reprojector {
  Reprojector() {
    _from = Projection.parse(
      '+proj=utm +zone=51 +datum=WGS84 +units=m +no_defs',
    );
    _to = Projection.parse('+proj=longlat +datum=WGS84 +no_defs');
  }

  late final Projection _from;
  late final Projection _to;

  /// Returns [longitude, latitude] in EPSG:4326 for a given UTM 51N coordinate.
  List<double> reproject(double easting, double northing) {
    final pt = _from.transform(_to, Point(x: easting, y: northing));
    return [pt.x, pt.y];
  }

  List<List<double>> reprojectRing(List<List<double>> ring) =>
      ring.map((pt) => reproject(pt[0], pt[1])).toList();
}
