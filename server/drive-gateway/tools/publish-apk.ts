/** Upload release APKs only; never changes survey folders. */
import { OAuth2Client } from "google-auth-library";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile, writeFile, mkdir, rmdir, readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { driveFromEnvironment, type Drive } from "../src/drive.js";

export function releaseInfo(badging: string) {
  const match = badging.match(
    /package: name='ph\.gov\.bfp\.firecheck' versionCode='(\d+)' versionName='([\w.+-]+)'/,
  );
  if (!match || !/native-code: 'arm64-v8a'\s*$/m.test(badging)) {
    throw new Error("Expected a FireCheck ARM64 APK.");
  }
  return { code: Number(match[1]), version: match[2]! };
}

export async function uploadVerified(drive: Drive, id: string, bytes: Buffer) {
  const md5 = createHash("md5").update(bytes).digest("hex");
  const prior = await drive.metadata(id);
  if (prior.md5Checksum === md5 && Number(prior.size) === bytes.length) return;
  const session = await drive.begin(id, bytes.length);
  let offset = 0;
  let failures = 0;
  while (offset < bytes.length) {
    const chunk = bytes.subarray(offset, offset + 8 * 1024 * 1024);
    try {
      await drive.chunk(session, chunk, offset, bytes.length);
      offset += chunk.length;
      failures = 0;
    } catch {
      if (++failures > 3)
        throw new Error("APK upload interrupted; rerun to retry.");
      const status = await drive.status(session, bytes.length);
      if (status.expired)
        throw new Error("APK upload session expired; rerun to retry.");
      offset = status.offset;
    }
    console.log(`APK upload: ${Math.floor((offset / bytes.length) * 100)}%`);
  }
  const stored = await drive.metadata(id);
  if (stored.md5Checksum !== md5 || Number(stored.size) !== bytes.length) {
    throw new Error("Uploaded APK checksum or size does not match.");
  }
}

async function main() {
  const root = fileURLToPath(new URL("../../../", import.meta.url));
  const secrets = join(root, "server/drive-gateway/.secrets");
  const configPath = join(secrets, "apk-release.json");
  const config = JSON.parse(await readFile(configPath, "utf8"));
  const apk = resolve(
    root,
    process.argv.find((a) => a.endsWith(".apk")) ??
      "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk",
  );
  const sdk =
    process.env.ANDROID_SDK_ROOT ??
    process.env.ANDROID_HOME ??
    join(homedir(), "Library/Android/sdk");
  const versions = (await readdir(join(sdk, "build-tools"))).sort((a, b) =>
    b.localeCompare(a, undefined, { numeric: true }),
  );
  const aapt =
    process.env.AAPT ?? join(sdk, "build-tools", versions[0]!, "aapt");
  const info = releaseInfo(
    execFileSync(aapt, ["dump", "badging", apk], { encoding: "utf8" }),
  );
  const bytes = await readFile(apk);
  execFileSync("python3", [join(root, "tool/check_apk_size.py"), apk], {
    stdio: "inherit",
  });
  const md5 = createHash("md5").update(bytes).digest("hex");
  if (info.code < (config.versionCode ?? 0))
    throw new Error("Refusing to publish an older APK.");
  if (info.code === config.versionCode && config.md5 !== md5)
    throw new Error("Changed APK requires a higher build number.");
  console.log(
    `Release ${info.version} (${info.code}), ARM64, ${(bytes.length / 1e6).toFixed(2)} MB`,
  );
  if (!process.argv.includes("--apply")) {
    console.log("Dry run: add --apply to upload.");
    return;
  }
  const lock = join(secrets, "apk-publish.lock");
  await mkdir(lock); // Prevent concurrent publishers from replacing Latest out of order.
  try {
    const drive = await driveFromEnvironment({
      DRIVE_AUTH_MODE: "oauth",
      GOOGLE_OAUTH_BUNDLE_FILE: join(secrets, "drive/oauth.json"),
    });
    const rootFolder = await drive.metadata(config.parentFolderId);
    if (
      rootFolder.mimeType !== "application/vnd.google-apps.folder" ||
      rootFolder.trashed
    )
      throw new Error("Invalid release parent folder.");
    async function folder(parent: string, name: string) {
      const matches = (await drive.children(parent)).filter(
        (f) =>
          f.name === name &&
          f.mimeType === "application/vnd.google-apps.folder",
      );
      if (matches.length > 1) throw new Error(`Ambiguous folder: ${name}`);
      return matches[0]?.id ?? (await drive.folder(parent, name));
    }
    const releaseFolder = await folder(
      config.parentFolderId,
      config.folderName ?? "FireCheck app releases",
    );
    const archive = await folder(releaseFolder, "Archive");
    const name = `FireCheck-${info.version}-${info.code}-arm64-v8a.apk`;
    const archived = (await drive.children(archive)).filter(
      (f) => f.name === name,
    );
    if (archived.length > 1)
      throw new Error(
        "Duplicate archived release; inspect Drive before retrying.",
      );
    if (archived[0]?.md5Checksum && archived[0].md5Checksum !== md5)
      throw new Error("Archived release differs; increment the build number.");
    const versionedId = archived[0]?.id ?? (await drive.empty(archive, name));
    await uploadVerified(drive, versionedId, bytes);
    const latest = (await drive.children(releaseFolder)).filter(
      (f) => f.name === "FireCheck-latest-arm64-v8a.apk",
    );
    if (latest.length > 1)
      throw new Error("Multiple Latest APKs; inspect Drive before retrying.");
    let latestId = latest[0]?.id;
    if (latestId) {
      await uploadVerified(drive, latestId, bytes);
    } else {
      const copy = await drive.copy(versionedId, releaseFolder);
      latestId = copy.id;
      await drive.relocate(
        latestId,
        releaseFolder,
        "FireCheck-latest-arm64-v8a.apk",
      );
    }
    const verified = await drive.metadata(latestId);
    if (verified.md5Checksum !== md5 || Number(verified.size) !== bytes.length)
      throw new Error("Latest verification failed.");
    // Only the APK gets public reader access when explicitly configured.
    const credentials = JSON.parse(
      await readFile(join(secrets, "drive/oauth.json"), "utf8"),
    );
    const oauth = new OAuth2Client(
      credentials.GOOGLE_CLIENT_ID,
      credentials.GOOGLE_CLIENT_SECRET,
    );
    oauth.setCredentials({ refresh_token: credentials.GOOGLE_REFRESH_TOKEN });
    const token = await oauth.getAccessToken();
    async function api(path: string, init: RequestInit = {}) {
      const response = await fetch(
        `https://www.googleapis.com/drive/v3/files/${latestId}${path}`,
        {
          ...init,
          signal: AbortSignal.timeout(60000),
          headers: {
            Authorization: `Bearer ${token.token}`,
            "Content-Type": "application/json",
          },
        },
      );
      if (!response.ok)
        throw new Error(
          `Drive APK metadata/sharing failed (${response.status}).`,
        );
      return response.json();
    }
    if (config.anyoneWithLink === true) {
      const permissions = await api(
        "/permissions?fields=permissions(type,role)&supportsAllDrives=true",
      );
      if (
        !permissions.permissions.some(
          (p: any) => p.type === "anyone" && p.role === "reader",
        )
      ) {
        await api("/permissions?supportsAllDrives=true", {
          method: "POST",
          body: JSON.stringify({
            type: "anyone",
            role: "reader",
            allowFileDiscovery: false,
          }),
        });
      }
    }
    const metadata = await api(
      "?fields=id,name,webViewLink,webContentLink,md5Checksum,size,permissions(type,role)&supportsAllDrives=true",
    );
    if (
      config.anyoneWithLink &&
      !metadata.permissions?.some(
        (p: any) => p.type === "anyone" && p.role === "reader",
      )
    )
      throw new Error("Public download permission verification failed.");
    const updated = {
      ...config,
      webViewLink: metadata.webViewLink,
      webContentLink: metadata.webContentLink,
      releaseFolderId: releaseFolder,
      latestFileId: latestId,
      versionCode: info.code,
      version: info.version,
      md5,
    };
    await writeFile(configPath, JSON.stringify(updated, null, 2) + "\n", {
      mode: 0o600,
    });
    console.log(
      JSON.stringify({
        latestFileId: latestId,
        releaseFolderId: releaseFolder,
        version: info.version,
        verified: true,
        webViewLink: metadata.webViewLink,
        webContentLink: metadata.webContentLink,
      }),
    );
  } finally {
    await rmdir(lock);
  }
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
