# FireCheck Drive gateway deployment

## Live configuration

- Supabase Free project: `xmigquvscisdqtrepdwv`.
- Endpoint: `https://xmigquvscisdqtrepdwv.supabase.co/functions/v1/drive-gateway`.
- Google Cloud project: `firecheck-495005`; no billing account was added.
- Central Drive owner: `jnescarlan@up.edu.ph`.
- Google OAuth audience: External, In production (verified in Google Cloud).
- Drive storage is a shared folder in the owner's My Drive, not a Workspace Shared Drive.
- Input: `1PG7WAgzaViIosQdKrH9KWxTJApYfq-0q`.
- Output: `1wsT0jAPQDQOlO08GtNSIf2XAXTDXFjIY`.
- Published versions: `1_0U7aERi3xPFanQ_0XrR3Aq-gk_p52JU`.

Gateway migrations are installed, and the gateway is activated. Legacy client assignment-claim/resolve RPC execution and direct upload-audit inserts were disabled. Private gateway tables are inaccessible to mobile API roles. The server uses a dedicated database login with TLS certificate validation. Owner credentials are stored in server secrets, not the APK.

## Published maps

| Map | Assignment ID | Boundary source |
| --- | --- | --- |
| cebu | `5e19adbf-f65a-4963-89ba-e63b321ec939` | boundary.shp |
| guadalupe-sitio-3 | `b249b7c6-f089-4a34-8e66-af6f0a86356d` | Building_3.shp extent, matching the mobile importer's fallback |

Both source projections are WGS84 UTM zone 51N; assignment boundaries were transformed to WGS84 longitude/latitude. Only the owner is enrolled. Additional fieldworker access is awaiting the user's choice; it was not made public to all signed-in accounts.

## Verification

- Deployed health endpoint: 200; missing authentication: 401.
- Authenticated deployed supervisor request reached PostgreSQL and Drive.
- Unenrolled account map access and nonsupervisor admin access: 403.
- All 13 published Cebu components downloaded through the hosted gateway with matching size and MD5.
- Hosted upload created a file, accepted a 256 KiB chunk, reported its resume offset, accepted the final chunk, completed, and accepted an idempotent completion retry.
- Removing membership immediately denied map access.
- Temporary test account was signed out and deleted; test export folders were moved to Drive trash.
- Targeted Flutter login, gateway and migration suite: 25 passed before the final request-header fix; all 12 gateway tests passed afterward, including the new bodyless-completion regression test.
- Existing server suite: 16 passed during implementation; final TypeScript build passed.

Live testing found and fixed an Edge Runtime dependency on the global Buffer object (now explicitly imported), and empty POST requests incorrectly declaring JSON content. The CLI and mobile client now omit the JSON header when no body is sent.

## Android rollout

Version `0.1.2+3` uses the existing release signing key. ARM64 split version code is 2003. The APK embeds the gateway URL and excludes server credentials. Downloads are served from `build/apk-download/`; install the matching architecture as an update.

No Android device was connected during deployment. Installing the final APK, confirming Get Maps without a second Google picker, offline reopening, and a real survey export on a phone remain required acceptance checks. Existing installed APKs do not update automatically.

Google can still revoke the central owner grant. In that event the owner reconnects the server; fieldworkers are not prompted for Drive consent. Free platform quotas remain finite.
