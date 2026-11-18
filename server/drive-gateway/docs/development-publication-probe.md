# Isolated development publication measurement

The runner is `tools/development-publication-probe.ts`. Running it without arguments prints the plan and performs no network, credential or database operations. Actual execution requires `--execute` and explicit environment configuration. This is a development measurement; it is not a deploy script or a durable publication worker.

The execution contract is append-only:

1. Refuse any database except the administrator database `postgres` on `127.0.0.1:55441`, and create a UUID-named `firecheck_devprobe_*` database there. Use a standalone gateway schema, synthetic supervisor identity, actual Fastify route and gateway role. This is not full-chain Supabase authorization or HTTP ingress validation.
2. Refuse unknown/insufficient quota; require at least 4 GiB available before remote creation. Create one UUID-marked sandbox directly under authenticated My Drive `root`, outside historical FireCheck roots. Persist its stable ID immediately in an exclusive, restricted local manifest. Require `ownedByMe` and exactly one user/owner permission, on the sandbox and input/output/published children, before payload upload. Read all permission pages; never change sharing.
3. Create 100 opaque files with complete names for 25 four-component shapefile groups. Allocate IDs first, then sort identically to source publication so the first copy is exactly 64 bytes. The total is exactly 1,073,741,824 bytes; every file is below 512 MiB. Pattern bytes are not GIS-valid geometry/attributes and do not test the mobile 128 MiB import bound. Upload in 8 MiB chunks; checksum and size-check every source file. Record upload time separately.
4. Publish once through the real source route. Record individual Drive method timings, whole route time, version and manifest/file bindings. Re-read all copied metadata and verify all 100 MD5/size pairs.
5. Inject an adapter error before the second actual copy in another publication. Retain exactly one 64-byte partial copy, verify no additional committed version/current-pointer change, and download the previous version's first artifact through the authorized route. Retain the failed folder and reason.
6. Retry with a fresh publication intent/UUID; verify the complete current manifest, every MD5/size, and the previous version. This is not same-UUID publication idempotency. Expected retained payload is at most 3,221,225,536 bytes (three GiB plus 64 bytes), below four GiB. No remote delete, trash, move, sharing change or cleanup API exists in this runner.
7. Persist all evidence before dropping only the successful run's unique local database. On failure, retain any created local database and remote objects; capture the source/current/version database state when available. Report stable sandbox/folder IDs and manifest path for later review. Do not automatically resume a failed probe into old artifacts; another execution creates another sandbox and consumes additional quota.

The runner uses its own transaction wrapper with a synchronous, nonthrowing error listener on checked-out PostgreSQL clients. An idle transaction termination is recorded with its original SQLSTATE; later termination events do not replace it. The Drive boundary checks that state before/after calls: one already accepted call may settle, but no subsequent call begins after the abort is observed. The wrapper retains client ownership until the callback settles, then discards a terminated connection. The outer failure manifest records the database error and re-reads source/version state through an independent connection. Production `Database` behavior and operating timeouts are unchanged.

A probe-only 150-second safety guard checks before/after Drive calls during each publication. It throws through the real transaction on exceeding that guard and captures the boundary. This is not an application handler deadline and does not cancel a Drive copy already accepted remotely. The adapter's 60-second per-request timeout and database's 120-second idle-in-transaction limit remain separate. A first-publication failure stops the later success/failure/retry sequence and is evidence of a measured boundary, not a pass.

From `server/drive-gateway`, after review of this runner and plan:

```sh
npx tsx tools/development-publication-probe.ts
```

For the authorized isolated development run, configure these local environment variables without exposing OAuth contents:

```sh
DEV_PROBE_DATABASE_URL='postgresql://postgres:local-sync-test@127.0.0.1:55441/postgres' \
GOOGLE_OAUTH_BUNDLE_FILE="$PWD/.secrets/drive/oauth.json" \
DEV_PROBE_MANIFEST="$PWD/.secrets/task6-development-publication-$(date +%Y%m%dT%H%M%S).json" \
npx tsx tools/development-publication-probe.ts --execute
```

The password above is the synthetic disposable local-container password. The OAuth bundle stays server-only. The manifest records no tokens, credentials or resumable URLs. It records local runtime/database versions, stable IDs, hashes, sizes, permission outcomes and timings. No existing shared root/configuration, production database, linked Supabase project or deployed runtime is touched. The report-only orphan inventory is not executed by the probe.

An actual successful run measures Google Drive copy latency with local PostgreSQL and Node application execution. It cannot establish Supabase Edge/Cloud Run wall-clock/CPU/memory behavior, actual ingress deadlines, representative GIS/mobile import behavior, or a durable publisher's reliability. Those checks require separate evidence.
