import { createServer } from "node:http";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { OAuth2Client, CodeChallengeMethod } from "google-auth-library";

export const DRIVE_SCOPE = "https://www.googleapis.com/auth/drive";

/** Loopback-only, single-use callback. No tokens or provider errors in responses. */
export async function listenForConsent(options: {
  port: number;
  state: string;
  exchange: (code: string) => Promise<void>;
  timeoutMs?: number;
}) {
  let busy = false;
  let finish!: () => void;
  let fail!: (error: Error) => void;
  const completed = new Promise<void>((resolve, reject) => {
    finish = resolve;
    fail = reject;
  });
  // A timeout can happen while the caller is still preparing the authorization URL.
  void completed.catch(() => {});
  const server = createServer(async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    res.setHeader(
      "Content-Security-Policy",
      "default-src 'none'; frame-ancestors 'none'",
    );
    const url = new URL(req.url ?? "/", `http://127.0.0.1:${options.port}`);
    const supplied = Buffer.from(url.searchParams.get("state") ?? "");
    const expected = Buffer.from(options.state);
    if (
      req.method !== "GET" ||
      req.headers.host !== `127.0.0.1:${options.port}` ||
      url.pathname !== "/oauth/callback" ||
      url.searchParams.getAll("state").length !== 1 ||
      supplied.length !== expected.length ||
      !timingSafeEqual(supplied, expected)
    ) {
      res.writeHead(400).end("Invalid connection request.");
      return;
    }
    if (busy) {
      res.writeHead(409).end("This connection request has already been used.");
      return;
    }
    busy = true;
    try {
      const code = url.searchParams.get("code");
      if (
        url.searchParams.has("error") ||
        !code ||
        url.searchParams.getAll("code").length !== 1
      )
        throw new Error("Consent was not completed.");
      await options.exchange(code);
      res.end("FireCheck Drive connection saved. You can close this tab.");
      finish();
    } catch {
      res
        .writeHead(400)
        .end(
          "Connection failed. Check the selected owner account and restart the setup command.",
        );
      fail(
        new Error(
          "Drive connection failed; no credentials were displayed. Check the owner, consent scopes and OAuth client configuration.",
        ),
      );
    } finally {
      clearTimeout(timer);
      server.close();
    }
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(options.port, "127.0.0.1", resolve);
  });
  const timer = setTimeout(
    () => {
      busy = true;
      server.close();
      fail(
        new Error("Google connection timed out. Restart the setup command."),
      );
    },
    options.timeoutMs ?? 10 * 60 * 1000,
  );
  return {
    completed,
    close: () => {
      clearTimeout(timer);
      server.close();
    },
  };
}

export async function createOwnerConsent(
  client: OAuth2Client,
  expectedEmail: string,
) {
  const state = randomBytes(32).toString("base64url");
  const proof = await client.generateCodeVerifierAsync();
  const url = client.generateAuthUrl({
    access_type: "offline",
    prompt: "consent",
    scope: ["openid", "email", DRIVE_SCOPE],
    state,
    login_hint: expectedEmail,
    code_challenge: proof.codeChallenge,
    code_challenge_method: CodeChallengeMethod.S256,
  });
  return { state, verifier: proof.codeVerifier, url };
}

export function verifyOwnerGrant(
  identity: { email?: string; email_verified?: boolean } | undefined,
  expectedEmail: string,
  tokens: { refresh_token?: string | null; scope?: string },
) {
  if (
    !identity?.email_verified ||
    identity.email?.toLowerCase() !== expectedEmail.toLowerCase()
  )
    throw new Error("The selected account is not the configured folder owner.");
  if (!tokens.refresh_token || !tokens.scope?.split(" ").includes(DRIVE_SCOPE))
    throw new Error("Offline Drive access was not granted.");
}
