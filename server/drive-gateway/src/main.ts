import pg from "pg";
import { buildApp } from "./app.js";
import { Database } from "./db.js";
import { driveFromEnvironment } from "./drive.js";
import { ApiError, assert } from "./domain.js";
function required(name: string) {
  const v = process.env[name];
  assert(v, 500, `MISSING_${name}`);
  return v;
}
const supabase = new URL(required("SUPABASE_URL"));
assert(supabase.protocol === "https:", 500, "SUPABASE_REQUIRES_HTTPS");
const pool = new pg.Pool({
  connectionString: required("DATABASE_URL"),
  max: 10,
  connectionTimeoutMillis: 10000,
});
const app = buildApp({
  database: new Database(pool),
  drive: await driveFromEnvironment(),
  config: {
    inputRoot: required("DRIVE_INPUT_ROOT"),
    outputRoot: required("DRIVE_OUTPUT_ROOT"),
    publishedRoot: required("DRIVE_PUBLISHED_ROOT"),
    sharedDrive: process.env.SHARED_DRIVE_ID,
  },
  authenticate: async (token) => {
    const r = await fetch(new URL("/auth/v1/user", supabase), {
      headers: {
        apikey: required("SUPABASE_PUBLISHABLE_KEY"),
        Authorization: `Bearer ${token}`,
      },
      signal: AbortSignal.timeout(10000),
      redirect: "error",
    });
    if (r.status === 401 || r.status === 403)
      throw new ApiError(401, "SESSION_EXPIRED");
    if (!r.ok) throw new ApiError(503, "AUTH_SERVICE_UNAVAILABLE");
    const result = (await r.json()) as { id?: string; is_anonymous?: boolean };
    assert(result.id && !result.is_anonymous, 401, "SESSION_EXPIRED");
    return result.id;
  },
});
await app.listen({ port: Number(process.env.PORT ?? 8080), host: "0.0.0.0" });
for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.on(signal, async () => {
    await app.close();
    await pool.end();
    process.exit(0);
  });
