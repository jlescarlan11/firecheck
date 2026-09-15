/** Administrator-only local OAuth setup. Never prints client secrets or tokens. */
import { readFile, mkdir, writeFile, rename, chmod } from "node:fs/promises";
import { join, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { OAuth2Client } from "google-auth-library";
import {
  createOwnerConsent,
  listenForConsent,
  verifyOwnerGrant,
} from "../src/oauth-connection.js";

async function main() {
  const source = process.env.GOOGLE_OAUTH_CLIENT_FILE;
  const owner = process.env.DRIVE_OWNER_EMAIL;
  if (!source || !owner)
    throw new Error(
      "Set GOOGLE_OAUTH_CLIENT_FILE to the downloaded Web OAuth client JSON and DRIVE_OWNER_EMAIL to the designated owner.",
    );
  const redirect = "http://127.0.0.1:8765/oauth/callback";
  const data = JSON.parse(await readFile(source, "utf8")) as {
    web?: {
      client_id: string;
      client_secret: string;
      redirect_uris?: string[];
    };
  };
  const web = data.web;
  if (
    !web?.client_id ||
    !web.client_secret ||
    !web.redirect_uris?.includes(redirect)
  )
    throw new Error(
      `Use a Web OAuth client with the exact authorized redirect URI ${redirect}.`,
    );
  const client = new OAuth2Client(web.client_id, web.client_secret, redirect);
  const consent = await createOwnerConsent(client, owner);
  const output = resolve(
    process.env.DRIVE_SECRET_DIRECTORY ?? ".secrets/drive",
  );
  const listener = await listenForConsent({
    port: 8765,
    state: consent.state,
    exchange: async (code) => {
      const { tokens } = await client.getToken({
        code,
        codeVerifier: consent.verifier,
      });
      if (!tokens.id_token) throw new Error("No owner identity returned.");
      const identity = await client.verifyIdToken({
        idToken: tokens.id_token,
        audience: web.client_id,
      });
      verifyOwnerGrant(identity.getPayload(), owner, tokens);
      await mkdir(output, { recursive: true, mode: 0o700 });
      await chmod(output, 0o700);
      // Atomic bundle replacement also supports central-account reconnection.
      const temporary = join(output, `${randomUUID()}.tmp`);
      await writeFile(
        temporary,
        JSON.stringify({
          GOOGLE_CLIENT_ID: web.client_id,
          GOOGLE_CLIENT_SECRET: web.client_secret,
          GOOGLE_REFRESH_TOKEN: tokens.refresh_token,
        }),
        { mode: 0o600, flag: "wx" },
      );
      await rename(temporary, join(output, "oauth.json"));
    },
  });
  console.log(
    "Open this Google authorization URL in your browser on this computer:",
  );
  console.log(consent.url);
  console.log(
    "Waiting for the designated owner. Credentials will not be printed.",
  );
  try {
    await listener.completed;
    console.log(
      "Owner verified. Saved restricted-permission .secrets/drive/oauth.json (or DRIVE_SECRET_DIRECTORY override). Upload this bundle to Secret Manager before deployment.",
    );
  } finally {
    listener.close();
  }
}
main().catch(() => {
  // OAuth library errors may embed the token request body. Do not print them.
  console.error(
    "Drive setup failed. Check the Web client file, exact redirect URI, owner email, consent and port 8765, then rerun. No credentials were printed.",
  );
  process.exitCode = 1;
});
