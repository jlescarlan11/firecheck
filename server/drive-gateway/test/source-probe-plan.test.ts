import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  capacityFixture,
  localProbeDatabase,
  retainedPayloadBound,
} from "../src/development-probe.js";
import { validateMap } from "../src/domain.js";
test("capacity fixture hits exact metadata maximum with tiny first-copy failure and bounded retained payload", () => {
  const files = capacityFixture();
  assert.equal(files.length, 100);
  assert.equal(
    files.reduce((n, f) => n + f.size, 0),
    1024 ** 3,
  );
  assert.equal(files[0]!.size, 64);
  assert.ok(files.every((f) => f.size <= 512 * 1024 ** 2));
  assert.equal(
    new Set(files.map((f) => f.name.replace(/\.[^.]+$/, ""))).size,
    25,
  );
  validateMap(
    files.map((f, i) => ({
      ...f,
      id: `00000000-0000-0000-0000-${String(i).padStart(12, "0")}`,
      driveId: String(i),
      md5: "0".repeat(32),
    })),
  );
  assert.equal(retainedPayloadBound(files), 3 * 1024 ** 3 + 64);
  assert.ok(retainedPayloadBound(files) < 4 * 1024 ** 3);
});
test("probe database rejects remote and other local servers before any write", () => {
  for (const uri of [
    "postgresql://postgres:synthetic@db.example.com:55441/postgres",
    "postgresql://postgres:synthetic@127.0.0.1:5432/postgres",
    "postgresql://postgres:synthetic@127.0.0.1:55441/userdata",
  ])
    assert.throws(() => localProbeDatabase(uri, "firecheck_devprobe_abc"));
  assert.equal(
    new URL(
      localProbeDatabase(
        "postgresql://postgres:synthetic@127.0.0.1:55441/postgres",
        "firecheck_devprobe_abc",
      ),
    ).pathname,
    "/firecheck_devprobe_abc",
  );
});

test("probe database rejects invalid generated names and URI query overrides independently", () => {
  const uri = "postgresql://postgres:synthetic@127.0.0.1:55441/postgres";
  assert.throws(() => localProbeDatabase(uri, "probe_test"));
  assert.throws(() =>
    localProbeDatabase(uri + "?host=db.example.com", "firecheck_devprobe_abc"),
  );
});
