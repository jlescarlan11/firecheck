# Cleanup development verification — 2026-11-18

This is the durable evidence summary for the [18 cleanup requirements](../../CODEBASE_TASK_CLEANUP.md). It records development results, including failures and limits; it does not establish full PRD completion. Final whole-session review identified two residual R02 gaps. Latest-finalization and concurrent-drain atomic-claim/schema-v20 process-ownership corrections are now frozen and independently approved; current-source arm64 build and final full suite both pass. No backend deployment/policy rollout or full field acceptance was verified. The current mobile binary was observed on the user's existing installation after approved in-place update.

## Tested identity and evidence handling

Base HEAD: `94b6713ec4182769f873a93c28951c78efa9044e`, with the existing mixed uncommitted working tree preserved. No commit was created. Flutter 3.41.9 stable/framework `00b0c91f06`. Exact session snapshots, source freeze hashes, full logs and per-task reports are retained locally under `.superpowers/sdd/2026-11-18-codebase-task-cleanup/`; task-7b-report.md identifies this document's exact manifest. Those local artifacts may be ignored by Git and are supplementary to this tracked summary.

Native checks used the separate `ph.gov.bfp.firecheck.cleanupvalidation` profile AOT arm64 app on TECNO CLA5, Android 16/API 36, RAM 7,871,176KiB (~8 GB). Current harness APK SHA256: `3393ce9e5ed054abacfe047731aaeb969c474c2ae19b0514fd77f28f5006490a`. During this isolated-harness phase, the installed production package and its real data were untouched; the later user-approved in-place update is documented below. The harness has no INTERNET permission and starts no sync worker. Its fixture has one synthetic account, two downloaded synthetic assignments, four building polygons and one durable synthetic submission. App network permission prevents network access regardless of phone radio state.

The harness uses live product implementations/copied frozen sources. Only its copied Mapbox renderer's offline style/reload seam differs: local blank light/dark styles allow native annotation/lifecycle inspection. Default online basemap appearance is not established. Scratch pubspec0.1.3+4 is distinct from the pre-existing production0.1.9/code4013 installation. Scratch profile size is not a product release-size result.

Only synthetic-geometry screenshots and selected sanitized native metrics are tracked here. Camera images, camera preview screenshots, exact GPS coordinates, isolated databases, raw private Drive manifests, credentials, emails and quota details are excluded.

## Later practical installed-app walkthrough and scope decision

The user explicitly deferred extended device/capacity validation in favor of a practical walkthrough and has only the current phone available. F03/O02 extended acceptance remains deferred by that scope decision rather than asserted passed. Accountable roles and technical gaps remain in the disposition record.

The [sanitized installed-app walkthrough](installed-walkthrough-summary.json) covers the existing installed app0.1.9/code4013, **not a binary built from this working tree**. Observed routes: Home, My Maps, Gather Data map selection/zoom, distance-policy override prompt cancelled, Review after the user's normal biometrics (up to date), empty upload queue with Upload All disabled, Account, and Home restored. The original working map was restored. No survey drafts or manual uploads were requested. This establishes navigation/read UI in the older app only; it does not establish new-code behavior or new-survey end-to-end acceptance. Raw screenshots contain real account/map data and remain ignored/local.

## Automated development checks

Commands below are executed results reported by the owning tasks/controller; this documentation step did not repeat them. Final v20 verification is identified explicitly; earlier1103/1118 full-suite counts and three-ABI builds are historical/intermediate. The final run follows the approved v20 correction and test-only schema-fixture repair, using normal Flutter test concurrency with no competing APK/AOT build.

| Command / boundary | Final result | Local evidence |
| --- | --- | --- |
| `flutter test --no-pub` | **1128 PASS, zero failures/skips**, exit0,136s, final v20 source. Earlier stopped parallel run is not passing evidence. | `final-fix-logs/root-final-flutter-v20-serial.log` |
| `flutter analyze --no-pub` (earlier full check) | Exit1;931 existing findings: 913 info, 18 warnings, 0 errors. Same live-source baseline; final v20 scoped analysis retains the same11 database infos and seven targets clean. Archived `build/**` excluded without deleting archives or suppressing live diagnostics. | `task7a-evidence/full-root-analyze.log` |
| `flutter test --no-pub tool/photo_processing_benchmark_test.dart --reporter expanded` | **1 PASS**;437.137ms, max event-loop gap13.339ms. Host only. | task-7 brief / `/tmp/firecheck-cleanup-photo-benchmark.log` |
| `python3 -m unittest discover -s tool -p 'check_apk_size_test.py'` | **5 PASS**. | controller task-7 brief |
| `FIRECHECK_UPLOAD_APK=0 bash tool/build_android_release.sh` (pre-v20) | **Earlier PASS**, all 3 ABI size checks: armeabi-v7a 38.81MB, arm64-v8a 47.72MB, x86_64 50.92MB. No publication. | `task7a-evidence/release-build.log`; symbols `build/release-symbols/20261118T080646Z-88481` |
| Current-source arm64 release (publishing disabled) | **PASS**,466.5s,47.72MB;0.1.9/code6014, installed after explicit user approval; no APK publication. | `final-fix-logs/root-final-arm64-v20.log` / package+size proof |
| Gateway: `npm run check` | **PASS** (`tsc --noEmit`). | `task6-fix1-logs/check.log` |
| Gateway: `TEST_DATABASE_URL=<designated disposable local PostgreSQL> npm test` | **70/70 PASS**, zero failed/skipped/cancelled. | `task6-fix1-logs/full.log` |
| Gateway strict tool/test typecheck (command below) | **PASS**. | `task6-fix1-logs/tools-check.log` |
| Gateway: `npm run prepare:edge` | **PASS**, local build/artifact generation only; no deployment. Later fix affects runner/tests, not Edge source. | `task6-logs/edge.log` |
| Localization regeneration: `flutter gen-l10n` | **PASS**; unused `phase2FormNote` removed from both ARB sources/generated output.19 existing untranslated Tagalog entries remain separately reported. | task-7a report |

Gateway commands run from `server/drive-gateway`. Strict tool/test command:

```sh
npx tsc --noEmit --target ES2023 --module NodeNext --moduleResolution NodeNext \
  --strict --esModuleInterop --skipLibCheck --noUncheckedIndexedAccess \
  tools/development-publication-probe.ts tools/inventory-publications.ts \
  test/probe-timeout.test.ts test/probe-timeout-child.ts
```

The development DB is the dedicated disposable loopback PostgreSQL/PostGIS service on port 55441. The real [migration fixture](../../../server/drive-gateway/test/migration-fixture.ts) applies the repository's complete migration chain, including historical grant simulation and the new forward photo policy; it tests a clean install and representative pre-fix upgrade. Reproduce focused policy checks from the gateway directory with `TEST_DATABASE_URL` pointing only to a disposable fixture database:

```sh
npx tsx --test test/photo-storage.test.ts
npx tsx --test test/supervisor-contract.test.ts
```

Photo role matrix: 20 PASS. Anonymous, peer/nonmember, revoked, cross-assignment, spoofed owner, malformed/encoded paths, rename/bucket moves, canonical authority/closure mutation, legitimate author upload/upsert/registration after closure and service cleanup are covered at SQL/RLS boundaries. These are not Storage HTTP tests. Public GIS read policy remains intentionally unchanged. Local advisors baseline/final are identical 13 findings (4 INFO,8 WARN,1 ERROR), including pre-existing public PostGIS issues; no newly introduced finding is claimed, and no globally clean result is implied. The final isolated probe records PostgreSQL 17.11/aarch64/GCC 15.2.0; fixture/source and local reports identify the applied chain.

## Native observations

The controller observed actual native Mapbox maps, product duplicate UI and actual local repository actions. [Light reshape](reshape-light.png) and [dark reshape after style reload](reshape-dark.png) show dashed orange boundaries and the blue working shape. Zoom in/out, map A→B replacement, `b-existing` feature tap callback and clearing an invalid boundary all completed without an observed crash. These screenshots use synthetic geometry only.

[Comparison available](review-available.png) shows both geometries at shared scale, labels and distinct marker shapes in the legend, available offline. [Comparison unavailable](review-unavailable.png) shows explanation, all three destructive decisions disabled, Retry and Skip enabled. Keep both, Replace theirs and Discard mine each queued through the actual product local repository; no remote receipt is claimed.

Actual native camera cancellation left photo_count 0; retry persisted photo_count 1 with a 507,591-byte file in the isolated app. GPS service enabled/whileInUse permission returned a position; coordinates are omitted. A synthetic asymmetric 800×600 EXIF orientation 6 fixture produced 600×800 output with orientation 0, and GPS return/output match booleans were true. This verifies a synthetic metadata case, not every camera manufacturer's EXIF. After force-stop/relaunch of the isolated app, startup and repository checks retain one photo and one pending `new_feature_resolve` job for synthetic `b-mine`. The separate pending_resolutions table retains the exact synthetic target `b-mine`, kind `new_feature`, decision `discard_mine` before and after restart. The queue payload is null because the decision is stored in that separate table. This proves local persistence of the exact resolution; no remote acceptance is claimed. Original stay-awake setting 0 was restored. During the earlier 94-second inactivity observation the same process remained foreground/alive; no idle exit was reproduced.

## Photo measurements and their limits

[Sanitized metric summary](native-summary.json) retains the complete20-sample camera-derived case and exact attribution fields. Fixture preparation is outside warm-up/measurement: native 3048×4064 camera pixels are orientation-corrected, center-cropped/resized to 3000×2000 and identifying EXIF stripped. The unchanged product processor then processes 20 samples after separate warm-up. Raw camera bytes are unchanged and are a separate larger-input case.

| Case | Result | Interpretation |
| --- | --- | --- |
| Camera-derived 3000×2000 | 20 samples; p95 **3218.347ms**; peak observed RSS 475,480,064bytes; process high-water 498,937, 856bytes; output1600×1067. | Proposed 5s camera-case target passes on this phone. |
| Same case UI | 120.0000076Hz,8.3333ms budget; 3736 in-window frames, 85 over budget (**2.2751606%**); max total frame span 40.886ms; max main-isolate timer gap45.03ms. Collection complete/eligible. | Proposed<5% frame and 250ms stall targets pass for this case. No crash/ANR observed during the run. |
| Legacy synthetic3000×2000 stress | 20 complete samples; p95 **5326.23ms**; observed RSS473, 853,952bytes. | **Exceeds proposed 5s**. Its pre-fix frame percentages are ineligible; valid processing timing remains reported. This prevents an “all performance passed” claim. |
| Raw larger native camera 3048×4064 | 20 post-warm-up samples; p95 **4701.337ms**; observed peak RSS 485,609,472bytes, process high-water 498,937, 856bytes; output 1200×1600. 5508 frames/87 over budget (**1.5795207%**), complete/eligible; max timer gap 44.467ms, max total span 43.327ms. | Reported separately; no approved larger-input maximum/performance budget. The 6MP target is not applied to this case. |

The fixed harness filters FrameTiming by monotonic `startUs <= vsyncStart < endUs` around precisely the 20 processor calls, retaining full durations of end-straddling frames. It waits for an actually delivered post-window frame sentinel; a 5s collection timeout makes the gate ineligible. The complete camera case excludes 3 pre-window and 3 post-window frames. Delayed batch, boundary, timeout and sanitization tests pass (7 helper tests total). Prior buffered/guessed-tail frame percentages cannot establish the gate.

RSS is sampled every 20ms: observed peak is not guaranteed instantaneous maximum; process high-water includes setup/warm-up. Flutter build/raster/total-span timing measures Flutter UI while its progress animates, not native surface presentation. Timer gap is separate main-isolate evidence. Display rate is adaptive and applies per run. These measurements do not imply all device classes or whole-app flows pass.

## Publication, retention and remaining acceptance

Gateway reliability tests cover source recheck/copy checksums, rollback/current-pointer atomicity and fresh retry. The reviewed isolated private My Drive + local PostgreSQL probe **completed successfully**, exit 0. [Sanitized probe summary](publication-probe-summary.json) records 100 source files/1,073,741,824bytes. First publication returned 200 in 105,099.977ms; fresh retry returned 200 in 104,766.144ms, each with 100 copied files and verified metadata/hash/count. A controlled failure after one 64-byte copy returned 503 in 2665.274ms; the old current pointer remained advertised, its 64-byte version download returned 200 and only one version was committed at that failure boundary. Final state has two verified version bindings; the original immutable version was reverified. Source upload took 413,445.419ms separately from publication.

Execution used Node 24.21.0/darwin arm64, actual Google Drive and local PostgreSQL 17.11/aarch64. Proof was saved before dropping only the unique local probe DB. Private append-only remote artifacts are retained within the planned 3GiB+64byte bound; no automatic cleanup occurred. This opaque-byte payload is not GIS-valid and does not demonstrate the 128MiB mobile importer maximum or hosted ingress/CPU/memory/time capacity. No raw probe IDs, manifest, quota or account metadata are tracked here.

Source publication remains synchronous. [Gateway runtime contract](../../../server/drive-gateway/README.md) documents separate Drive request, database transaction, ingress and selected hosting limits. Hosted maximum valid GIS workload, CPU/memory/ingress behavior and durable publisher escalation remain O02 acceptance work. A background shared-map export worker is not a durable source publisher.

Report-only orphan tooling protects current/all retained versions, source/upload/export references, unknown/history and possible in-flight work, and reports concurrent state/list failures as inconclusive. Remote orphan inventory, organizer dry-run or historical movement was not performed. No deletion/trash/move or retention apply mode was implemented or invoked.

Pending required acceptance includes a representative lower-spec second device class; native sign-in/account switching; full native sketch/survey flow; actual remote sync acceptance; interrupted/background real uploads and transport restart behavior; default online basemap contrast; Storage HTTP/GIS link smoke checks; and representative GIS-valid hosted publication capacity. Rights-holder authorization/third-party notice review remains unresolved despite the pre-existing MIT file. Accountable roles/review triggers are in the disposition table; no individual assignee is invented. The user explicitly deferred extended device/capacity validation; those checks remain unperformed and are not performance/capacity passes. R02 correction and scoped review are complete; current-source arm64 build and final full suite both pass.

## Final R02 concurrency correction

Whole-session review's two P2 gaps are addressed and final scoped Codex review approved with no new material defect. The R02 correction spans10 cumulative paths (9 in concurrency wave); the later separate schema fixture update makes11 final checked paths. Evidence:37 final focused checks and92 covering checks PASS; seven new/other handwritten targets analyzer clean, database.dart retains the same11 pre-existing infos. Deterministic concurrency coverage uses two SQLite connections to an actual file; process-identity coverage includes a spawned isolate, registration races and dead/unresponsive owner handling. The v19→v20 forward migration preserves upload history and file/receipt bindings.

Latest intended direct export batch controls finalization; conditional SQL claims recheck original owner, retry eligibility, FIFO and supersession before transport. A stale selection or another drain cannot reclaim an active same-process upload. Process identity is shared through the global VM registry, verified against the current single Android-process foreground/WorkManager model. Missing/invalid/unresponsive identity means no direct upload/recovery.

Accepted availability limit: after the registry creator terminates normally (including background-first completion) or crashes, other drains may need a **full app-process restart**. Screen reopening/retry does not recreate identity or steal a claim. A full restart ends workers and permits prior-process recovery for the original account. Separate-OS-process runners need additional liveness protection before introduction. This is integrity protection, not uninterrupted recovery or a new resumable transport. Earlier three-ABI release results predate v20; current-source arm64-only build and final full Flutter run both pass.

Current-source arm64 release: **PASS**,466.5s,47.72MB size gate PASS, package `ph.gov.bfp.firecheck`, ABI `arm64-v8a`, measured versionName `0.1.9` / versionCode **6014**. The command's build-number4014 receives this project's ABI offset; do not identify the output as code4014. APK SHA256 `92e51efb566bb327d448a5d1b689e97c192a7c1df9e79a4a29068323df0c6ffa`. Installed in place after explicit user approval; not published. Evidence: `final-fix-logs/root-final-arm64-v20.log`, `root-final-arm64-size.json`, `root-final-arm64-package.txt`. No current-source three-ABI claim is made.

The first full v20 run was stopped after a stale schema fixture expectation and three UI-condition timeouts during competing heavy AOT work. Its SIGINT exit0 is **not a passing test result**. The schema fixture was corrected to its intended minimum-version assertion (test-only, no binary change); a fresh full run without the competing build **passed 1128 tests, zero failures/skips, exit0,136s**, at `final-fix-logs/root-final-flutter-v20-serial.log`. All three earlier UI timeouts disappear in that run.

Final automated result: **Flutter 1128 PASS**, zero failures/skips; current-source arm64 release PASS; scoped final code review approved. Earlier1103/1118 counts and prior three-ABI builds remain historical/intermediate evidence. Gateway70/70 and host/Python checks remain as recorded because the later correction did not alter those boundaries. The user explicitly approved installation over the real field-data app; signature/SHA checks matched and `adb install -r` succeeded. Package manager confirms0.1.9/code6014. The completed updated-app walkthrough below supersedes the earlier installation-pending state. The installed APK binary was preserved before update; that is not a full field-data backup.

## Approved updated-app walkthrough — complete

The user explicitly approved installing the updated APK over the real app. The controller reverified SHA256 `92e51efb566bb327d448a5d1b689e97c192a7c1df9e79a4a29068323df0c6ffa` and matching signing certificates; `adb install -r` succeeded. Package manager confirms versionName0.1.9/versionCode6014. These observations establish current mobile UI on the user's existing installation; the earlier installedcode4013 walkthrough is preserved separately.

[Sanitized updated-install summary](updated-install-summary.json) records the observed outcomes without map names, account identifiers, process IDs or raw screenshots:

- Home retained4 surveyed/1438 total/1434 remaining; both maps retained their prior1/5 and3/1433 counts. Offline basemap was ready; map selection/zoom worked.
- In an unsaved Building sketch, Finish was disabled with0/2 vertices, enabled after3 distinct vertices, disabled after Undo→2. Cancel requested discard confirmation; Discard removed the unsaved sketch. Finish/save was never invoked and no feature was created.
- After normal user biometric authentication, Review opened: selected map1/1 complete,0 incomplete,0 new features,0 photos pending; No New Changes/Up To Date.
- Upload queue showed0 files/no pending uploads and Upload All disabled. No manual upload was requested.
- Account continuity comparison was true; no email/account identifier is tracked. Original working map and Home were restored. End Home counts match the before counts; stay-awake remains0.

The app's private database was not extracted. Retained UI counts prove visible continuity, not exhaustive database integrity. Full new-survey completion/actual remote sync were not exercised. Extended device/capacity protocol remains deferred by the user. No backend deployment/policy rollout or full field acceptance is established. Raw screenshots contain real map/account data and remain ignored/local. No installation approval remains pending.
