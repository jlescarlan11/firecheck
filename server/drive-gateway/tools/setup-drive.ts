/** Reuse the approved My Drive tree and create only a missing published folder. */
import { driveFromEnvironment, descendant } from "../src/drive.js";
import { mkdir, writeFile } from "node:fs/promises";
async function main() {
  const root = "1qRskwl5e1LdcrlseiVAzsmR57Y39bx2R";
  const input =
    process.env.DRIVE_INPUT_ROOT ?? "1PG7WAgzaViIosQdKrH9KWxTJApYfq-0q";
  const output =
    process.env.DRIVE_OUTPUT_ROOT ?? "1wsT0jAPQDQOlO08GtNSIf2XAXTDXFjIY";
  const drive = await driveFromEnvironment();
  await descendant(drive, input, root);
  await descendant(drive, output, root);
  const existing = (await drive.children(root)).filter(
    (f) => f.name === "published",
  );
  if (
    existing.length > 1 ||
    (existing[0] &&
      existing[0].mimeType !== "application/vnd.google-apps.folder")
  )
    throw new Error(
      "Ambiguous published folder. Resolve its exact ID before setup.",
    );
  const published = existing[0]?.id ?? (await drive.folder(root, "published"));
  await descendant(drive, published, root);
  const configuration = {
    DRIVE_AUTH_MODE: "oauth",
    DRIVE_INPUT_ROOT: input,
    DRIVE_OUTPUT_ROOT: output,
    DRIVE_PUBLISHED_ROOT: published,
  };
  await mkdir(".secrets", { recursive: true, mode: 0o700 });
  await writeFile(
    ".secrets/drive-folders.json",
    JSON.stringify(configuration, null, 2),
    { mode: 0o600 },
  );
  console.log(JSON.stringify(configuration, null, 2));
}
main().catch(() => {
  console.error(
    "Drive setup failed. Verify the central account's access and the approved folder tree. No credentials were printed.",
  );
  process.exitCode = 1;
});
