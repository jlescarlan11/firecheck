# Android release builds

Build smaller, installable release APKs with:

```sh
FIRECHECK_UPLOAD_APK=0 bash tool/build_android_release.sh --build-name=0.1.10 --build-number=4015
```

This builds one standalone APK per processor architecture, separates Dart debug
symbols, and checks each APK against a 55 MB download budget. Outputs are in
`build/app/outputs/flutter-apk/`:

- `app-arm64-v8a-release.apk`: phones running 64-bit ARM Android.
- `app-armeabi-v7a-release.apk`: phones running 32-bit ARM Android.
- `app-x86_64-release.apk`: x86-64 Android devices and emulators.

Install only the APK matching the device. When connected through ADB,
`adb shell getprop ro.product.cpu.abilist` lists its supported architectures.
Flutter adds architecture offsets to APK version codes when splitting. For
`0.1.10+4015`, the ARM64 APK is expected to have version code `6015`
(base build number `4015` plus ARM64 offset `2000`; verify the actual APK with
`aapt dump badging`). The latest development installation is `0.1.9` / code
`6014`, so this submission build advances its version code.
Continue using the same split build scheme for direct APK updates. If switching
back to a universal APK or another distribution scheme, its version code must
exceed the installed split APK's code. Compare the actual APK code against the
installed code rather than only comparing the base pubspec build number.

Each APK includes the same app features. Release builds use the `release`
signing configuration and do not fall back to the debug key.

Archive the matching `build/release-symbols/<build-id>/` directory with every
release outside the disposable build folder. It contains Dart symbols needed
by `flutter symbolize`, a JSON size report with APK hashes, and the R8 mapping
(`r8-mapping.txt`) for Java/Kotlin crash reports.

For Google Play distribution, build an Android App Bundle:

```sh
flutter build appbundle --release --split-debug-info=build/release-symbols/play-BUILD_ID
```

Use a unique `BUILD_ID` for each build and archive those symbols. Google Play
selects architecture-specific downloads from the bundle; the bundle's upload
size is not the per-phone download size.

A plain `flutter build apk --release` creates a universal APK containing all
three architectures. Use it only when one file supporting all devices is
specifically needed; the measured baseline was 135.07 MB.

## Size regression check

```sh
python3 tool/check_apk_size.py build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The check uses actual APK file bytes (decimal MB), rejects multiple native
architectures and compressed native libraries, and defaults to a 55 MB ceiling. `--baseline OLD.apk` includes
percentage savings in `--report report.json`. `--max-mb` sets an intentional
budget override; `--allow-universal` supports auditing universal packages.
These numbers describe the APK download, not installed storage or cached maps.
Keep native libraries uncompressed: the chosen priority is lower installed
storage and faster installation over the smallest possible download.

For a deeper Dart/package breakdown:

```sh
flutter build apk --release --target-platform=android-arm64 --analyze-size
```

See Flutter's [Android release guide](https://docs.flutter.dev/deployment/android)
and [app size measurement guide](https://docs.flutter.dev/perf/app-size).

## Signing key

This checkout has a dedicated release key created on September 15, 2026:

- Keystore: `android/signing/firecheck-release.jks`
- Alias: `firecheck`
- Local credentials: `android/key.properties`
- Public fingerprints: `android/signing/certificate-fingerprints.txt`

The keystore and credentials are excluded from Git and readable only by the
local owner. Back up both files together in secure storage. Keep using the same
key for future APK updates; do not regenerate it for each build. Never distribute
the keystore or credentials with the APK.

On another machine, restore those files to the same locations. `storeFile` in
`key.properties` resolves relative to `android/app/`.

## Google sign-in

The release certificate's SHA-1 and SHA-256 fingerprints are registered on the
Android app `ph.gov.bfp.firecheck` in Firebase project `firecheck-495005`.
Existing development certificate registrations are retained.

Google Cloud also has a dedicated Android OAuth client named
`FireCheck Android Release`, with client ID
`907009121107-4nhrn30qcv23jag2od90jbmiskp28mek.apps.googleusercontent.com`.
It pairs `ph.gov.bfp.firecheck` with the release SHA-1 fingerprint above.
Adding a fingerprint in Firebase alone did not create this OAuth client;
verify the matching package and fingerprint in Google Cloud's Clients page.

Supabase's Google provider accepts the existing web and development client IDs
plus this release client ID. The app continues to pass the web client ID as
`serverClientId`; do not substitute the Android client ID in `.env`.
Google notes that client configuration changes can take five minutes to a few
hours to propagate. These server-side registration changes do not require
reinstalling an otherwise correctly signed APK.

## Installing on a phone

Download the APK on Android, open it, and allow installation from the browser
or file manager when prompted. The app requires Android 8.0 or later.

An existing installation can update in place only with a matching signing
certificate and a higher actual Android version code. A same-certificate update
to development build `0.1.9` / code `6014` was tested in place; visible survey
counts and both downloaded maps were retained. This is visible continuity
evidence, not an exhaustive private-database audit. Schema v20 migrates upload
history and file/receipt bindings without resetting the database.

If installation fails because a development signing certificate differs, stop
and preserve or export unsynced work before planning a certificate transition.
Do not uninstall as a routine fix: uninstalling deletes local data. Keep the
existing release certificate for future updates.

## Shipping UI updates to an installed phone

Code changes and a debug build do not update a release installed on a phone.
Increment the version/build number in `pubspec.yaml`, build a signed release,
and copy the matching architecture APKs to `build/apk-download/` with both
the version and architecture in each filename. Keep using the release certificate above so Android can update the
existing installation in place.

The local download server must bind to this computer's **current** Wi-Fi IP
(`ipconfig getifaddr en0`); a previous address can become stale. Serve only
`build/apk-download/`, and open the download on a phone connected to the same
network. Keep its download page pointing to the latest verified APK.

## Automatic Google Drive upload

On this configured checkout, the release build script also uploads the ARM64 APK
when `server/drive-gateway/.secrets/apk-release.json` exists. Use explicit increasing
version/build numbers. The submission release is `0.1.10+4015` (expected ARM64
code `6015`), following the installed code `6014`. To build without publishing:

```sh
FIRECHECK_UPLOAD_APK=0 bash tool/build_android_release.sh --build-name=0.1.10 --build-number=4015
```

`FireCheck app releases/FireCheck-latest-arm64-v8a.apk` keeps the same file ID and
share link across releases. `Archive/` retains immutable versioned APKs. The
publisher verifies the actual APK package, architecture, version, size and Drive
checksum; it skips identical uploads and refuses downgrades or changed bytes
under an already published build number. An interrupted upload can be retried.
The build script uploads only after a successful build and APK size checks;
run the relevant application tests before releasing.

To upload an already built APK without rebuilding:

```sh
server/drive-gateway/node_modules/.bin/tsx server/drive-gateway/tools/publish-apk.ts --apply
```

The `--apply` command writes to Drive and must be a separately authorized
publication step. Omit `--apply` for local validation only. Set `FIRECHECK_UPLOAD_APK=0` to build
without uploading. Plain `flutter build` does not trigger uploads. Other processor
architectures are built by the release script but are not automatically published.

Setup on another machine requires Node 24+, gateway npm dependencies, the Android
SDK (`ANDROID_SDK_ROOT` / `ANDROID_HOME`, or the default macOS SDK location), the
existing protected `drive/oauth.json` OAuth bundle, and this ignored configuration:

```json
{
  "parentFolderId": "YOUR_PRIVATE_RELEASE_PARENT_FOLDER_ID",
  "anyoneWithLink": true
}
```

Use a parent folder without public edit permissions; inherited edit access cannot
be restricted by a reader permission on the APK.

The publisher writes verified release metadata and the provider-returned download
URLs back to this local configuration. `anyoneWithLink: true` grants public reader
access only to the Latest APK. Existing survey folder permissions are untouched.
Setting it to false stops granting public access; it does not revoke permissions
already granted in Drive. The script never prints OAuth credentials. A local
`apk-publish.lock` directory prevents overlapping publishers; after an interrupted
process, remove that directory only after confirming no publisher is running.


## Submission release handoff

The source version is `0.1.10+4015`. After build, inspect the actual package,
version code, ARM64 ABI and signing certificate, run the size gate, and retain
the APK with its matching symbols and hashes. Name the reviewed download
`FireCheck-0.1.10-arm64-v8a.apk` for GitHub release `v0.1.10`; the README points
to that release asset. A download link alone does not establish publication.

See [0.1.10 release notes](releases/0.1.10.md) and the [development evidence](verification/2026-11-18-cleanup/README.md).
The prior verified source APK was `0.1.9` / code `6014`; the submission binary's
build/package checks must be recorded separately. Mobile installation does not
apply backend changes. In particular, the forward photo policy migration
`supabase/migrations/20261118050717_authorize_photo_storage_mutations.sql` is
source-controlled and locally tested, but has not been deployed. Backend
operators must review inventory, migrations and deployment separately before
claiming rollout. No Drive folder moves or deletions are part of this release.
