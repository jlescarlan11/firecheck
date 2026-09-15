import test from "node:test";
import assert from "node:assert/strict";
import { boundaryPolygon } from "../src/domain.js";
test("assignment boundaries require a closed WGS84 polygon", () => {
  const polygon = {
    type: "Polygon",
    coordinates: [
      [
        [123, 10],
        [124, 10],
        [124, 11],
        [123, 10],
      ],
    ],
  };
  assert.deepEqual(JSON.parse(boundaryPolygon(polygon)), polygon);
  assert.throws(() => boundaryPolygon({ ...polygon, type: "Point" }));
  assert.throws(() =>
    boundaryPolygon({
      type: "Polygon",
      coordinates: [
        [
          [123, 10],
          [124, 10],
          [124, 11],
          [123, 11],
        ],
      ],
    }),
  );
  assert.throws(() =>
    boundaryPolygon({
      type: "Polygon",
      coordinates: [
        [
          [123, 100],
          [124, 10],
          [124, 11],
          [123, 100],
        ],
      ],
    }),
  );
  assert.throws(() =>
    boundaryPolygon({
      type: "Polygon",
      coordinates: [
        [
          [Infinity, 10],
          [124, 10],
          [124, 11],
          [Infinity, 10],
        ],
      ],
    }),
  );
});
