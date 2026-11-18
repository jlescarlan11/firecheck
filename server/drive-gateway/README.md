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

The deploy helper reads `.secrets/drive/oauth.json`, `.secrets/drive-folders.json`, `.secrets/database.env`, `.secrets/supabase-ca.crt`, and `.secrets/export-worker.env`. The last file must contain a strong random `EXPORT_WORKER_TOKEN` matching the scheduler's Vault secret; retain it across deployments. Keep these files private and outside version control. The helper installs secrets and deploys only `drive-gateway`, then checks public health and rejects an unauthenticated assignment request. Worker activation remains a separate deliberate cutover.

Obtain the database CA through **Database → Settings → Download certificate** in the project dashboard. The current download is [Supabase production CA](https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt). Pass its base64-encoded PEM through `FIRECHECK_DB_CA_BASE64`. For local Node checks, remove connection-string SSL overrides before specifying `ssl: { ca, rejectUnauthorized: true }`.

### Registering new map assignments

A supervisor may run `npm run admin -- create assignment.json`. The file contains a fresh `id`, `name`, `campaignId` and WGS84 GeoJSON `boundary` of type `Polygon`. The server validates coordinates and PostGIS geometry validity, creates the assignment and enrolls its creator as owner. Register its Drive source with `source`, publish it, then explicitly enroll fieldworkers. The separate migration `20260915165116_gateway_supervisor_assignment_creation.sql` grants only the gateway role this insert permission.

The existing schema uses a non-null campaign UUID without a campaigns table: `campaignId` is an externally supplied grouping identity, not an enrollment credential or server-created campaign record. A supervisor supplies the same approved UUID for related assignments. Creation enrolls only its creator as owner; fieldworkers require explicit supervisor enrollment by user UUID. Assignment membership, display names and editable profile metadata never grant supervisor rights. Do not invent a geographic boundary; derive it from the approved map or a supervisor-provided boundary.

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

- Mobile import still uses the existing in-memory shapefile interface: map bundles are capped at 128 MiB. Files stream to resumable temp files first. Mobile consumer limits are separate from server map-publication/upload validation (512 MiB per file, 1 GiB total, 100 files).
- Legacy shapefile uploads use the organized map/surveyor/Archive layout described below. Names are display labels; private managed keys bind map folders to assignment UUIDs, and receipt links bind to stable folder IDs. Shared-map generated exports have a separate layout and worker contract below.
- Source publication and upload batch setup are synchronous. No durable source publisher is implemented. Metadata validation permits 100 files, 512 MiB per file and 1 GiB total; these are validation bounds, not verified synchronous capacity. Representative maximum input tests on the selected hosted runtime remain pending. See the distinct runtime boundaries below.
- A failed publication/setup transaction can leave a newly created folder in Drive. The database current pointer and version record commit only after verified source copies; a failed attempt leaves the last good version advertised. Retrying source publication creates a fresh version UUID; this is distinct from idempotent upload batch/completion receipts. Drive itself is not transactional. Report-only inventory below never authorizes deletion; retention and grace periods require an explicit operator decision.
- Files are stored in the configured Drive account, not a second object store. If Drive or the API is unavailable, new online transfers wait; existing downloaded maps remain offline.
- Remote revocation cannot erase files from an offline phone. Membership is checked on every online file/chunk/completion request; an accepted upload can finish after assignment closure, but only while its owner retains membership.
- The server validates app sessions through Supabase's authenticated `/auth/v1/user` endpoint. Do not claim immediate invalidation of every previously issued access JWT solely from sign-out; expiry and Supabase policy still apply.

## Organized survey outputs

Uploads are grouped as `firecheck/output/<map>/<surveyor (short ID)>/`.
Each surveyor has one latest **completed** batch per map. Incomplete transfers
and older batches stay under that map's `Archive/` folder, named by surveyor,
date, and short batch ID. Completing an older transfer cannot replace a newer
completed batch. Map folders use a private Drive property tied to the assignment
ID and are reused under an assignment lock.

This layout keeps collaborators' exports separate; it does not merge their
shapefile records. Folder and file IDs are preserved when archiving, so receipt
links continue to work. Existing `public.drive_uploads` audit paths describe
the location at the time of upload; the gateway receipt returns the current path.

To preview organizing existing gateway-owned uploads, run
`npx tsx tools/organize-output.ts`. Add `--apply` to move them. Add `--archive-legacy` to preserve old email-named output folders under a top-level `Archive` as well. The tool saves a
restricted rollback manifest in `.secrets/` first and does not delete or rewrite
survey files. Deploy the gateway change before applying the cleanup so subsequent
uploads use the same layout.


## Publication runtime boundaries

These boundaries measure different things; none establishes a supported publication throughput ceiling:

| Boundary | Current contract |
| --- | --- |
| Each Google Drive HTTP call | 60-second adapter timeout; a publication makes many sequential calls. |
| Fastify `requestTimeout` | 90 seconds to receive a request, not a handler execution deadline. See [Fastify requestTimeout](https://fastify.dev/docs/latest/Reference/Server/#requesttimeout). |
| PostgreSQL transaction | 3-second lock timeout; 120-second idle-in-transaction timeout. A long sequence of Drive calls between SQL statements can hit the latter. |
| Selected Supabase Free runtime | 150-second worker wall-clock duration; 2 seconds CPU per request excluding asynchronous I/O; 256 MiB memory; 150-second request idle timeout. Paid worker duration is 400 seconds. See [official Edge limits](https://supabase.com/docs/guides/functions/limits), checked November 18, 2026. |
| Optional Cloud Run configuration | This repo recommends 300 seconds initially. The service defaults to 300 seconds and allows up to 3,600; a timed-out connection does not necessarily stop container work. See [Cloud Run request timeout](https://docs.cloud.google.com/run/docs/configuring/request-timeout). |

A source publication freezes its supported-file listing, copies into a fresh folder, rechecks the source listing and each copy's MD5/size, then commits the immutable version and current pointer together. Existing versions remain referenced and readable subject to membership. New folders have `firecheckOutputKey=source-publication:<assignment UUID>:<version UUID>`; creating a fresh folder does not list the historical published root. Source listing still fails explicitly above 1,000 children instead of truncating.

Local fake-Drive tests establish rollback, checksum failure and fresh retry logic. They do not measure Google latency or hosted maximum capacity. The append-only [development probe contract](docs/development-publication-probe.md) measures actual Google copies with local PostgreSQL when separately executed; its opaque maximum-size payload is not valid representative GIS data. Hosted Edge/Cloud Run maximum-input capacity and valid mobile import remain separate pending checks. No deployment is part of local `prepare:edge`.

## Report-only publication inventory

`npx tsx tools/inventory-publications.ts` reads explicit `DATABASE_URL`, `DRIVE_INPUT_ROOT`, `DRIVE_OUTPUT_ROOT`, `DRIVE_PUBLISHED_ROOT` and the usual server Drive credential environment. Use a trusted administrator environment and verified TLS database configuration. It inspects only immediate folders under the configured published root. There is no apply/delete/trash/move mode; mutation flags are rejected. This command has not been executed against remote Drive in the cleanup session.

Every retained version, registered source/upload (including incomplete resumable uploads), known export, configured root and referenced file's actual parent ancestry is protected. Historical folders without a valid new publication marker remain protected as unknown, regardless of name. The helper reads internally consistent database snapshots before/after inspection, including active export jobs; changed references produce `inconclusive` with no candidate entries. Listing overflow, unresolved metadata or an inspection error also produces `inconclusive` without a partial list.

A marked folder absent from committed references is only `review-only` / `possibly-in-flight-publication`, and the overall report remains inconclusive: an uncommitted publisher may still own it. Stable folder IDs and exclusion reasons support operator review. The tool does not infer creation dates, grace periods, historical provenance or permission to delete. Unknown folders, archives and all old versions stay protected.

## Shared-map generated outputs

Shared maps use the existing leased `firecheck_sync.export_jobs` worker rather than the synchronous source-publication route. A managed map folder contains `Current.geojson`; verified revision artifacts (`shared-map.json` and `map.geojson`) are retained under that map's `Archive/r<revision>/` managed folders. Export and source-version manifests retain their file/folder identities. Legacy uploads moved into Archive retain their IDs and receipt URLs. This is separate from each surveyor's latest completed legacy shapefile batch.

`tools/organize-output.ts` already uses the organized layout and registered upload IDs. Its preview is read-only; its existing `--apply` / `--archive-legacy` moves are a separate operator action with a local rollback manifest. Publication inventory never invokes it. No consumer script was changed to expect the stale flat UUID path.
