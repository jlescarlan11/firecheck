// lib/core/geo/ph_epsg.dart
//
// Coordinate-reference systems commonly used in Philippine surveying work.
// The registry pairs each EPSG code with the proj4 string used by
// `proj4dart` for math and the WKT string used in the .prj sidecar so QGIS
// (and any other Esri-spec reader) recognizes the CRS without prompting.
//
// All WKT strings include the full AUTHORITY chain — this is what stops
// QGIS from showing a "select CRS" dialog when a shapefile loads.
//
// Storage convention: FireCheck holds geometries in EPSG:4326 (GeoJSON
// convention). [ShapefileExporter] reprojects to the chosen target only at
// export time.

class PhCrs {
  const PhCrs({
    required this.epsg,
    required this.name,
    required this.proj4,
    required this.wkt,
    required this.description,
  });
  final int epsg;
  final String name;
  final String proj4;
  final String wkt;
  final String description;
}

const PhCrs _wgs84 = PhCrs(
  epsg: 4326,
  name: 'WGS 84',
  proj4: '+proj=longlat +datum=WGS84 +no_defs',
  wkt:
      'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]]',
  description: 'Geographic lng/lat. Default storage and export CRS.',
);

const PhCrs _prs92 = PhCrs(
  epsg: 4683,
  name: 'PRS92',
  proj4:
      '+proj=longlat +ellps=GRS80 +towgs84=-127.62,-67.24,-47.04,3.068,-4.903,1.578,-1.06 +no_defs',
  wkt:
      'GEOGCS["PRS92",DATUM["Philippine_Reference_System_1992",SPHEROID["GRS 1980",6378137,298.257222101,AUTHORITY["EPSG","7019"]],TOWGS84[-127.62,-67.24,-47.04,3.068,-4.903,1.578,-1.06],AUTHORITY["EPSG","6683"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4683"]]',
  description: 'Philippine Reference System 1992 (geographic, lng/lat).',
);

const PhCrs _utm50n = PhCrs(
  epsg: 32650,
  name: 'WGS 84 / UTM zone 50N',
  proj4: '+proj=utm +zone=50 +datum=WGS84 +units=m +no_defs',
  wkt:
      'PROJCS["WGS 84 / UTM zone 50N",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]],PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",0],PARAMETER["central_meridian",117],PARAMETER["scale_factor",0.9996],PARAMETER["false_easting",500000],PARAMETER["false_northing",0],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH],AUTHORITY["EPSG","32650"]]',
  description: 'Projected metres. Covers Palawan and the western edge.',
);

const PhCrs _utm51n = PhCrs(
  epsg: 32651,
  name: 'WGS 84 / UTM zone 51N',
  proj4: '+proj=utm +zone=51 +datum=WGS84 +units=m +no_defs',
  wkt:
      'PROJCS["WGS 84 / UTM zone 51N",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]],PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",0],PARAMETER["central_meridian",123],PARAMETER["scale_factor",0.9996],PARAMETER["false_easting",500000],PARAMETER["false_northing",0],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH],AUTHORITY["EPSG","32651"]]',
  description:
      'Projected metres. Covers Luzon, NCR, eastern Visayas, most Mindanao.',
);

// PRS92 zones share GRS80 + the same TOWGS84 shift; only the central
// meridian and EPSG code change per zone.
String _prs92ZoneProj4(int centralMeridian) =>
    '+proj=tmerc +lat_0=0 +lon_0=$centralMeridian +k=0.99995 +x_0=500000 +y_0=0 +ellps=GRS80 +towgs84=-127.62,-67.24,-47.04,3.068,-4.903,1.578,-1.06 +units=m +no_defs';

String _prs92ZoneWkt(int epsg, int zoneNum, int centralMeridian) {
  return 'PROJCS["PRS92 / Philippines zone $zoneNum",GEOGCS["PRS92",DATUM["Philippine_Reference_System_1992",SPHEROID["GRS 1980",6378137,298.257222101,AUTHORITY["EPSG","7019"]],TOWGS84[-127.62,-67.24,-47.04,3.068,-4.903,1.578,-1.06],AUTHORITY["EPSG","6683"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4683"]],PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",0],PARAMETER["central_meridian",$centralMeridian],PARAMETER["scale_factor",0.99995],PARAMETER["false_easting",500000],PARAMETER["false_northing",0],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH],AUTHORITY["EPSG","$epsg"]]';
}

PhCrs _prs92Zone({
  required int epsg,
  required int zoneNum,
  required int centralMeridian,
  required String coverage,
}) =>
    PhCrs(
      epsg: epsg,
      name: 'PRS92 / Philippines zone $zoneNum',
      proj4: _prs92ZoneProj4(centralMeridian),
      wkt: _prs92ZoneWkt(epsg, zoneNum, centralMeridian),
      description: 'PRS92 zone $zoneNum (central meridian $centralMeridian°E). $coverage',
    );

/// Lookup table of every CRS this app recognizes for Philippine survey work.
/// Keyed by EPSG code so callers can write things like
/// `phEpsgRegistry[32651]` without remembering the constant name.
final Map<int, PhCrs> phEpsgRegistry = Map.unmodifiable({
  4326: _wgs84,
  4683: _prs92,
  32650: _utm50n,
  32651: _utm51n,
  3121: _prs92Zone(
    epsg: 3121,
    zoneNum: 1,
    centralMeridian: 117,
    coverage: 'Far western Philippines (Palawan, Sulu Sea).',
  ),
  3122: _prs92Zone(
    epsg: 3122,
    zoneNum: 2,
    centralMeridian: 119,
    coverage: 'Western Visayas, western Mindoro.',
  ),
  3123: _prs92Zone(
    epsg: 3123,
    zoneNum: 3,
    centralMeridian: 121,
    coverage: 'Luzon (Metro Manila, central Visayas).',
  ),
  3124: _prs92Zone(
    epsg: 3124,
    zoneNum: 4,
    centralMeridian: 123,
    coverage: 'Eastern Visayas, central Mindanao.',
  ),
  3125: _prs92Zone(
    epsg: 3125,
    zoneNum: 5,
    centralMeridian: 125,
    coverage: 'Eastern Mindanao.',
  ),
});

/// Throws [ArgumentError] if the EPSG code isn't in the PH registry.
/// Callers should validate user input through this lookup so an unknown
/// code can't silently fall through to a default CRS.
PhCrs requirePhCrs(int epsg) {
  final crs = phEpsgRegistry[epsg];
  if (crs == null) {
    throw ArgumentError.value(
      epsg,
      'epsg',
      'Not a Philippine EPSG code FireCheck recognizes. '
          'Known: ${phEpsgRegistry.keys.toList()}',
    );
  }
  return crs;
}
