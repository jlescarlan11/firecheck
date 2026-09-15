// Access token is read from the environment, never a command-line argument.
import { readFile } from "node:fs/promises";
const base = process.env.FIRECHECK_GATEWAY_URL;
const token = process.env.FIRECHECK_ACCESS_TOKEN;
if (!base || !token)
  throw new Error("Set FIRECHECK_GATEWAY_URL and FIRECHECK_ACCESS_TOKEN.");
const [command, a, b] = process.argv.slice(2);
const actions: Record<
  string,
  { method: string; path: string; body?: unknown }
> = {
  create: { method: "POST", path: "/v1/admin/assignments" },
  health: { method: "GET", path: "/v1/admin/health" },
  source: {
    method: "PUT",
    path: `/v1/admin/assignments/${a}/source`,
    body: { folderId: b },
  },
  publish: { method: "POST", path: `/v1/admin/assignments/${a}/publish` },
  enroll: { method: "PUT", path: `/v1/admin/assignments/${a}/members/${b}` },
  remove: { method: "DELETE", path: `/v1/admin/assignments/${a}/members/${b}` },
};
const action = actions[command ?? ""];
if (!action)
  throw new Error(
    "Commands: health | create ASSIGNMENT_JSON_FILE | source ASSIGNMENT FOLDER | publish ASSIGNMENT | enroll ASSIGNMENT USER | remove ASSIGNMENT USER",
  );
if (command === "create") {
  if (!a)
    throw new Error(
      "Specify a JSON file containing id, name, campaignId and WGS84 Polygon boundary.",
    );
  action.body = JSON.parse(await readFile(a, "utf8"));
}
const url = new URL(base);
url.pathname = url.pathname.replace(/\/+$/, "") + action.path;
if (url.protocol !== "https:" && url.hostname !== "localhost")
  throw new Error("HTTPS required");
const r = await fetch(url, {
  method: action.method,
  redirect: "error",
  headers: {
    Authorization: `Bearer ${token}`,
    ...(action.body ? { "Content-Type": "application/json" } : {}),
  },
  body: action.body ? JSON.stringify(action.body) : undefined,
});
console.log(r.status, await r.text());
if (!r.ok) process.exitCode = 1;
