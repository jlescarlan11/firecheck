# FireCheck Drive gateway

A file API with PostgreSQL transfer state and a Google Drive adapter, hosted on the existing Supabase Free project using Edge Functions. A Node container is also available for a future hosting change. The Flutter client uses its Supabase session; Drive OAuth access tokens and resumable URLs never leave the server.

## Current implementation

- Supervisor CLI: register a source folder, publish a copied map version, enroll/remove workers.
- Worker API: paginated assignment list, immutable manifest IDs, streamed/range downloads and upstream checksum/size checks.
- Uploads: account-bound UUID batches, declared file manifest, 8 MiB chunks, persisted resumable sessions, serialized per-batch database transactions, remote completion reconciliation and idempotent audit receipts.
- The existing app still stores photos in Supabase Storage. This integration moves Drive map files and shapefile exports; it does not duplicate those photos into Drive.
- Mobile schema v17 adds owner/batch IDs without assigning an owner to legacy queued files. Those older exports require re-export. Different-user queues are not drained by the active account.
- `FIRECHECK_GATEWAY_URL` enables gateway mode for foreground downloads, foreground exports and background exports. In gateway mode, login omits Drive consent. No fallback to direct Drive occurs on gateway errors. An unset URL retains the existing direct-Drive build while rollout is incomplete.

## Observed Drive configuration

The folder supplied on September 15, 2026 is a shared **My Drive folder**, not a Workspace Shared Drive: it has a human owner and `drive_id` is null.

- FireCheck root: `1qRskwl5e1LdcrlseiVAzsmR57Y39bx2R`
- Input: `1PG7WAgzaViIosQdKrH9KWxTJApYfq-0q`
- Output: `1wsT0jAPQDQOlO08GtNSIf2XAXTDXFjIY`
- Published root: not created yet. Create a separate `published` folder under the approved FireCheck root using the intended server connection.

The owner's current folder metadata allows anyone with the link to edit. No sharing settings were changed. Gateway authorization does not protect files accessed directly through that existing link; review this before production.

Confirmed September 16: keep this My Drive folder with central owner OAuth. No organization is required. OAuth is the default mode. Do not configure service-account upload mode against this folder.

## Local build and tests

Use Node 24 or later:

```sh
npm ci
npm run check
npm run build
```

Integration tests need a disposable local PostgreSQL server. They create and drop a uniquely named test database and create non-login test roles when missing. They refuse a non-local database URL. Never point tests at a user/work database.

```sh
docker run --detach --name firecheck-gateway-test -e POSTGRES_PASSWORD=local-gateway-test -p 127.0.0.1:55439:5432 postgres:17
docker exec firecheck-gateway-test pg_isready -U postgres
npm test
```

Wait for PostgreSQL readiness before running tests. `TEST_DATABASE_URL` overrides the local administrative connection; it must have permission to create the disposable database and roles. The app integration tests use a deterministic fake Drive adapter but real PostgreSQL transactions/RLS. They do not prove a Google account or hosted deployment is configured.

## Database setup

Apply `supabase/migrations/20260915151740_drive_gateway.sql` through the project's migration process. It creates a private schema and an initially disabled gateway. It does not revoke legacy mobile behavior until activation.

Create a dedicated database login, store its password in Supabase Edge Function secrets, and grant it the non-login `firecheck_gateway_server` role. Use that login's TLS connection string for `DATABASE_URL`. Do not run the production API using the postgres owner or expose database credentials to the APK. For example, a DBA can provision a login with a generated password and grant membership:

```sql
GRANT firecheck_gateway_server TO your_gateway_login;
```

Seed the initial supervisor UUID into `firecheck_gateway.supervisors` through an administrator connection after verifying the actual user. This is not derived from editable Google/Supabase profile metadata.

Before activation, a supervisor must review existing assignment memberships: the legacy self-claim RPC did not establish a trustworthy access roster. Then run `sql/activate.sql` using the migration/admin process. It revokes the name-based self-claim/lookup APIs, removes client-authored Drive completion audit inserts, and enables worker gateway routes. Old mobile builds relying on self-claim or audit insert must be upgraded at that cutover.

Gateway worker requests also verify that the legacy self-claim RPC has not been reopened. Supervisor setup endpoints are available before worker activation.

## Server Google credentials

### Actual Workspace Shared Drive

1. Create a runtime service account and a distinct Drive service account in the chosen Google Cloud project.
2. Enable Drive and IAM Credentials APIs.
3. Grant runtime account Token Creator **on the Drive account only**.
4. Give the Drive account appropriate input read/output write/published write permissions in the approved Shared Drive, subject to Workspace sharing policy.
5. Attach the runtime account to Cloud Run. Set `DRIVE_AUTH_MODE=service_account`, `DRIVE_SERVICE_ACCOUNT`, and the actual `SHARED_DRIVE_ID`.

The Google auth library uses runtime ADC plus explicit Drive-scoped impersonation tokens. No service-account JSON key belongs in the repo or app. IAM access alone does not grant Drive file permissions.

### Keep the current My Drive folder

Use a server Web OAuth client and the designated account's offline grant. Set `DRIVE_AUTH_MODE=oauth` and inject `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and `GOOGLE_REFRESH_TOKEN` through the server secret store (Supabase Edge Function secrets in the selected deployment). Obtain the grant through a trusted administrator OAuth flow, with exact redirect URI and state verification. Do not reuse a fieldworker's token or request a refresh token through chat.

The owner must authorize the server's Drive scope; validate Google OAuth publishing/verification requirements. A revoked central refresh token is an administrator service issue, not a fieldworker login prompt. The administrator setup command implements the local owner connection:

1. Create a dedicated **Web application** OAuth client in `firecheck-495005`. Add exactly `http://127.0.0.1:8765/oauth/callback` as an authorized redirect URI. Download its JSON outside version control. The existing Android client JSON is not a Web client and cannot be reused.
2. Set `GOOGLE_OAUTH_CLIENT_FILE` to that file and `DRIVE_OWNER_EMAIL` to the designated owner (currently `jnescarlan@up.edu.ph`). Run `npm run connect-drive` and open the printed Google URL on the same computer.
3. The helper verifies a single-use state, PKCE, the Google-signed owner identity, full Drive scope and an offline refresh token. It writes only `.secrets/drive/oauth.json` with owner-only permissions. It never prints secrets. `.secrets` is excluded from Git and container build contexts.
4. Set `GOOGLE_OAUTH_BUNDLE_FILE` to the absolute path of that local bundle. Run `npm run setup-drive` to verify the input/output ancestry and create or reuse the `published` folder. Save the returned nonsecret folder IDs.
5. Run `npm run probe-drive`. For the selected Supabase deployment, `npm run deploy:edge` installs the bundle as the server-only `FIRECHECK_DRIVE_OAUTH` secret. The CLI passes a restricted-permission environment file, never secret values as command arguments.
6. For reconnection, rerun the same helper and deploy the updated server-only Supabase secret. Existing fieldworker sessions and offline maps remain usable.

For production, do not leave an external OAuth consent app in **Testing**: Drive refresh tokens issued in Testing expire after seven days. Review the project's audience/publishing status and applicable Google verification requirements before issuing the production grant. See [Google OAuth token expiration](https://developers.google.com/identity/protocols/oauth2#expiration).

The helper is a local administrator tool, not a publicly hosted OAuth callback. Never expose port 8765 to the network.

## Drive integration probe

With the intended credentials and folder IDs injected into a trusted environment, run:

```sh
npx tsx tools/drive-probe.ts
```

The probe reads the input listing, creates a uniquely named test folder in output, uploads a small binary in two resumable chunks, checks its MD5 and performs a ranged read. It leaves only its own probe folder for review/removal; it does not touch existing survey files. The output contains IDs, never tokens. Passing this is required before activating the new phone build.

## Selected deployment: Supabase Free

The user chose to stay on free hosting on September 16. Use project `xmigquvscisdqtrepdwv` in Singapore. No Google Cloud billing account is needed for this deployment; Google Cloud still hosts the OAuth client and Drive API configuration.

- Entry point: `supabase/functions/drive-gateway/index.ts`. The generated modules share the exact authorization/transfer code used by the Node server; run `npm run prepare:edge` after changing it.
- `verify_jwt=false` disables the legacy relay verifier only. Every non-health API route verifies the caller using Supabase `/auth/v1/user`, then checks the protected supervisor/assignment tables. Invalid or missing sessions return 401.
- Store `FIRECHECK_DRIVE_OAUTH`, `FIRECHECK_DATABASE_URL`, `FIRECHECK_DB_CA_BASE64` and folder IDs as function secrets. The database login has the gateway role only. Its certificate and hostname are verified; do not use `rejectUnauthorized:false`.
- The endpoint is `https://xmigquvscisdqtrepdwv.supabase.co/functions/v1/drive-gateway`. Mobile and supervisor clients preserve that complete prefix.
- Downloads use 4 MiB ranges; uploads use at most 8 MiB chunks. Both can resume after an interrupted function invocation.
- Supabase Free functions have a 150-second worker duration, 2 seconds CPU per request and 256 MiB memory. These are finite free quotas, not unlimited free hosting. Keep publication batches small and measure representative maps before rollout. Existing photos and other project traffic share the project's quotas. See [runtime limits](https://supabase.com/docs/guides/functions/limits) and [function billing](https://supabase.com/docs/guides/functions/pricing).
- A live function test and real Drive transfer probe are required. Plain Node/Deno tests do not establish hosted runtime compatibility.

### Deployment commands

From this directory, after owner consent and folder setup:

```sh
npm run prepare:edge
npm run deploy:edge
```

The deploy helper reads `.secrets/drive/oauth.json`, `.secrets/drive-folders.json`, `.secrets/database.env` and `.secrets/supabase-ca.crt`. It installs secrets and deploys only `drive-gateway`, then checks public health and rejects an unauthenticated assignment request. Worker activation remains a separate deliberate cutover.

Obtain the database CA through **Database → Settings → Download certificate** in the project dashboard. The current download is [Supabase production CA](https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt). Pass its base64-encoded PEM through `FIRECHECK_DB_CA_BASE64`. For local Node checks, remove connection-string SSL overrides before specifying `ssl: { ca, rejectUnauthorized: true }`.

### Registering new map assignments

A supervisor may run `npm run admin -- create assignment.json`. The file contains a fresh `id`, `name`, `campaignId` and WGS84 GeoJSON `boundary` of type `Polygon`. The server validates coordinates and PostGIS geometry validity, creates the assignment and enrolls its creator as owner. Register its Drive source with `source`, publish it, then explicitly enroll fieldworkers. The separate migration `20260915165116_gateway_supervisor_assignment_creation.sql` grants only the gateway role this insert permission.

The existing schema uses a non-null campaign UUID without a campaigns table. Reuse your campaign UUID for related assignments; do not invent a geographic boundary. Derive it from the approved map or a supervisor-provided boundary.

## Optional Cloud Run deployment (not selected)

Build the `Dockerfile` from this directory and deploy the resulting container to the chosen project/region. Provision only after the account, billing/project and credential mode are confirmed.

- Runtime: Node 24 container, non-root process, `PORT` supplied by Cloud Run.
- Start with 512 MiB memory, concurrency 8, max instances 3 and a 300-second request timeout; measure before increasing. These are initial operating limits, not a capacity guarantee.
- Public HTTPS ingress is required for Supabase-session clients; application authentication still protects every API endpoint except `/healthz`.
- Inject `DATABASE_URL` and any OAuth secrets using Secret Manager references.
- Configure `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `DRIVE_INPUT_ROOT`, `DRIVE_OUTPUT_ROOT`, `DRIVE_PUBLISHED_ROOT`, and the chosen Google credential mode.
- Per-instance source-IP request limiting before authentication is enabled; shared cross-instance rate limiting or an external gateway is needed for stricter aggregate quotas. Do not log request bodies or Google error objects.
- `/healthz` is a liveness endpoint. The authenticated supervisor `/v1/admin/health` checks configured folder readability; run the write probe separately.
- On shutdown, the service closes HTTP and database connections. Transfer state persists in Postgres and Drive; no in-memory session or local container file is authoritative.

## Supervisor CLI

Read a supervisor's FireCheck access token from a trusted local environment. Never place it in shell command arguments, source files, screenshots, or chat.

```sh
npm run admin -- health
npm run admin -- source ASSIGNMENT_UUID DRIVE_INPUT_SUBFOLDER_ID
npm run admin -- publish ASSIGNMENT_UUID
npm run admin -- enroll ASSIGNMENT_UUID WORKER_UUID
npm run admin -- remove ASSIGNMENT_UUID WORKER_UUID
```

The CLI reads `FIRECHECK_GATEWAY_URL` and `FIRECHECK_ACCESS_TOKEN`. Register folders by exact ID; there is no global name search. Publishing copies supported components/sidecars into a version folder, validates complete shapefile component sets and snapshot checksums, and switches the version pointer only after all copies pass checks. Full shapefile geometry/attribute validation remains in the existing mobile importer.

## Mobile cutover

1. Pass the real Drive probe and supervisor publication/enrollment checks.
2. Review the membership roster and apply activation SQL.
3. Set the non-secret HTTPS `FIRECHECK_GATEWAY_URL` in the mobile build's environment.
4. Build a signed Android update with the existing release key, preserving local maps and surveys.
5. On device, test login, Get Maps, force-stop/restart, token expiry, interrupted download/upload, background upload, account switch and duplicate completion.
6. Verify exported files and the server-authored `drive_uploads` receipt in the supervisor's Drive/Supabase views.

Setting an environment variable locally does not update a phone already running an APK. The gateway is deployed to `xmigquvscisdqtrepdwv`; a phone still needs the gateway-enabled APK.

## Known operating limits

- Mobile import still uses the existing in-memory shapefile interface: map bundles are capped at 128 MiB. Files stream to resumable temp files first; chunk-level UI updates are a follow-up (current progress updates per verified component). Server uploads cap individual files at 512 MiB and batches at 1 GiB/100 files.
- Export destination is `firecheck/output/<user-uuid>_<assignment-uuid>_<batch-uuid>/`. This avoids mutable email/folder-name collisions. Update supervisor scripts expecting the previous nested output layout.
- Publication and batch setup are synchronous; very large file counts/copies need a durable background publisher. Test representative maximum inputs against the 300-second request budget before rollout.
- A failed publication/setup transaction can leave an unreferenced newly created folder in Drive. It is never advertised as a completed map/upload. Automatic orphan cleanup and old-version retention are not included; use the unique folder IDs and server metadata for a reviewed cleanup process.
- Files are stored in the configured Drive account, not a second object store. If Drive or the API is unavailable, new online transfers wait; existing downloaded maps remain offline.
- Remote revocation cannot erase files from an offline phone. Membership is checked on every online file/chunk/completion request; an accepted upload can finish after assignment closure, but only while its owner retains membership.
- The server validates app sessions through Supabase's authenticated `/auth/v1/user` endpoint. Do not claim immediate invalidation of every previously issued access JWT solely from sign-out; expiry and Supabase policy still apply.
