import 'package:firecheck/core/geo/ph_epsg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

void main() {
  group('phEpsgRegistry', () {
    test('contains every CRS FireCheck advertises for PH work', () {
      // The keys here are load-bearing: removing one is a breaking change
      // for anyone whose form-variant config (or future picker) points at it.
      expect(phEpsgRegistry.keys, containsAll(<int>[
        4326, 4683,
        32650, 32651,
        3121, 3122, 3123, 3124, 3125,
      ]));
    });

    test('every WKT carries its own AUTHORITY["EPSG","<code>"]', () {
      // Missing AUTHORITY codes are the #1 reason QGIS prompts users to
      // pick a CRS when a shapefile loads. Catch any drift here.
      for (final entry in phEpsgRegistry.entries) {
        expect(
          entry.value.wkt,
          contains('AUTHORITY["EPSG","${entry.key}"]'),
          reason: 'EPSG:${entry.key} WKT is missing its self-authority',
        );
      }
    });

    test('every proj4 string parses through proj4dart without throwing', () {
      // If any proj4 string is malformed, reprojection would crash at
      // export time on a real device — much better to catch it here.
      for (final crs in phEpsgRegistry.values) {
        expect(
          () => proj4.Projection.parse(crs.proj4),
          returnsNormally,
          reason: 'EPSG:${crs.epsg} (${crs.name}) proj4 failed to parse',
        );
      }
    });
  });

  group('requirePhCrs', () {
    test('returns the registered CRS for a known code', () {
      expect(requirePhCrs(32651).epsg, 32651);
      expect(requirePhCrs(32651).name, contains('UTM zone 51N'));
    });

    test('throws ArgumentError for an unknown code', () {
      expect(() => requirePhCrs(99999), throwsArgumentError);
    });
  });

  group('reprojection sanity (Manila → UTM 51N)', () {
    test('WGS84 (121°E, 14°N) lands near (281km E, 1549km N) in EPSG:32651', () {
      // Manila roughly at 121°E, 14.5°N. UTM 51N central meridian is 123°E,
      // so Manila sits ~2° west — easting ends up well left of the
      // 500,000 m false-easting baseline (so roughly ~280–290 km).
      // Northing in the northern hemisphere is ~latitude × 111 km, so
      // 14° → ~1549 km. These tolerances are loose enough to survive minor
      // datum-shift differences but tight enough to catch a swapped axis or
      // a wrong central meridian.
      final wgs = proj4.Projection.parse(phEpsgRegistry[4326]!.proj4);
      final utm = proj4.Projection.parse(phEpsgRegistry[32651]!.proj4);
      final pt = wgs.transform(utm, proj4.Point(x: 121.0, y: 14.0));
      expect(pt.x, closeTo(281000, 5000));
      expect(pt.y, closeTo(1549000, 5000));
    });
  });
}
