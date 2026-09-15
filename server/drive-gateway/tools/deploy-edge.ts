/** Deploy the approved free-plan gateway. Secret values never enter arguments. */
import { readFile, writeFile, chmod } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { parseEnv } from "node:util";
import { spawnSync } from "node:child_process";

const here = fileURLToPath(new URL("../", import.meta.url));
const root = fileURLToPath(new URL("../../../", import.meta.url));
const project = "xmigquvscisdqtrepdwv";
async function main() {
  const oauth = JSON.parse(
    await readFile(join(here, ".secrets/drive/oauth.json"), "utf8"),
  );
  const folders = JSON.parse(
    await readFile(join(here, ".secrets/drive-folders.json"), "utf8"),
  );
  const database = parseEnv(
    await readFile(join(here, ".secrets/database.env"), "utf8"),
  );
  const ca = await readFile(join(here, ".secrets/supabase-ca.crt"));
  const values: Record<string, string> = {
    FIRECHECK_DRIVE_OAUTH: JSON.stringify(oauth),
    FIRECHECK_DATABASE_URL: database.FIRECHECK_DATABASE_URL!,
    FIRECHECK_DB_CA_BASE64: ca.toString("base64"),
    DRIVE_INPUT_ROOT: folders.DRIVE_INPUT_ROOT,
    DRIVE_OUTPUT_ROOT: folders.DRIVE_OUTPUT_ROOT,
    DRIVE_PUBLISHED_ROOT: folders.DRIVE_PUBLISHED_ROOT,
  };
  for (const value of Object.values(values))
    if (!value || /[\r\n]/.test(value))
      throw new Error("Invalid deployment configuration");
  const envFile = join(here, ".secrets/edge.env");
  await writeFile(
    envFile,
    Object.entries(values)
      .map(([key, value]) => `${key}=${value}`)
      .join("\n") + "\n",
    { mode: 0o600 },
  );
  await chmod(envFile, 0o600);
  for (const args of [
    ["secrets", "set", "--project-ref", project, "--env-file", envFile],
    [
      "functions",
      "deploy",
      "drive-gateway",
      "--project-ref",
      project,
      "--use-api",
    ],
  ]) {
    const result = spawnSync("supabase", args, { cwd: root, encoding: "utf8" });
    if (result.status !== 0) {
      await writeFile(
        join(here, ".secrets/deploy-error.log"),
        result.stdout + result.stderr,
        { mode: 0o600 },
      );
      throw new Error(
        "Deployment command failed. Inspect the restricted local deployment log.",
      );
    }
    console.log(`${args[0]} ${args[1]} succeeded.`);
  }
  const url = `https://${project}.supabase.co/functions/v1/drive-gateway`;
  const health = await fetch(`${url}/healthz`, {
    signal: AbortSignal.timeout(30000),
  });
  if (!health.ok || !(await health.json()).ok)
    throw new Error("Deployed health check failed.");
  const denied = await fetch(`${url}/v1/assignments`, {
    signal: AbortSignal.timeout(30000),
  });
  if (denied.status !== 401)
    throw new Error("Deployed authentication check failed.");
  console.log(`Deployed and verified health/authentication: ${url}`);
  console.log(
    "Verify worker activation status and complete on-device transfer checks before rollout.",
  );
}
main().catch(() => {
  console.error(
    "Deployment did not complete. Check the local configuration and restricted deployment log. No credentials were printed.",
  );
  process.exitCode = 1;
});
