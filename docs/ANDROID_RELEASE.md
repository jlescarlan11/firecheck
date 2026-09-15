# Android release builds

Build smaller, installable release APKs with:

```sh
bash tool/build_android_release.sh
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
`0.1.1+2`, the ARM64 APK has version code `2002` (verify with `aapt dump badging`).
Continue using the same split build scheme for direct APK updates. If switching
back to a universal APK or another distribution scheme, its version code must
exceed the installed split APK's code; simply changing `+2` to `+3` is insufficient.

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

A development-signed installation cannot be updated by this release-signed APK.
If one is already installed, upload or export any unsynced work before removing
it: uninstalling deletes the app's local data. Subsequent releases signed with
this release key can update the release installation.

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
