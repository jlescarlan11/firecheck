# Export Completed Work as Attributed Shapefiles

**Date:** 2026-05-02
**Status:** Draft, awaiting review
**Author:** John Lester Escarlan (with brainstorming assistance)
**Branch:** 22-as-an-enumerator-i-want-the-app-to-package-my-completed-work-as-attributed-shapefiles-so-that-i-can-hand-it-back-in-the-format-the-course-expects

---

## User Story

> As an Enumerator, I want the app to package my completed work as attributed shapefiles, so that I can hand it back in the format the course expects.

---

## Acceptance Criteria

1. The app provides an export action accessible once an enumeration session has at least one completed feature.
2. Exporting produces a valid Esri shapefile bundle containing `.shp`, `.shx`, `.dbf`, `.prj`, and `.cpg`.
3. Each exported feature retains its geometry (point, line, or polygon) and is correctly georeferenced in WGS84 / EPSG:4326.
4. All field attributes captured during enumeration are written to the `.dbf` table, with column names and data types consistent across records.
5. Field names conform to shapefile constraints (max 10 characters, no spaces or special characters).
6. The exported files are bundled into a single `.zip` archive named with the session identifier and timestamp.
7. The user can save or share the exported archive through the device's standard file/share interface.
8. If export fails, the user sees a clear error message explaining the cause.
9. The exported shapefile opens correctly in QGIS or ArcGIS with all attributes intact.

---

## Decisions

| Topic | Choice | Rationale |
|---|---|---|
| Shapefile structure | Two shapefiles inside one ZIP (`buildings_*`, `roads_*`) | Shapefile format is homogeneous — polygon and polyline must be separate. One ZIP keeps the handoff simple. |
| `doesNotExist` features | Included with `NOT_EXIST = T` DBF field | A negative finding is still a finding; omitting silently makes coverage look incomplete. |
| Export action location | 4th action tile on HomeScreen | Consistent with the existing tile pattern; no new navigation layer needed. |
| JSON array fields | Pipe-delimited strings (e.g., `"sprinkler\|extinguisher"`) | Human-readable in QGIS attribute table; avoids embedding raw JSON in fixed-width DBF cells. |
| Writer approach | Pure Dart binary writer, no new dependencies | Mirrors existing `ShpParser`/`DbfParser` pattern. `archive` and `share_plus` already in pubspec. |
| CRS | WGS84 / EPSG:4326, no reprojection needed | Geometry is stored as GeoJSON (WGS84) in the DB; direct write. |
| Compute isolation | `compute` isolate for write step | Keeps the UI thread free; consistent with the pattern used elsewhere in the project. |
| Temp file cleanup | OS-managed via `getTemporaryDirectory()` | No proactive cleanup; consistent with the share-sheet pattern used by Upload Data. |
| Empty layers | Skip files for a geometry type with zero features | No point writing an empty shapefile; ZIP only contains layers that have data. |

---

## Architecture

### New files

```
lib/core/sync/shapefile/export/
  shp_writer.dart          ← writes .shp + .shx bytes (pure function, no Flutter deps)
  dbf_writer.dart          ← writes .dbf bytes (pure function, no Flutter deps)
  shapefile_exporter.dart  ← orchestrator: query DB → write → zip → share
  export_failure.dart      ← sealed failure types

lib/features/home/
  domain/export_state.dart                     ← Idle | Exporting | Done | Failed
  data/shapefile_export_notifier.dart          ← Riverpod notifier
  presentation/home_screen.dart                ← 4th action tile wired to notifier
```

### Data flow

1. User taps "Export Shapefile" tile on `HomeScreen`.
2. `ShapefileExportNotifier` transitions to `Exporting`; tile shows loading indicator.
3. Queries DB: all features with `status = 'complete'` for the current assignment, joined to `submissions` + `building_attributes` / `road_attributes`.
4. Splits by `featureType`: buildings → `buildings_*` files, roads → `roads_*` files. Layers with zero features are omitted.
5. In a `compute` isolate: writes `.shp`, `.shx`, `.dbf`, `.prj`, `.cpg` bytes for each non-empty type. The DB query runs on the main isolate first; only plain serializable structs (lists of coordinate arrays and field value maps) are passed into `compute`.
6. ZIPs all files into `firecheck_<assignmentId>_<yyyyMMddHHmmss>.zip` in `getTemporaryDirectory()`. The session identifier is the `assignments.id` UUID.
7. Calls `SharePlus.shareXFiles([XFile(zipPath)])` to open the system share sheet.
8. Notifier transitions to `Done` (resets to `Idle` after share sheet opens) or `Failed`.

---

## Binary Writer Internals

### `ShpWriter`

Produces paired `.shp` and `.shx` `Uint8List` values from a list of GeoJSON geometry objects.

**File header** (100 bytes, identical structure for both files):
- File code `9994` (big-endian int32)
- File length in 16-bit words (big-endian int32)
- Version `1000` (little-endian int32)
- Shape type: `5` = Polygon, `3` = Polyline (little-endian int32)
- Bounding box: minX, minY, maxX, maxY as float64 (little-endian)
- Remaining bbox fields (Zmin/Zmax/Mmin/Mmax) zero-filled

**Per record (`.shp`)**:
- Record header: record number (1-based, big-endian int32) + content length in 16-bit words (big-endian int32)
- Content: shape type (little-endian int32) + geometry bytes
  - Polygon: bbox (4× float64) + numParts (int32) + numPoints (int32) + parts array + points array
  - Polyline: same layout as Polygon

**Per record (`.shx`)**:
- 8 bytes: byte offset of record in `.shp` as 16-bit words (big-endian int32) + content length in 16-bit words (big-endian int32)

### `DbfWriter`

Produces `.dbf` `Uint8List` from a field schema and a list of record maps.

**File header** (32 bytes):
- Version `0x03`
- Date: YY, MM, DD (3 bytes)
- Record count (little-endian int32)
- Header size = `32 + (32 × fieldCount) + 1` (little-endian int16)
- Record size = `1 + Σ(field widths)` (little-endian int16)
- Remaining bytes zero-filled

**Field descriptors** (32 bytes each):
- Name: 11 bytes, null-padded
- Type char: `C` (character), `N` (numeric), `L` (logical)
- 4 bytes reserved
- Field length (uint8)
- Decimal count (uint8)
- Remaining bytes zero-filled

**Header terminator**: `0x0D`

**Records**:
- Deletion flag `0x20` (space = active record)
- Fixed-width ASCII fields, right-padded with spaces for `C`, left-padded with spaces for `N`
- `L` fields: `T` or `F`; null values write as space

**EOF marker**: `0x1A`

### Static files

| File | Content |
|---|---|
| `.prj` | `GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]` |
| `.cpg` | `UTF-8` |

---

## Field Mapping

### Buildings (`buildings.dbf`)

| DB column | DBF name | Type | Width | Notes |
|---|---|---|---|---|
| `features.id` | `FEAT_ID` | C | 36 | UUID |
| `building_attributes.cbmsId` | `CBMS_ID` | C | 20 | |
| `building_attributes.buildingName` | `BLDG_NAME` | C | 60 | |
| `building_attributes.ra9514Type` | `RA9514_TYPE` | C | 20 | |
| `building_attributes.storeys` | `STOREYS` | N | 3 | 0 decimals |
| `building_attributes.material` | `MATERIAL` | C | 30 | |
| `building_attributes.costIsExact` | `COST_EXACT` | L | 1 | |
| `building_attributes.costAmount` | `COST_AMT` | N | 12 | 2 decimals |
| `building_attributes.costEstimateRange` | `COST_RANGE` | C | 20 | |
| `building_attributes.fireFightingFacilitiesJson` | `FIRE_FACIL` | C | 254 | pipe-delimited |
| `building_attributes.fireLoadJson` | `FIRE_LOAD` | C | 254 | pipe-delimited |
| `submissions.doesNotExist` | `NOT_EXIST` | L | 1 | |
| `submissions.remarks` | `REMARKS` | C | 254 | |

### Roads (`roads.dbf`)

| DB column | DBF name | Type | Width | Notes |
|---|---|---|---|---|
| `features.id` | `FEAT_ID` | C | 36 | UUID |
| `road_attributes.isBridge` | `IS_BRIDGE` | L | 1 | |
| `road_attributes.roadName` | `ROAD_NAME` | C | 60 | |
| `road_attributes.widthMeters` | `WIDTH_M` | N | 8 | 2 decimals |
| `road_attributes.roadFeaturesJson` | `ROAD_FEAT` | C | 254 | pipe-delimited |
| `road_attributes.othersDescription` | `OTHER_DESC` | C | 254 | |
| `submissions.doesNotExist` | `NOT_EXIST` | L | 1 | |
| `submissions.remarks` | `REMARKS` | C | 254 | |

---

## Error Handling

### `ExportFailure` (sealed class)

| Subtype | Cause | User message |
|---|---|---|
| `NoCompletedFeatures` | Export triggered with no completed features | "No completed features to export." |
| `WriteError(message)` | I/O failure writing to temp directory | "Export failed: could not write files. Please try again." |
| `ShareError(message)` | `SharePlus` invocation failed | "Export ready but could not open share sheet. Please try again." |

### `ExportState` state machine

```
Idle ──tap──▶ Exporting ──success──▶ Done ──(auto)──▶ Idle
                        ──failure──▶ Failed(ExportFailure) ──(snackbar)──▶ Idle
```

- **`Idle`**: tile enabled if `completedFeatures > 0`, disabled otherwise.
- **`Exporting`**: tile shows loading indicator; repeat taps are no-ops.
- **`Done`**: share sheet opens; notifier auto-resets to `Idle`.
- **`Failed`**: `SnackBar` shows human-readable message; notifier auto-resets to `Idle`.

---

## Testing

### `shp_writer_test.dart`
- Write a polygon feature → parse bytes with existing `ShpParser` → assert coordinates match
- Write a polyline feature → same round-trip assertion
- Assert bounding box in file header matches feature extents
- Assert `.shx` offsets correctly index each record

### `dbf_writer_test.dart`
- Write building fields → parse bytes with existing `DbfParser` → assert field names, types, and values match
- Write road fields → same round-trip assertion
- Null DB values → blank strings / blank numerics in output
- `doesNotExist = true` → `NOT_EXIST` field writes `T`
- JSON array → pipe-delimited string in `FIRE_FACIL` / `ROAD_FEAT`

### `shapefile_exporter_test.dart`
- 2 completed buildings + 1 completed road → ZIP contains exactly 10 files
- 0 completed features → `NoCompletedFeatures` failure
- Only buildings, no roads → ZIP contains 5 building files only (roads layer skipped)
- Building with `doesNotExist = true` → feature present in output with `NOT_EXIST = T`

### `shapefile_export_notifier_test.dart`
- Happy path: `Idle → Exporting → Done`
- Export failure: `Idle → Exporting → Failed(WriteError)`
- Tap while `Exporting` → state stays `Exporting` (no-op)
- After `Done` → notifier resets to `Idle`
