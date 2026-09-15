import pg from "pg";
import { buildApp } from "./generated/app.js";
import { Database } from "./generated/db.js";
import { driveFromEnvironment } from "./generated/drive.js";
import { ApiError } from "./generated/domain.js";

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing gateway configuration: ${name}`);
  return value;
}
// Google credentials exist only in this function's server environment.
const oauth = JSON.parse(required("FIRECHECK_DRIVE_OAUTH"));
for (const key of [
  "GOOGLE_CLIENT_ID",
  "GOOGLE_CLIENT_SECRET",
  "GOOGLE_REFRESH_TOKEN",
]) {
  if (typeof oauth[key] !== "string" || !oauth[key])
    throw new Error("Invalid Drive credential bundle");
}
const supabase = new URL(required("SUPABASE_URL"));
const databaseUrl = new URL(required("FIRECHECK_DATABASE_URL"));
for (const key of ["sslmode", "sslrootcert", "sslcert", "sslkey"])
  databaseUrl.searchParams.delete(key);
const pool = new pg.Pool({
  connectionString: databaseUrl.toString(),
  ssl: {
    rejectUnauthorized: true,
    ca: atob(required("FIRECHECK_DB_CA_BASE64")),
  },
  max: 2,
  idleTimeoutMillis: 10000,
  connectionTimeoutMillis: 10000,
});
const app = buildApp({
  database: new Database(pool),
  drive: await driveFromEnvironment({ ...oauth, DRIVE_AUTH_MODE: "oauth" }),
  config: {
    inputRoot: required("DRIVE_INPUT_ROOT"),
    outputRoot: required("DRIVE_OUTPUT_ROOT"),
    publishedRoot: required("DRIVE_PUBLISHED_ROOT"),
    routePrefix: "/drive-gateway",
  },
  authenticate: async (token: string) => {
    const response = await fetch(new URL("/auth/v1/user", supabase), {
      headers: {
        apikey: required("SUPABASE_ANON_KEY"),
        Authorization: `Bearer ${token}`,
      },
      signal: AbortSignal.timeout(10000),
      redirect: "error",
    });
    if (response.status === 401 || response.status === 403)
      throw new ApiError(401, "SESSION_EXPIRED");
    if (!response.ok) throw new ApiError(503, "AUTH_SERVICE_UNAVAILABLE");
    const user = await response.json();
    if (!user.id || user.is_anonymous)
      throw new ApiError(401, "SESSION_EXPIRED");
    return user.id;
  },
});
// Supabase supports Node HTTP servers. This retains streamed downloads without
// buffering app.inject() responses or duplicating the authorization handlers.
await app.listen({ port: 8000, host: "0.0.0.0" });
