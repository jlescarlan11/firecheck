"""
Generates test shapefiles (boundary, buildings, roads) in EPSG:32651
near Cebu City for manual UI testing of the Get Maps flow.

Usage:
    python3 tools/generate_test_shapefiles.py

Output: tools/test_shapefiles/ — upload all 12 files to your Drive
folder (e.g. firecheck/inbox/cebu/).
"""

import os
import shapefile

OUT = os.path.join(os.path.dirname(__file__), "test_shapefiles")
os.makedirs(OUT, exist_ok=True)

# EPSG:32651 — WGS 84 / UTM Zone 51N (covers Philippines)
PRJ = (
    'PROJCS["WGS_1984_UTM_Zone_51N",'
    'GEOGCS["GCS_WGS_1984",'
    'DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],'
    'PRIMEM["Greenwich",0.0],'
    'UNIT["Degree",0.0174532925199433]],'
    'PROJECTION["Transverse_Mercator"],'
    'PARAMETER["False_Easting",500000.0],'
    'PARAMETER["False_Northing",0.0],'
    'PARAMETER["Central_Meridian",123.0],'
    'PARAMETER["Scale_Factor",0.9996],'
    'PARAMETER["Latitude_Of_Origin",0.0],'
    'UNIT["Meter",1.0]],'
    'AUTHORITY["EPSG","32651"]]'
)

# Cebu City centre in UTM Zone 51N (approx)
CX, CY = 598550.0, 1138900.0


def write_prj(name):
    with open(os.path.join(OUT, f"{name}.prj"), "w") as f:
        f.write(PRJ)


# ── boundary (1 km × 1 km polygon) ─────────────────────────────────────────
w = shapefile.Writer(os.path.join(OUT, "boundary"), shapeType=5)
w.field("feat_id", "C", 10)
w.poly([[
    [CX - 500, CY - 500],
    [CX + 500, CY - 500],
    [CX + 500, CY + 500],
    [CX - 500, CY + 500],
    [CX - 500, CY - 500],
]])
w.record("BOUND-1")
w.close()
write_prj("boundary")

# ── buildings (3 small polygons inside boundary) ────────────────────────────
w = shapefile.Writer(os.path.join(OUT, "buildings"), shapeType=5)
w.field("feat_id",  "C", 10)
w.field("bldg_use", "C", 20)
w.field("bldg_type","C", 20)

buildings = [
    ([CX-300, CY-300, CX-200, CY-200], "BLD-001", "residential", "house"),
    ([CX+100, CY+100, CX+220, CY+200], "BLD-002", "commercial",  "shop"),
    ([CX-100, CY+200, CX+000, CY+320], "BLD-003", "residential", "apartment"),
]
for (x0, y0, x1, y1), fid, use, typ in buildings:
    w.poly([[
        [x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0],
    ]])
    w.record(fid, use, typ)
w.close()
write_prj("buildings")

# ── roads (2 line segments) ─────────────────────────────────────────────────
w = shapefile.Writer(os.path.join(OUT, "roads"), shapeType=3)
w.field("feat_id",  "C", 10)
w.field("road_type","C", 20)

w.line([[[CX - 480, CY], [CX + 480, CY]]])
w.record("RD-001", "local")

w.line([[[CX, CY - 480], [CX, CY + 480]]])
w.record("RD-002", "local")

w.close()
write_prj("roads")

print(f"Created 12 files in {OUT}/")
print("Upload them all to: My Drive/firecheck/inbox/cebu/")
