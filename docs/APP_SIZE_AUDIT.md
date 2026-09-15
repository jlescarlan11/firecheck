# App size optimization loop

## Baseline — September 15, 2026

The existing signed release APK is **135,074,511 bytes (135.07 MB)**.
A copy is retained locally at `build/size-audit/baseline/app-release.apk`.
ZIP inspection attributes nearly all of the download to native libraries:

| Component | APK entry bytes (MB) |
| --- | ---: |
| x86-64 native libraries | 48.77 |
| ARM64 native libraries | 45.64 |
| ARM32 native libraries | 37.03 |
| Android bytecode | 2.08 |
| Flutter assets | 0.31 |

Sizes are decimal MB, matching download file sizes. ZIP overhead and remaining
resources account for the rest. Native library entries are stored uncompressed.
The three largest native components are Mapbox, the Flutter engine, and compiled
Dart app code. These are used by the app; deleting libraries would break it.
Android code and resource shrinking are already enabled by Flutter's plugin.

## Repeatable loop

1. Preserve a known baseline APK and its hash.
2. Make one targeted packaging or code change.
3. Run `bash tool/build_android_release.sh`.
4. Compare each APK with the baseline using `tool/check_apk_size.py`.
5. Run applicable app tests and verify signatures/package metadata.
6. Test installation and critical flows on an available Android device.
7. Record measured outcomes and retain matching debug symbols before distribution.

The build script makes separate, fully installable APKs for ARM32, ARM64, and
x86-64. Its gate rejects an accidental universal APK and sizes above 55 MB.
Symbols are separated from the downloaded APK and retained under a unique build
folder. Run gate tests with:

```sh
python3 -m unittest discover -s tool -p 'check_apk_size_test.py'
```

## Validation limits

No Android device was connected at the start of this audit. Build, signature,
archive, and host tests cannot establish camera, maps, login, or background-job
behavior on an actual phone. Keep that device check visible when releasing.

## Iteration results

- Baseline: 135.07 MB; includes all three native architectures.
- Separate-architecture build: ARM64 **49.10 MB** (63.65% smaller), ARM32
  **40.51 MB** (70.01% smaller), x86-64 **52.24 MB** (61.33% smaller).
  All three passed the 55 MB budget and single-architecture checks.
- Full existing Flutter suite: **880 passed, 2 skipped, 0 failed**.
- Separate Dart symbols:
  - arm64-v8a: **47.53 MB**, **64.81%** below the universal baseline.
  - armeabi-v7a: **38.60 MB**, **71.43%** below the universal baseline.
  - x86_64: **50.66 MB**, **62.49%** below the universal baseline.

## Photo responsiveness iteration

Photo decoding, resize, and JPEG encoding previously ran on the UI isolate.
They now run in a worker using `compute`, passing file paths only. EXIF platform
calls remain on the main isolate. The output remains a JPEG at quality 85 with
a maximum 1600-pixel edge; no additional image-size reduction is claimed.

Host benchmark (`tool/photo_processing_benchmark_test.dart`), one run per variant:

| Measurement | Before | After |
| --- | ---: | ---: |
| Longest main-event-loop gap | 1229.699 ms | 59.041 ms |
| Elapsed time | 1314.785 ms | 3514.201 ms |
| Output bytes | 47,513 | 47,513 |

These runs occurred on a shared computer during a release build, with variable
load. They demonstrate reduced main-isolate blocking, not a proven total-time
speedup or Android frame-time guarantee. Native-device profiling remains needed.
All 16 targeted photo/benchmark checks passed. Two additional failure-path tests
verify corrupt-image and missing-file errors cross the isolate boundary; the
five image-processor tests passed together.

Changed photo code and its test/benchmark files pass targeted Flutter static analysis.

## Upload batching iteration

The worker previously loaded every eligible pending job, then took three in
Dart, repeating that work for every batch. It now applies `LIMIT 3` in SQLite
before materializing rows, while keeping retry eligibility and deterministic
creation-time/ID ordering. Other repository callers retain unlimited results
unless they request a limit. Invalid limits fail explicitly.

All **53 Drive tests** passed, including a seven-job drain that fetched batches
of `[3, 3, 1, 0]`, completed all uploads, and verified filtering before limiting.
For seven eligible jobs without retries, that means loading seven job objects
across batches instead of 7 + 4 + 1 = 12. No database schema migration is needed.

## Native-library compression tradeoff (estimate only)

A ZIP deflate measurement of the ARM64 libraries estimates a **22.34 MB** APK
if native libraries are compressed. This is not a built, signed, or device-tested
artifact. Android would then extract the native libraries during installation;
APK plus extracted libraries is estimated at **66.41 MB**, compared with the
current **47.53 MB** APK whose native libraries are uncompressed. App data,
compiled artifacts, and caches are excluded from both estimates.

The selected policy is lower installed storage and faster installation. Keep
native libraries uncompressed; do not enable legacy compressed packaging to
reduce download bytes at the expense of installed storage.

## Download byte-buffer iteration

Google Drive map, assignment metadata, and sidecar downloads now accumulate
chunks with `BytesBuilder` instead of growing general-purpose `List<int>`
objects and converting them afterward. Default copying protects against reused
mutable input chunks. All four focused download tests passed, covering contents,
progress, sidecars, checksums, and inactivity timeouts. This avoids the generic
integer-list representation; no exact device-memory reduction is claimed.

The size gate also rejects compressed native libraries, enforcing the chosen
installed-storage policy even if a future packaging change produces a smaller APK.

## Combined build verification

- arm64-v8a: **47,526,471 bytes (47.53 MB)**, **64.81% smaller** than baseline.
- armeabi-v7a: **38,595,519 bytes (38.60 MB)**, **71.43% smaller** than baseline.
- x86_64: **50,662,911 bytes (50.66 MB)**, **62.49% smaller** than baseline.

All three combined APKs passed signature verification against the baseline
release certificate, 16 KB ZIP alignment, package/minimum-SDK checks, and
`extractNativeLibs=false`. Copies are retained in `build/size-audit/combined/`.
Matching Dart symbols, R8 mapping, and hashes are in
`build/release-symbols/20260915T150354Z-96630/`.

The five Python size/storage-policy tests pass. The download tests were rerun
with the explicit checksum assertion and all four passed. These artifact checks
are complete. The combined ARM64 APK installed successfully on a fresh ARM64
emulator reporting a 16,384-byte page size and reached the sign-in screen.
The app-specific log contained no fatal exception, unhandled Dart exception, or
native-link error in the captured startup interval. Screenshot:
`build/size-audit/launch-settled.png`.

The fresh emulator initially stalled with its default graphics backend. It
booted with SwiftShader and 2 GB RAM, but Android System UI and Play Store also
reported responsiveness failures during first startup. The initial activity
wait timed out before the screen appeared. This validates installation and
basic launch, not startup performance or authenticated feature flows. Physical
phone checks for sign-in, maps, camera/GPS, and background uploads remain.

## Finalization checks

The authentication changes present in the final working tree also passed their
**41 authentication tests**. The combined release build was generated after
those source changes. The local `build/apk-download/` page now points to the
verified architecture-specific APKs. No release signing credentials or keystores
are included in version control. The temporary emulator was shut down and
removed after logs and the launch screenshot were saved.
