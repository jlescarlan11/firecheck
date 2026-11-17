# Run FireCheck with your own Google Drive

This guide is for instructors or teams who want to own the Drive folders, user accounts, and backend. The supplied 0.1.3 evaluation APK uses the original project. Build a fresh Android app after setting up your own services.

## 1. Prepare a sample map and the Drive folders

In the designated owner's My Drive, create `firecheck/input/demo-area`, `firecheck/published`, and `firecheck/output`. Put a sample shapefile set in `demo-area` using the [README's folder and file layout](../README.md#folder-and-file-layout). Record the IDs of `input`, `published`, `output`, and `demo-area` from their Drive URLs. Use sample data intended for the demo.

## 2. Create the Supabase backend

Create a Supabase project you control. From the repository root, using Supabase CLI 2.x, run:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --linked
```

The migrations create the database schema, photo bucket, and gateway role. Create a dedicated database login with a strong password and grant it membership in `firecheck_gateway_server`. Obtain its connection string and your project's database CA certificate.

Some of the 0.1.3 migrations rely on the older Supabase defaults for Data API privileges. On a new project with opt-in exposure, review the tables and operations used by the app and grant the required privileges to `authenticated` on those objects with RLS enabled. The Drive gateway schema stays private. Verify sign-in, survey reads and writes, and photo upload on the new project before handing off the build. [Supabase Data API privileges](https://supabase.com/docs/guides/api/securing-your-api)

## 3. Authorize the Drive owner and deploy the gateway

In your Google Cloud project, enable the Drive API and configure consent for the designated owner. Create a Web OAuth client for the gateway with the redirect URI `http://127.0.0.1:8765/oauth/callback`. Download its JSON to a private location, then run this from the repository root with Node 24 or later:

```sh
cd server/drive-gateway
npm ci
GOOGLE_OAUTH_CLIENT_FILE=/absolute/path/to/oauth-client.json \
DRIVE_OWNER_EMAIL=owner@example.com npm run connect-drive
```

Sign in as the Drive owner when prompted. The helper saves the resulting grant in `.secrets/drive/oauth.json` within the gateway directory. Create a private environment file for these Edge Function secrets. [Supabase Edge Function secrets](https://supabase.com/docs/guides/functions/secrets)

| Secret | Value |
| --- | --- |
| `FIRECHECK_DRIVE_OAUTH` | The contents of `.secrets/drive/oauth.json` as a single line of JSON |
| `FIRECHECK_DATABASE_URL` | The connection string for the dedicated gateway database login |
| `FIRECHECK_DB_CA_BASE64` | The project's database CA PEM certificate encoded as a single line of base64 |
| `DRIVE_INPUT_ROOT` | Your `input` folder ID |
| `DRIVE_PUBLISHED_ROOT` | Your `published` folder ID |
| `DRIVE_OUTPUT_ROOT` | Your `output` folder ID |

Run `npm run prepare:edge` in the gateway directory. Then return to the repository root and deploy to your own project reference. The `setup-drive` and `deploy:edge` package scripts in 0.1.3 contain IDs from the original deployment. Use the folder IDs and explicit CLI target above and below for your own project.

```sh
supabase secrets set --project-ref YOUR_PROJECT_REF --env-file /absolute/path/to/private-edge.env
supabase functions deploy drive-gateway --project-ref YOUR_PROJECT_REF --use-api
```

The gateway URL is `https://YOUR_PROJECT_REF.supabase.co/functions/v1/drive-gateway`. Confirm that `/healthz` returns HTTP 200. From the gateway directory, run `npm run probe-drive` with `GOOGLE_OAUTH_BUNDLE_FILE` set to the authorization JSON's absolute path and `DRIVE_INPUT_ROOT` and `DRIVE_OUTPUT_ROOT` set to your folder IDs. The probe verifies Drive access and creates a test upload folder.

## 4. Build the Android app for your project

Set up Google sign-in with the Web OAuth client for app login and the Android OAuth client for the app's package name and signing certificate SHA-1. Use the fingerprint of the key that actually signs your build. Configure the Google provider in your Supabase project with the Web client ID first and the Android client ID after it. Put the matching Firebase Android configuration in `android/app/google-services.json`. [Supabase Google sign-in](https://supabase.com/docs/guides/auth/social-sign-in/auth-google), [Firebase Android setup](https://firebase.google.com/docs/auth/android/google-signin)

Copy `.env.example` to `.env` in the repository root and fill in your settings:

```dotenv
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
MAPBOX_ACCESS_TOKEN=YOUR_PUBLIC_MAPBOX_TOKEN
GOOGLE_WEB_CLIENT_ID=YOUR_APP_LOGIN_WEB_CLIENT_ID
FIRECHECK_GATEWAY_URL=https://YOUR_PROJECT_REF.supabase.co/functions/v1/drive-gateway
```

Use public client configuration in this file because it is bundled into the app. Run `flutter pub get` and `flutter run` to test a debug build. Use your own release signing key to distribute a signed APK. A device that already has FireCheck under the same package name can update in place only with a matching signing certificate. [Android release guide](ANDROID_RELEASE.md)

## 5. Publish the map and verify the setup

1. Create or sign in as the supervisor in your Supabase project. Copy the supervisor's user UUID from Supabase Auth. In the SQL Editor, add that verified UUID to `firecheck_gateway.supervisors(user_id)`.
2. Set `FIRECHECK_GATEWAY_URL` and `FIRECHECK_ACCESS_TOKEN` in the local CLI environment. The access token is the supervisor's Supabase user session token. For a dedicated email/password supervisor account, obtain the session using the project's password sign-in flow. [Supabase password sign-in](https://supabase.com/docs/guides/auth/passwords)
3. From `server/drive-gateway/`, run `npm run admin -- health`. Create a demo assignment with `npm run admin -- create assignment.json`. The JSON needs `id`, `name`, `campaignId`, and a WGS 84 GeoJSON Polygon in `boundary`. Use fresh UUIDs for the assignment and campaign, and derive the longitude/latitude boundary from your sample map.
4. Register `demo-area`, publish the map, and enroll any separate evaluator account by its Supabase user UUID. The supervisor who created the assignment is already its owner. [Supervisor commands](../README.md#connect-publish-and-enroll)
5. Run [`activate.sql`](../server/drive-gateway/sql/activate.sql) in your new project to enable the worker routes.
6. On Android, sign in, download the published map, save a test survey offline, then reconnect and upload it. Confirm that the exported files appear in your Drive `output/` folder.
