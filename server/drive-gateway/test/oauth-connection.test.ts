import test from "node:test";
import assert from "node:assert/strict";
import { OAuth2Client } from "google-auth-library";
import { createHash } from "node:crypto";
import {
  createOwnerConsent,
  listenForConsent,
  verifyOwnerGrant,
  DRIVE_SCOPE,
} from "../src/oauth-connection.js";

test("owner consent requests offline Drive access with state and PKCE", async () => {
  const client = new OAuth2Client(
    "test-client",
    "test-secret",
    "http://127.0.0.1:8765/oauth/callback",
  );
  const flow = await createOwnerConsent(client, "owner@example.com");
  const params = new URL(flow.url).searchParams;
  assert.equal(params.get("access_type"), "offline");
  assert.equal(params.get("state"), flow.state);
  assert.equal(params.get("code_challenge_method"), "S256");
  assert.equal(
    params.get("code_challenge"),
    createHash("sha256").update(flow.verifier).digest("base64url"),
  );
  assert.equal(params.get("login_hint"), "owner@example.com");
  assert.ok(!flow.url.includes("test-secret"));
});

test("owner verification rejects a different account, unverified email and incomplete consent", () => {
  const identity = { email: "owner@example.com", email_verified: true };
  const tokens = {
    refresh_token: "private",
    scope: `openid email ${DRIVE_SCOPE}`,
  };
  assert.doesNotThrow(() =>
    verifyOwnerGrant(identity, "OWNER@example.com", tokens),
  );
  assert.throws(() => verifyOwnerGrant(identity, "worker@example.com", tokens));
  assert.throws(() =>
    verifyOwnerGrant(
      { ...identity, email_verified: false },
      identity.email,
      tokens,
    ),
  );
  assert.throws(() =>
    verifyOwnerGrant(identity, identity.email, {
      ...tokens,
      refresh_token: undefined,
    }),
  );
  assert.throws(() =>
    verifyOwnerGrant(identity, identity.email, {
      ...tokens,
      scope: "openid email",
    }),
  );
});

test("callback rejects forged state without consuming consent and handles only one exchange", async () => {
  let calls = 0;
  let complete!: () => void;
  const exchangeWait = new Promise<void>((resolve) => {
    complete = resolve;
  });
  const listener = await listenForConsent({
    port: 18765,
    state: "valid-state",
    exchange: async (code) => {
      assert.equal(code, "code");
      calls++;
      await exchangeWait;
    },
  });
  try {
    const bad = await fetch(
      "http://127.0.0.1:18765/oauth/callback?state=forged&code=code",
    );
    assert.equal(bad.status, 400);
    assert.equal(calls, 0);
    const first = fetch(
      "http://127.0.0.1:18765/oauth/callback?state=valid-state&code=code",
    );
    // Await entry to the real callback before attempting a replay.
    while (!calls) await new Promise((resolve) => setTimeout(resolve, 5));
    const replay = await fetch(
      "http://127.0.0.1:18765/oauth/callback?state=valid-state&code=code",
    );
    assert.equal(replay.status, 409);
    complete();
    const response = await first;
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    await listener.completed;
    assert.equal(calls, 1);
  } finally {
    complete();
    listener.close();
  }
});

test("provider errors containing secrets are never sent to the browser", async () => {
  const listener = await listenForConsent({
    port: 18766,
    state: "valid",
    exchange: async () => {
      throw new Error("refresh_token=secret-canary");
    },
  });
  try {
    const response = await fetch(
      "http://127.0.0.1:18766/oauth/callback?state=valid&code=code",
    );
    assert.equal(response.status, 400);
    assert.ok(!(await response.text()).includes("secret-canary"));
    await assert.rejects(
      listener.completed,
      (error: Error) => !error.message.includes("secret-canary"),
    );
  } finally {
    listener.close();
  }
});

test("abandoned consent expires", async () => {
  const listener = await listenForConsent({
    port: 18767,
    state: "valid",
    exchange: async () => {},
    timeoutMs: 20,
  });
  await assert.rejects(listener.completed, /timed out/);
  listener.close();
});
