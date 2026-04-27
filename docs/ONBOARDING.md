# FireCheck — Onboarding for the team

Welcome. This doc gets you from zero to "I just ran the MVP and surveyed a polygon" in under an hour, then orients you on how the codebase is organized and what to do next.

If you only have 5 minutes, read **§1 (run it)** and **§7 (where to look first)**. The rest is reference.

---

## 1. Run the MVP on your machine (45 min one-time setup)

### 1.1 Install the toolchain

| Tool | Version | Get it |
|---|---|---|
| Flutter | `>=3.22.0` stable | https://docs.flutter.dev/get-started/install |
| Android Studio | latest | for the SDK + emulator manager |
| Android emulator | Pixel 7, API 34+ | create via Android Studio → Device Manager |
| `adb` | bundled with Android Studio | should be on PATH |
| Git | any | likely already installed |

After installing Flutter, run:

```bash
flutter doctor
```

You want green ticks for **Flutter**, **Android toolchain**, **Android Studio**, and **Connected device** (after starting your emulator). Web/iOS/macOS are not required.

### 1.2 Get the credentials

Ask the team lead for:
- Supabase URL + anon key (for `.env`)
- Mapbox public access token (`pk.…`)
- Test login: `admin@admin.com` + the test password

If you want your own Supabase project (e.g., to break things safely):
1. Create a free project at supabase.com.
2. From `supabase/migrations/`, run all 10 SQL files in order via the SQL editor.
3. Insert one row into `assignments` for yourself + a few `features` polygons. Or copy the seed data the team uses.

### 1.3 Clone + install + codegen

```bash
git clone https://github.com/jlescarlan11/firecheck.git
cd firecheck
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

`build_runner` generates Drift classes (`lib/core/db/database.g.dart`). Re-run it whenever you change a Drift table. `gen-l10n` regenerates `lib/generated/l10n/*` from the `.arb` files; re-run whenever you add an i18n key.

### 1.4 Wire `.env`

```bash
cp .env.example .env
```

Fill in the three values. The app reads these via `flutter_dotenv` in `lib/main.dart`. Missing or wrong values throw `StateError` at boot with a clear message.

### 1.5 Start the emulator and run

```bash
# 1. start emulator from Android Studio Device Manager (or `emulator -avd <name>`)
# 2. then:
flutter run -d emulator-5554
```

Or if you want to keep using a separate terminal for `adb`:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n ph.gov.bfp.firecheck/.MainActivity
```

### 1.6 Walk the happy path

Sign in → **Get Maps** → wait for download → **Open map** → tap a red polygon → fill the form (RA 9514 type, storeys, material, cost, fire load) → take a photo → **Done**. Repeat for any other polygons. Back to Home → **Upload Data** → biometric (or skip if not enrolled, see §6) → `/review` → **Start Upload** → wait → "Submitted ✓" banner appears on Home.

---

## 2. Codebase tour

### 2.1 The 4 layers per feature

Most features in `lib/features/<feature>/` follow this pattern:

```
<feature>/
  domain/         # pure value classes + validators (no Flutter, no Drift)
  data/           # repositories — only place that talks to Drift / Supabase
  presentation/   # widgets + Riverpod providers + StateNotifiers
```

Test files mirror `lib/` directly under `test/`.

### 2.2 The big files to know

| File | What it does |
|---|---|
| `lib/main.dart` | Entry. Loads `.env`, initialises Supabase + Mapbox, mounts `ProviderScope` with overrides for the real renderer + tile-store, kicks `SyncController.start()` and `SubmittedAssignmentLock.watchAndStamp()`. |
| `lib/app.dart` | `MaterialApp.router` + theme + l10n delegates. |
| `lib/core/router/app_router.dart` | All routes (`/login`, `/`, `/map`, `/get-maps`, `/feature/:id`, `/feature/:id/olp/result`, `/review`, `/blocker`). Auth + ClosedRemotely redirects live here. |
| `lib/core/db/database.dart` | The `AppDatabase` Drift class. Schema version + onUpgrade migrations live here. **Schema is at v5.** |
| `lib/core/sync/worker/sync_controller.dart` | Singleton sync facade. Wires connectivity + lifecycle + WorkManager + the worker. |
| `lib/core/sync/worker/sync_worker.dart` | The actual outbox drain loop. Pure consumer of `SyncApi` + `SyncJobsRepository`. |
| `lib/features/review/presentation/review_screen.dart` | The Phase 4b Review screen composer. |
| `lib/features/map/presentation/map_screen.dart` + `map_renderer.dart` | The map. Renderer is split (`FakeMapRenderer` for widget tests, `MapboxMapRenderer` for production). |

### 2.3 How Drift works here

- Tables live in `lib/core/db/tables/*.dart` and are listed in `database.dart`.
- After editing tables, run `dart run build_runner build --delete-conflicting-outputs` to regen `database.g.dart`.
- Bumping `schemaVersion` requires writing a migration step in `onUpgrade` AND adding a test under `test/core/db/migration_v*_test.dart`.
- Tests use `AppDatabase.forTesting(NativeDatabase.memory())` — no real file. **Always close the DB in `tearDown`** or you'll get pending-timer assertions.

### 2.4 How Riverpod is structured

- **Providers** are in `presentation/<feature>_providers.dart` near the screen that uses them.
- **Streams from Drift** → `StreamProvider`. Most repositories expose a `watchX()` method that maps directly.
- **Use cases** → `Provider<UseCase>`. Notifiers compose them.
- **Forms** → `StateNotifierProvider.autoDispose.family<Notifier, State, FormKey>`. Family key is the `(submissionId, featureId)` tuple. AutoDispose so notifier dies when the screen unmounts.
- **Test pattern** → `ProviderContainer(overrides: [...])` for non-widget tests; `ProviderScope(overrides: [...])` for widget tests. Override providers, don't mock them.

### 2.5 i18n

- Source: `lib/core/i18n/app_en.arb` (English) + `lib/core/i18n/app_tl.arb` (Tagalog).
- After editing either file, run `flutter gen-l10n`.
- In code: `final l = AppLocalizations.of(context)!; ... l.someKey` or `l.someKey(arg)`.
- The Tagalog file does NOT need `@key` placeholder metadata blocks — those only go in the English template.

---

## 3. The sync engine — the part that's most subtle

The most interesting subsystem. If you're going to extend the app, you'll touch this eventually.

### 3.1 Outbox model

When the user taps **Done** on a form, the submission is moved to `sync_status='ready_to_upload'`. **Nothing is sent yet.**

When the user later taps **Start Upload**, `FinalizeSubmissionUseCase` runs in a Drift transaction and writes one row per upload-task into `sync_jobs` (one for the submission, one per photo, one per new feature). `sync_jobs` is the outbox.

`SyncWorker` then drains the outbox. It claims up to N pending jobs, runs them through `SyncApi`, and marks each row `success` / `pending` (with backoff) / `dead` (after 5 attempts).

### 3.2 Triggers (when does the worker run)

- **Foreground tap** — `SyncController.triggerNow()` from the Review screen's Start Upload button.
- **Connectivity restored** — `ConnectivityListener` watches `connectivity_plus` and triggers when offline → online.
- **App resumed** — `LifecycleListener` watches `WidgetsBindingObserver` for `AppLifecycleState.resumed`.
- **Background** — `WorkmanagerDispatcher` registers a 16-min periodic task. Fires even when the app is force-stopped.

### 3.3 Failure paths

- **401 Unauthorized** — refresh the session via `AuthRepository.refresh()`, retry once, give up if still failing.
- **409 (assignment closed remotely)** — the server returned SQLSTATE `53300`. We mark `assignments.closed_remotely=true`, run `PendingWorkBundle.exportFor(assignmentId)` to generate a JSON+ZIP archive in the app's Downloads dir, and surface the `AssignmentClosedBlocker` overlay with a Share button.
- **Other 4xx** — permanent failure, mark dead immediately.
- **5xx / network** — transient failure, increment attempts, schedule retry with exponential backoff.

### 3.4 Submitted-state lock

`SubmittedAssignmentLock.watchAndStamp(assignmentId)` is a passive watcher started at app boot in `main.dart`. It listens to `sync_jobs` + `assignments` and stamps `submitted_at = now` exactly when:
- At least one `success` sync_job exists for the assignment, AND
- No `pending` / `in_progress` / `dead` jobs remain.

The latter check covers submission jobs, photo jobs, and new-feature jobs together. Idempotent — won't re-stamp if already set.

### 3.5 Why two-phase photo upload

Photos are big and the network is flaky. We don't want to re-upload an 800 KB photo just because the metadata write failed. So:
1. **Phase A** — `POST /storage/v1/object/photos/<submission_id>/<photo_id>.jpg`. On success, we have the storage path.
2. **Phase B** — `UPDATE photos SET storage_path = '<path>' WHERE id = '<photo_id>'`. Only after this completes is the photo "uploaded" from the server's POV.

If Phase B fails (e.g., the photo bytes uploaded but the metadata write 500'd), we retry just Phase B without re-uploading. The `photos.upload_status` column tracks this state locally.

---

## 4. How to add a feature (the spec → plan → implement loop)

The team uses a deliberate process. Each "phase" is one feature or coherent group of features.

### 4.1 Brainstorm + write the spec

Open a doc at `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. It should answer:
- **Scope** — what's in, what's out.
- **Architecture** — module layout, key types, data flow.
- **i18n** — list new ARB keys.
- **Testing strategy** — unit + repo + widget tests.
- **Risks** — what might go wrong.
- **Phase N+1 follow-ups** — what you're explicitly punting.

Get a teammate to review before writing the plan.

### 4.2 Write the implementation plan

Open `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`. Each task is small (one file or two), TDD-style:

```
### Task 1: <name>
**Files:** Create / Modify / Test list
- [ ] Step 1: Write the failing test (full code)
- [ ] Step 2: Run + confirm it fails
- [ ] Step 3: Implement (full code)
- [ ] Step 4: Run + confirm pass
- [ ] Step 5: Commit (`feat(area): ...`)
```

No placeholders. Every step has the actual code or command. The point is that someone unfamiliar with the codebase can execute it.

### 4.3 Implement

Work top to bottom. **Commit per task.** Run `flutter analyze` and `flutter test` after each commit; both should be clean.

### 4.4 Tag + PR

When all tasks are done:

```bash
flutter analyze
flutter test
flutter build apk --debug
git tag -a phase-N-<short> -m "Phase N — <one-liner>"
git push origin main
git push origin phase-N-<short>
```

Then open a PR. The team uses `gh pr create --base phase-<previous>-snapshot --head main`. To create the snapshot branch from the previous phase's tag:

```bash
git branch phase-<previous>-snapshot phase-<previous>-<short>
git push origin phase-<previous>-snapshot
```

---

## 5. The conventions you'll trip on if you don't know them

### 5.1 Test patterns

- **Drift in widget tests** — instantiate `AppDatabase` *inside* the `testWidgets` body, not in `setUp`. Drift's stream timers + the Flutter test framework's `FakeAsync` zone deadlock if you cross the boundary.
- **Drift matcher collision** — `package:drift/drift.dart` exports `isNotNull` and `isNull`, which collide with `flutter_test`'s matchers. Always import as: `import 'package:drift/drift.dart' hide isNotNull, isNull;`
- **FK chain seeding** — when seeding a submission, you need: `assignments → features → submissions → photos → sync_jobs`. Skipping a parent fails the FK constraint silently in some test paths. There are seed helpers in many test files; copy the pattern.
- **`submittedBy` not `enumeratorId`** — when constructing a `SubmissionsCompanion.insert(...)`, the field is `submittedBy`. The user-facing parameter on `SubmissionRepository` is `enumeratorId` for historical reasons; don't confuse the two.

### 5.2 Linter pickiness (very_good_analysis)

- Single-quote strings.
- Trailing commas at every multi-line argument list.
- `prefer_const_constructors` everywhere it can apply.
- `avoid_redundant_argument_values` — if you pass a value that matches the default, drop the kwarg.
- `prefer_final_locals` — `final` over `var` unless reassigned.
- `no_leading_underscores_for_local_identifiers` — local helpers inside `void main(){}` shouldn't start with `_`.

Run `flutter analyze` before committing. Info-level lints are still expected to be zero.

### 5.3 Commit style

Mirror the existing log:

```
feat(<area>): <imperative summary>
fix(<area>): <imperative summary> [+ Bug N if it's a regression caught manually]
chore(<area>): <imperative summary>
docs(<area>): <imperative summary>
test(<area>): <imperative summary>
```

Body for non-trivial commits explains *why*, not *what*.

### 5.4 Don't push without testing

`flutter analyze && flutter test` on `main` should always be green. The team treats `main` as the trunk.

---

## 6. Common gotchas

### 6.1 Location permission denied

If you tap **Deny** on the Android location permission dialog, the geolocator stream errors out. Pre-Bug-14 this would crash polygon taps. Now it falls through gracefully — proximity check is skipped, detail screen still opens.

To re-prompt: `adb shell pm clear ph.gov.bfp.firecheck` then relaunch.

### 6.2 Biometric prompt doesn't fire

By default, fresh Android emulators have no fingerprint enrolled, so `BiometricGate.isAvailable()` returns false and the gate falls through to `/review`. To exercise the prompt:
1. Emulator → Settings → Security → enroll a fingerprint (set a PIN first if asked).
2. To authenticate, click the emulator's `⋯` (More) button → Fingerprint → "Touch sensor".

### 6.3 Build runner errors after a pull

If you see `database.g.dart` or `*.freezed.dart` errors after pulling, run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 6.4 i18n key missing

If `AppLocalizations.of(context)!.someKey` doesn't compile, you forgot to run `flutter gen-l10n` after editing the ARB. Run it and re-build.

### 6.5 `SUPABASE_URL missing from .env`

The app refuses to boot if `.env` isn't filled. Copy from `.env.example`, fill in real values.

### 6.6 Mapbox map renders black

Either `MAPBOX_ACCESS_TOKEN` is wrong / missing, or your token doesn't have `STYLES:READ` scope. Check at https://account.mapbox.com/access-tokens/.

### 6.7 "Polygons aren't tappable"

If after a clean install polygons don't respond to taps, check `adb logcat -d | grep -B 5 "_FeatureClickHandler"` for an unhandled exception. The Bug 11-15 series fixed several of these; if you find a new one, capture the exception and file an issue.

---

## 7. Where to look first (cheat sheet)

| If you want to… | Read this |
|---|---|
| Understand the whole app at once | `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md` (the master spec) |
| Add a new database column | `lib/core/db/tables/*.dart` + `lib/core/db/database.dart` (bump version + onUpgrade + add a migration test) |
| Add a new screen | Pick a feature, copy the file structure of `lib/features/review/`. Add a route in `lib/core/router/app_router.dart`. |
| Add a new sync entity | `lib/core/sync/domain/sync_entity_type.dart` + `lib/core/sync/data/sync_api.dart` + `lib/core/sync/worker/sync_worker.dart` (add a case) |
| Add an i18n string | `lib/core/i18n/app_en.arb` + `app_tl.arb` then `flutter gen-l10n` |
| Add a Riverpod use case | `lib/features/<feature>/presentation/sub/<name>_use_case.dart` + provider + test |
| Debug a sync issue on-device | `adb logcat -d \| grep -i "sync\|outbox"` |
| Reset the local DB | `adb shell pm clear ph.gov.bfp.firecheck` |
| See what tests exist | `find test -name "*.dart"` — they mirror `lib/` |
| See known limitations + deferred work | `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md` §15 + per-phase specs' "Out of scope" sections |

---

## 8. Where to ask for help

- **Code questions** — read the spec for the area first, then ping the team.
- **Process questions** — re-read §4 above; the spec → plan → implement loop is intentionally explicit.
- **Stuck on a bug** — capture `adb logcat` output, describe the symptom + what you tried, and ask. The team's debugged a lot of these by now.

Welcome aboard. Have fun.
