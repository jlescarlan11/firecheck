# FireCheck Mobile

FireCheck Mobile is an Android field survey app for enumerators working on Philippine Bureau of Fire Protection (BFP) assessments. Enumerators download assigned maps, collect building, road, and household survey data offline, then review and upload their changes when they reconnect.

**MVP for academic evaluation · Android submission release 0.1.10**

## Features

| Feature | What it supports |
| --- | --- |
| Offline fieldwork | Download multiple assigned maps and map tiles, choose a working map, and save survey edits without connectivity. |
| Building and road surveys | Capture building construction and fire load details, road width and surface material, and photos. Use **New Feature** to sketch a missing building or road, with Undo and discard confirmation. |
| Household fire vulnerability | Complete the Oplan Ligtas na Pamayanan (OLP) household survey and view its *Lebel ng Kahinaan* score. |
| Review and upload | Select maps for review and upload your own changes progressively. Accepted revisions remain in history; later edits can be uploaded again. Track transfers and retry failed work. |
| Map and conflict review | A dashed orange outline marks the read-only assignment boundary; blue geometry marks the working edit. Compare duplicate features offline before choosing a resolution. |

## Screenshots

Flutter test captures using sample data.

| Home | Building survey | Upload review |
| --- | --- | --- |
| ![Home screen with survey progress](docs/design/2026-09-15-app/app-home-390.png) | ![Building survey form](docs/design/2026-09-15-app/app-building-390.png) | ![Upload review screen](docs/design/2026-09-15-app/app-review-390.png) |

## Install the demo APK

[Download the signed FireCheck 0.1.10 demo APK (ARM64)](https://github.com/jlescarlan11/firecheck/releases/download/v0.1.10/FireCheck-0.1.10-arm64-v8a.apk).

Download the APK on an ARM64 phone running Android 8.0 or later and open it to install. If Android prompts you, allow installation from the app you used to open the APK.

The project team needs to enroll your Google sign-in account in a published sample assignment before you can download the demo map. [Android release guide](docs/ANDROID_RELEASE.md)

## Try the app

1. While online, sign in, open **My Maps**, choose **Download maps**, and download an assigned map. Return to your maps and choose the map to work on.
2. Turn off network access, select a building polygon, fill out the survey, add a photo, and save. Reopen the survey to confirm the data persisted.
3. Reconnect, choose **Review before upload**, select the maps to review, and check edited or newly added features. Follow the available upload action, then check transfer progress and the result. Uploading preserves accepted revision history and allows later changes to be submitted.

For an existing installation, use an APK signed with the same release certificate and a higher Android version code to update in place. Do not uninstall to resolve an update error: uninstalling deletes local work. [Release notes and known limits](docs/releases/0.1.10.md)

## Run from source

Install Flutter and the Android SDK. The evaluation checks used Flutter 3.41.9 and Dart 3.11.5.

1. Clone the repository and open its root in Android Studio with the Flutter plugin installed.

   ```bash
   git clone https://github.com/jlescarlan11/firecheck.git
   cd firecheck
   cp .env.example .env
   flutter pub get
   flutter gen-l10n
   ```

2. Set your Supabase URL and publishable key, public Mapbox token, Google web OAuth client ID, and gateway URL in `.env`. Place the matching Firebase Android configuration at `android/app/google-services.json` and register the SHA-1 of the signing key used for the build. The app bundles `.env`, so use public client configuration there. [Independent setup guide](docs/SELF_HOSTED_SETUP.md)
3. Start an Android emulator or connect a phone with USB debugging enabled. Run `lib/main.dart` from Android Studio or use `flutter run` in the project root.

## Set up Google Drive for a demo

The evaluation APK uses the original project's hosted gateway. For that demo, ask the project team to enroll your Google sign-in account in a published sample assignment. To use Drive folders and accounts you control, deploy your own gateway and build the Android app with your project settings. [Independent setup guide](docs/SELF_HOSTED_SETUP.md)

### Folder and file layout

A supervisor can create this structure under a shared folder in the owner's My Drive:

```text
firecheck/
├── input/
│   └── demo-area/
│       ├── boundary.shp, boundary.shx, boundary.dbf, boundary.prj
│       ├── buildings.shp, buildings.shx, buildings.dbf, buildings.prj
│       └── roads.shp, roads.shx, roads.dbf, roads.prj
├── published/
└── output/
```

- Place the actual files directly in the assignment folder. Each row above lists four separate files with the same base name. Use the lowercase names shown for a standard demo.
- Use an area polygon for `boundary`, building polygons for `buildings`, and road lines for `roads`. Export the demo layers in WGS 84 / UTM zone 51N (EPSG:32651). For the standard survey schema, include `feat_id`, `bldg_use`, and `bldg_type` in the building attributes, and `feat_id` and `road_type` in the road attributes.
- If the demo uses a custom survey, place `form_definition.json` and/or `field_requirements.txt` alongside the shapefile components. The app has bundled defaults for a demo that uses the standard survey.
- The gateway copies input files to `published/` when the supervisor publishes an assignment. Update the files under `input/` and publish again to release a new version. The gateway creates upload folders under `output/` as surveys are submitted.

### Connect, publish, and enroll

For a new deployment, configure the gateway with the three Drive folder IDs and authorize the designated Drive owner's account using server-side OAuth. Follow the gateway guide for database setup, owner authorization, and deployment. [Drive gateway setup](server/drive-gateway/README.md)

From `server/drive-gateway/`, use the supervisor CLI to register the exact Drive ID of `demo-area/`, publish the map, and grant the evaluator access. This requires a Supabase assignment record and the evaluator's Supabase user UUID. If you need to create the assignment, the CLI's `create` command accepts a JSON file with `id`, `name`, `campaignId`, and a WGS 84 GeoJSON Polygon in `boundary`. Use the configured gateway URL and the supervisor's FireCheck session token in the CLI environment.

```bash
npm run admin -- source ASSIGNMENT_UUID DRIVE_INPUT_SUBFOLDER_ID
npm run admin -- publish ASSIGNMENT_UUID
npm run admin -- enroll ASSIGNMENT_UUID EVALUATOR_USER_UUID
```

The evaluator can then sign in and open **Get Maps**. If the map is missing, check that the supervisor published a version and enrolled the same account the evaluator used to sign in.

## Tech stack

- Dart and Flutter for the Android app, with Riverpod for state management.
- Drift and SQLite for offline data and the upload queue.
- Mapbox Maps SDK for maps and offline tiles.
- Supabase Auth, Postgres/PostGIS, and Storage for sign-in, survey records, and photos.
- A Supabase Edge Function gateway for downloading maps from and uploading shapefile exports to Google Drive.

## Validation

The [dated development verification record](docs/verification/2026-11-18-cleanup/README.md) records the reviewed cleanup source and its limits. The submission APK receives new version metadata; its build and publication are separate release steps.

| Check | Recorded development result |
| --- | --- |
| Flutter tests | 1128 passed, zero failures or skips |
| Flutter analyzer | 0 errors, 18 warnings, 913 informational diagnostics; existing baseline, not a clean analyzer run |
| Gateway checks | Typecheck passed; 70 tests passed |
| Current-source Android build | ARM64 release 0.1.9 / Android code 6014 passed the 55 MB gate at 47.72 MB |
| Updated installation walkthrough | Same-certificate in-place update retained visible progress across two maps. Home, map selection/zoom, unsaved sketch Undo/Cancel, biometric Review, empty queue and same-account continuity were observed. |

The walkthrough did not complete a new survey or perform a real upload. Extended device and hosted capacity checks were explicitly deferred. Backend policy migration/deployment, staging, production backend rollout and full field acceptance were not verified. Direct-Drive recovery may require a full app-process restart if the process identity registry owner ends; reopening a screen does not recover ownership. See [cleanup decisions](docs/CODEBASE_TASK_CLEANUP.md) for remaining acceptance and operational responsibilities.

## Architecture and documentation

- [`lib/features`](lib/features/) contains the assignment, map, survey, review, and upload screens and workflows.
- [`lib/core`](lib/core/) handles shared services. Drift and SQLite store work locally, Mapbox renders maps, and a local upload queue tracks work until it can be sent.
- [`supabase`](supabase/) contains the backend schema and migrations for Supabase and PostGIS. The [Drive gateway](server/drive-gateway/) handles hosted Google Drive operations.
- [`test`](test/) contains Flutter unit and widget tests. The [design specification](docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md) explains the original architecture and sync model.

FireCheck Mobile is available under the [MIT License](LICENSE).
