# FireCheck Mobile — Phase 4b Design Spec

**Date:** 2026-04-27
**Status:** Draft v1 (brainstorming output)
**Phase:** 4b — Review screen + Upload Data flow + Submitted/Closed lock UI
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Predecessor:** `docs/superpowers/specs/2026-04-26-firecheck-phase-4a-design.md`

## 1. Summary

Phase 4b is the user-facing wrap of Phase 4a's sync engine. It replaces Phase 4a's debug long-press trigger on the Home screen with the proper **Upload Data** flow per master spec §8 Flow F:

> Home → Upload Data → biometric gate → review screen lists: total features, completed, incomplete, new features added, photos pending; surfaces validation warnings → Start Upload → sync worker drains queue with per-item progress → on success, assignment locked (submitted_at set, no further edits).

After this ships, an enumerator can:

1. Tap **Upload Data** on Home → biometric gate (`local_auth`) → routes to `/review`.
2. Review screen shows summary (X features, Y complete, Z incomplete, etc.), validation blockers + warnings (with deep-link to fix), failed-jobs section (with per-item + Retry-all), and the **Start Upload** button.
3. Tap Start Upload → screen flips to upload-progress mode (aggregate counter + collapsible per-item list). Worker drains. Failed items return to the Failed section for retry.
4. On success, `assignments.submitted_at` gets stamped → app enters **Submitted ✓** state: home shows submission badge; map polygons are still tappable but the SubmissionDetailScreen renders read-only (no Done button, no field edits, no add-new pill).
5. If the assignment is closed remotely (Phase 4a's `closed_remotely=true` path), an **Assignment Closed** blocking screen overlays with a Share button to send the JSON+ZIP bundle (Phase 4a's `PendingWorkBundle`) out-of-band.

Phase 4a's debug long-press trigger is removed.

## 2. Scope

### In scope

- **Real auth wiring** — `submittedBy` finally takes the Supabase user id (Phase 4a Bug 1 fixed properly). Plumbed via a new `currentUserIdProvider` reading from `AuthState.Authenticated`.
- **`BiometricService`** — thin `local_auth` wrapper with `isSupported()` + `authenticate({reason})`. Includes `FakeBiometricService` test double. Powers the Upload Data gate only (Q2 = A; Get Maps gate deferred to Phase 5).
- **Review screen** at `/review` route. Composer + 5 sub-sections:
  - `_SummaryCard` (counts)
  - `_FailedJobsSection` (only when dead jobs > 0; per-row + Retry-all per Q5 = A)
  - `_ValidationSection` × 2 (blockers + warnings, grouped by feature, with "Go to feature" deep-links per spec §10)
  - `_StartUploadButton` (disabled when blockers exist or no work to upload)
  - `_UploadProgressSection` (replaces summary + start button while in-flight; aggregate counter + collapsible per-item list per Q4 = C)
- **Pure `ReviewValidator`** — aggregates per-submission validation across the assignment into `ReviewState`. Reuses Phase 2/3a/3b validators (`validateBuildingForm`, `validateRoadForm`, `validateOlpForFinalize`).
- **`StartUploadUseCase`** — finalizes all `ready_to_upload` submissions in the assignment (idempotent), then triggers the worker.
- **`RetryDeadUseCase`** — flips dead sync_jobs back to pending (resets attempts/lastError/nextRetryAt) and triggers the worker. `retryAll()` + `retryOne(jobId)`.
- **`UploadProgressController`** — StateNotifier subscribing to sync_jobs status stream. Computes `done/total` and emits `UploadProgress` (sealed: `Idle | InProgress | Completed | Locked`).
- **`SubmittedAssignmentLock`** — passive watcher; when all sync_jobs for the assignment are terminal-success, stamps `assignments.submitted_at = now`. Idempotent.
- **`AssignmentLockState`** sealed class + `assignmentLockStateProvider`: `Unlocked | Submitted(submittedAt) | ClosedRemotely(bundleFile)`.
- **Submitted-state read-only propagation** — small `if (locked)` guards in:
  - `home_screen.dart` (badge replaces progress card; Upload Data hidden)
  - `submission_detail_screen.dart` (sections `disabled: true`; Done hidden; photo strip hides + chip)
  - `map_screen.dart` (add-new pill greyed; long-press disabled)
- **`AssignmentClosedBlocker`** full-screen overlay with Share button via `share_plus`.
- **`go_router` redirect rule** — when `lockState is ClosedRemotely`, intercepts navigation with the blocker; when `Submitted`, allows but flags read-only.
- **Remove Phase 4a debug long-press trigger** from `home_screen.dart`.
- **i18n** — ~25 new ARB keys covering review screen UI, biometric reason text, submitted/closed labels, share action.

### Out of scope (Phase 5 polish)

- Get Maps biometric gate
- Stricter Storage RLS (per-user-owner)
- "Clear local data after submit"
- "Get new assignment" flow
- Photo bytes-level upload progress
- Read-only banner on OLP result screen
- Backfill of `submittedBy='admin'` rows
- Multi-device "submitted" sync
- Failed-jobs Sentry/crash reporting

### Out of scope forever (per master spec §15)

- Polygon/road reshape, real-time multi-enumerator collaboration, supervisor approval / messaging in-app, iOS background upload (v2).

## 3. Architecture

### 3.1 Module layout

```
lib/features/review/
├── domain/
│   ├── review_state.dart            # value class: summary + warnings + blockers + dead-jobs + UploadProgress
│   ├── review_validator.dart        # pure: buildReviewState(...)
│   └── upload_progress.dart         # sealed: Idle | InProgress | Completed | Locked
├── data/
│   └── review_repository.dart       # streams the data the validator needs
└── presentation/
    ├── review_screen.dart           # composer
    ├── review_providers.dart        # Riverpod wiring
    ├── upload_progress_controller.dart # StateNotifier
    ├── sections/
    │   ├── _summary_card.dart
    │   ├── _failed_jobs_section.dart
    │   ├── _validation_section.dart
    │   ├── _upload_progress_section.dart
    │   └── _start_upload_button.dart
    └── sub/
        ├── retry_dead_use_case.dart
        └── start_upload_use_case.dart

lib/core/auth/
├── biometric_service.dart           # abstract + LocalAuthBiometricService + FakeBiometricService
└── current_user_provider.dart       # exposes currentUserId from AuthState.Authenticated

lib/features/assignment/
├── data/
│   └── submitted_assignment_lock.dart  # watchAndStamp
└── presentation/
    ├── assignment_lock_state.dart      # sealed AssignmentLockState
    ├── assignment_lock_providers.dart  # assignmentLockStateProvider
    ├── assignment_closed_blocker.dart  # full-screen blocking overlay
    └── submitted_banner.dart           # "Submitted ✓ on YYYY-MM-DD" header
```

### 3.2 Modified files

- `lib/features/home/presentation/home_screen.dart` — Upload Data card wired to biometric → review; Submitted badge replaces progress card when locked; debug long-press REMOVED.
- `lib/features/survey/building_form/data/submission_repository.dart` — call sites no longer hardcode `'admin'`.
- `lib/features/survey/building_form/presentation/submission_detail_screen.dart` — read-only when locked.
- `lib/features/map/presentation/map_screen.dart` — add-new disabled when locked; debug long-press REMOVED.
- `lib/core/router/app_router.dart` — `/review` route + `redirect` rule for closed-remotely lock.
- `lib/core/i18n/app_en.arb` + `app_tl.arb` — ~25 new keys; regen `lib/generated/l10n/*`.
- `android/app/src/main/AndroidManifest.xml` — verify `USE_BIOMETRIC` + `USE_FINGERPRINT` perms; add if missing.

### 3.3 Reused infrastructure

- `SyncJobsRepository` (status streams), `SyncController.triggerNow()`, `FinalizeSubmissionUseCase`, `AssignmentLockRepository.lockStateStream` (Phase 4a), `PendingWorkBundle.exportFor()` (Phase 4a), `share_plus` (Phase 4a dep).
- `validateBuildingForm` / `validateRoadForm` / `validateOlpForFinalize` — composed by the new `ReviewValidator`.
- `AuthStateNotifier.state` — read for current Supabase user id.
- `local_auth: ^2.2.0` — already in pubspec.

### 3.4 Data flow

**Upload Data flow:**
```
Home: tap "Upload Data"
  → biometric.isSupported()
    → if !supported: navigate /review (school-project pragmatism)
    → else: biometric.authenticate(reason)
      → on true: navigate /review
      → on false: SnackBar "Biometric verification failed"

/review screen:
  → reviewStateProvider streams ReviewState
  → user reviews; if blockers: tap "Go to feature" → /feature/<id>
  → else tap Start Upload:
    → StartUploadUseCase.execute(assignmentId)
      → finalize each ready_to_upload submission
      → SyncController.triggerNow()
    → UploadProgressController switches Idle → InProgress(0, total)
    → sync_jobs status stream drives done/total updates
    → all terminal → Completed(failedCount)
    → if failedCount=0 → SubmittedAssignmentLock stamps submitted_at → Locked(submitted)
```

**Lock state propagation:**
```
assignmentLockStateProvider watches: assignments table + sync_jobs
  → emits Unlocked / Submitted(date) / ClosedRemotely(bundleFile)
  → consumed by home_screen, map_screen, submission_detail_screen, app_router redirect
```

## 4. Auth wiring (Bug 1 fix carryover)

`SubmissionRepository.ensureDraftForFeature({featureId, enumeratorId})` already accepts the user id. The fix is at call sites — they currently pass `'admin'`.

New helper: `lib/core/auth/current_user_provider.dart`:

```dart
final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth is Authenticated ? auth.userId : null;
});
```

Call sites updated:

| Call site | Change |
|---|---|
| `SubmissionDetailScreen._ensureFirst` | `enumeratorId: ref.read(currentUserIdProvider) ?? throw StateError('not authenticated')` |
| `SubmissionDetailScreen._addTab` | same |
| `MapScreen._handleFeatureTap` | same |
| `MapScreen._handleLongPress` | same |

The throw is acceptable: these call sites only fire after the auth-gated routes; if userId is null, that's a programming bug worth surfacing loudly.

Phase 4a's PayloadBuilder coercion of non-UUID `submittedBy` to null stays in place — handles legacy 'admin' rows + any future weirdness.

## 5. BiometricService

`lib/core/auth/biometric_service.dart`:

```dart
abstract class BiometricService {
  Future<bool> isSupported();
  Future<bool> authenticate({required String reason});
}

class LocalAuthBiometricService implements BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isSupported() async {
    final canCheck = await _auth.canCheckBiometrics;
    final supported = await _auth.isDeviceSupported();
    return canCheck && supported;
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,  // PIN/pattern fallback acceptable
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}

class FakeBiometricService implements BiometricService {
  FakeBiometricService({this.supported = true, this.willAuthenticate = true});
  final bool supported;
  final bool willAuthenticate;
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> authenticate({required String reason}) async => willAuthenticate;
}

final biometricServiceProvider =
    Provider<BiometricService>((ref) => LocalAuthBiometricService());
```

Gate at Home screen's Upload Data action:

```dart
onTap: () async {
  final biometric = ref.read(biometricServiceProvider);
  final supported = await biometric.isSupported();
  if (!supported) {
    if (context.mounted) context.go('/review');
    return;
  }
  final ok = await biometric.authenticate(
    reason: l.biometricGateReason,
  );
  if (!ok) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.biometricFailedSnackbar)),
      );
    }
    return;
  }
  if (context.mounted) context.go('/review');
}
```

Manifest: verify `USE_BIOMETRIC` + `USE_FINGERPRINT` perms exist (Phase 0 likely added them; if not, this task adds them).

## 6. ReviewState + ReviewValidator + ReviewRepository

### 6.1 `UploadProgress` sealed

```dart
sealed class UploadProgress { const UploadProgress(); }
class Idle extends UploadProgress { const Idle(); }
class InProgress extends UploadProgress {
  const InProgress({required this.done, required this.total});
  final int done;
  final int total;
}
class Completed extends UploadProgress {
  const Completed({required this.failedCount});
  final int failedCount;
}
class Locked extends UploadProgress {
  const Locked({required this.kind, this.submittedAt});
  final LockKind kind;
  final DateTime? submittedAt;
}
enum LockKind { submitted, closedRemotely }
```

### 6.2 `ReviewState`

```dart
class ReviewState {
  const ReviewState({
    required this.summary,
    required this.warnings,
    required this.blockers,
    required this.deadJobs,
    required this.upload,
  });
  final ReviewSummary summary;
  final List<ReviewIssue> warnings;
  final List<ReviewIssue> blockers;
  final List<DeadJobRow> deadJobs;
  final UploadProgress upload;

  bool get canStartUpload =>
      blockers.isEmpty && summary.completeFeatures > 0 && upload is Idle;
}

class ReviewSummary {
  const ReviewSummary({
    required this.totalFeatures,
    required this.completeFeatures,
    required this.incompleteFeatures,
    required this.newFeaturesAdded,
    required this.photosPending,
  });
}

class ReviewIssue {
  const ReviewIssue({
    required this.featureId,
    required this.featureLabel,
    required this.severity,
    required this.code,
    required this.messageKey,
  });
}

enum ReviewSeverity { blocker, warning }

class DeadJobRow {
  const DeadJobRow({
    required this.jobId,
    required this.entityType,
    required this.entityId,
    required this.attempts,
    required this.lastError,
  });
}
```

### 6.3 `ReviewValidator`

Pure function. Per spec §10:

**Blockers:**
- Feature has no submission OR all submissions are draft → `feature_has_no_finalized_submission`
- Submission complete but no photo → `photo_required`
- Building submission missing `ra_9514_type` → `ra_9514_type_required`
- Road submission with `width_meters ≤ 0` → `width_meters_required`

**Warnings:**
- Residential building (ra_9514_type ∈ {A, B}) without OLP `completed_at` → `olp_residential`
- `cost_is_exact=true` but `cost_amount` is null → `cost_amount_missing`

`does_not_exist=true` short-circuits all building/road blockers (matches existing `validateBuildingForm` / `validateRoadForm` behavior); photo is still required.

### 6.4 `ReviewRepository`

```dart
class ReviewRepository {
  ReviewRepository(this._db);
  final AppDatabase _db;

  /// Combined stream of all source data the validator needs.
  /// Re-emits whenever anything changes.
  Stream<ReviewSourceData> streamForCurrentAssignment(String assignmentId) {
    // Combine via rxdart-style helpers (or manually) the Drift watch streams
    // for: features, submissions, building_attributes, road_attributes,
    // household_surveys, photos, sync_jobs.
  }
}

class ReviewSourceData {
  // Packs all the rows into one snapshot.
}
```

A Riverpod `reviewStateProvider` watches this + the upload progress, runs `buildReviewState`, exposes the result.

## 7. UI: Review screen + sections

Layout described in design Section 5.1 (mockup). Key bits:

- **`_SummaryCard`** — single Card with 5 stat rows. No interactivity.
- **`_FailedJobsSection`** — `if (state.deadJobs.isNotEmpty)` Card with header + per-row `_DeadJobTile` + "Retry all" tonal button. `_DeadJobTile` has Retry icon button + expandable error details.
- **`_ValidationSection`** rendered twice: blockers (with red icon, hard-block label) + warnings (with amber icon, advisory label). Each row = expandable `_FeatureIssueGroup` showing the feature label + bulleted issues + "Go to feature →" `TextButton` calling `context.go('/feature/$featureId')`.
- **`_StartUploadButton`** — `FilledButton` with `Tooltip` if disabled. Disabled when `!state.canStartUpload`. Tapping calls `StartUploadUseCase.execute(assignmentId)`.
- **`_UploadProgressSection`** — replaces the start button + summary + validation when `state.upload is InProgress`. Top: `LinearProgressIndicator(value: done/total)` + label `"Uploading X of Y items..."`. Bottom: `ExpansionTile("Show details")` containing per-item rows with status icons.

`ReviewScreen` itself is a `ConsumerWidget` that watches `reviewStateProvider` and composes the sections via a `ListView`.

## 8. Submitted-state lock + Assignment-locked blocker

### 8.1 `SubmittedAssignmentLock`

```dart
class SubmittedAssignmentLock {
  SubmittedAssignmentLock(this._db);
  final AppDatabase _db;

  /// Watches sync_jobs + submissions; when every submission for the
  /// assignment has sync_status='uploaded' AND no sync_jobs remain in
  /// {pending, in_progress, dead}, stamps assignments.submitted_at = now.
  /// Idempotent — won't re-stamp if already set.
  Stream<void> watchAndStamp(String assignmentId) async* {
    await for (final _ in _db
        .customSelect('SELECT 1', readsFrom: {_db.submissions, _db.syncJobs})
        .watch()) {
      final shouldStamp = await _shouldStampNow(assignmentId);
      if (shouldStamp) {
        await (_db.update(_db.assignments)
              ..where((t) => t.id.equals(assignmentId)))
            .write(AssignmentsCompanion(submittedAt: Value(DateTime.now())));
      }
      yield null;
    }
  }

  Future<bool> _shouldStampNow(String assignmentId) async {
    final assignment = await (_db.select(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    if (assignment == null || assignment.submittedAt != null) return false;
    // Counts ANY sync_job (submission, photo, feature) whose entity belongs
    // transitively to this assignment AND is still in a non-terminal or
    // dead state. Submission jobs alone aren't enough — a stuck photo job
    // would silently allow stamping otherwise.
    final activeJobs = await _db.customSelect(
      '''
      SELECT count(*) as c FROM sync_jobs j
      WHERE j.status IN ('pending', 'in_progress', 'dead')
      AND (
        (j.entity_type = 'submission' AND j.entity_id IN (
          SELECT s.id FROM submissions s
          JOIN features f ON f.id = s.feature_id
          WHERE f.assignment_id = ?
        ))
        OR (j.entity_type = 'photo' AND j.entity_id IN (
          SELECT p.id FROM photos p
          JOIN submissions s ON s.id = p.submission_id
          JOIN features f ON f.id = s.feature_id
          WHERE f.assignment_id = ?
        ))
        OR (j.entity_type = 'feature' AND j.entity_id IN (
          SELECT id FROM features WHERE assignment_id = ?
        ))
      )
      ''',
      variables: [
        Variable.withString(assignmentId),
        Variable.withString(assignmentId),
        Variable.withString(assignmentId),
      ],
    ).getSingle();
    return (activeJobs.read<int>('c')) == 0;
  }
}
```

Wired as a Riverpod listener that starts on app launch (alongside SyncController). Listens forever; auto-stamps when the conditions match.

### 8.2 `AssignmentLockState` + provider

```dart
sealed class AssignmentLockState { const AssignmentLockState(); }
class Unlocked extends AssignmentLockState { const Unlocked(); }
class Submitted extends AssignmentLockState {
  const Submitted({required this.submittedAt});
  final DateTime submittedAt;
}
class ClosedRemotely extends AssignmentLockState {
  const ClosedRemotely({required this.bundleFile});
  final File? bundleFile;  // may be null briefly while bundle is generating
}

final assignmentLockStateProvider =
    StreamProvider<AssignmentLockState>((ref) async* {
  // Combine: assignments row stream (submitted_at, closed_remotely)
  //          + Phase 4a's PendingWorkBundle file path (for closed_remotely case)
});
```

### 8.3 Read-only mode propagation

| Consumer | Behavior when locked |
|---|---|
| `home_screen.dart` | Replaces Assignment progress card with `SubmittedBanner`. Hides Upload Data action. Removes Phase 4a debug long-press regardless. |
| `submission_detail_screen.dart` | Sets `disabled: true` on all sections; hides Done button; hides photo-strip "+ Photo" chip; OLP "Mark Complete" button hidden. |
| `map_screen.dart` | "+ New Feature" pill greyed (long-press disabled). Polygon taps still navigate. |

### 8.4 `AssignmentClosedBlocker`

Full-screen overlay rendered when `assignmentLockStateProvider` emits `ClosedRemotely`. Wired via go_router redirect (whenever location is anything except `/login` AND lock is `ClosedRemotely`, redirect to `/blocker`):

```dart
class AssignmentClosedBlocker extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final lock = ref.watch(assignmentLockStateProvider).value;
    if (lock is! ClosedRemotely) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: Color(0xFFC53030)),
                const SizedBox(height: 12),
                Text(l.assignmentClosedTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
                const SizedBox(height: 8),
                Text(l.assignmentClosedBody, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (lock.bundleFile != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.share),
                    label: Text(l.shareBundleAction),
                    onPressed: () async {
                      await Share.shareXFiles([XFile(lock.bundleFile!.path)]);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

## 9. i18n additions

~25 new ARB keys in en + tl:

- `submittedBadge`, `submittedAt(date)`, `readOnlyBanner`
- `uploadDataAction`, `biometricGateReason`, `biometricFailedSnackbar`
- `reviewTitle`
- `summaryFeatures(n)`, `summaryComplete(n)`, `summaryIncomplete(n)`, `summaryNewFeatures(n)`, `summaryPhotosPending(n)`
- `failedJobsTitle(n)`, `retryButton`, `retryAllButton`, `showDetailsToggle`
- `validationBlockersTitle(n)`, `validationWarningsTitle(n)`, `goToFeature`
- `startUploadButton`, `startUploadDisabledTooltip`
- `uploadProgressLabel(done, total)`, `uploadProgressShowDetails`, `uploadCompleteSuccess(n)`, `uploadCompleteWithFailures(n)`
- `assignmentClosedTitle`, `assignmentClosedBody`, `shareBundleAction`
- Issue messages: `issuePhotoRequired`, `issueRa9514Required`, `issueWidthRequired`, `issueOlpResidential`, `issueCostAmountMissing`, `issueFeatureNoSubmission`

## 10. Testing strategy

### 10.1 Unit tests

- `ReviewValidator.buildReviewState` boundaries: empty assignment, all-complete, photo-missing blocker, ra_9514_type-missing blocker, width-zero blocker, residential-without-OLP warning, cost-amount-missing warning, does_not_exist short-circuit, dead-jobs surfacing, lock-state propagation.
- `UploadProgress` + `AssignmentLockState` sealed equality + sub-type identity.

### 10.2 Repository / use-case tests (NativeDatabase.memory + FK chain)

- `ReviewRepository.streamForCurrentAssignment` re-emits on each table change.
- `StartUploadUseCase.execute` — finalizes only `ready_to_upload`; idempotent; returns count.
- `RetryDeadUseCase.retryAll` and `retryOne` — flip dead → pending, reset attempts/error/retry_at, trigger controller.
- `SubmittedAssignmentLock.watchAndStamp` — stamps when all jobs success; idempotent on already-stamped; doesn't stamp with pending/in_progress/dead jobs.
- `BiometricService` test with `FakeBiometricService` doubles.
- `currentUserIdProvider` returns userId for Authenticated, null for Unauthenticated.

### 10.3 Widget tests (AppDatabase-inside-testWidgets-body)

- `_SummaryCard` renders all 5 stats.
- `_FailedJobsSection` hidden when no dead jobs; shown when ≥1; "Retry all" calls use case.
- `_ValidationSection` groups by feature; "Go to feature" link works.
- `_StartUploadButton` disabled with blockers; enabled without.
- `_UploadProgressSection` renders correct fraction; collapsible expands/collapses.
- `ReviewScreen` integration (seed fixture → assert all sections).
- `AssignmentClosedBlocker` shown when lock = ClosedRemotely; Share button triggers share sheet (mocked).
- `SubmissionDetailScreen` read-only mode when locked.
- `home_screen.dart`: Upload Data tap → biometric → on success navigates `/review`; on failure SnackBar.

### 10.4 Integration test

Seed a 2-feature assignment with 2 ready_to_upload submissions (one with photo, one with does_not_exist=true + photo). Open `/review` → no blockers → tap Start Upload → FakeSyncApi succeeds → progress fills → Completed(0) → submitted_at gets stamped → screen flips to Locked(submitted) banner.

### 10.5 Acceptance gate

- `flutter analyze` clean
- `flutter test` ≥ 280 passing (Phase 4a: 240; Phase 4b adds ~40-50)
- `flutter build apk --debug` succeeds
- Manual happy path on Pixel 7 emulator (full Flow F: survey → Done → Upload Data → biometric → review → Start → progress → Locked).
- Tag `phase-4b-upload-flow` (push remains user-gated).

## 11. Conventions reused

- Drift codegen via `dart run build_runner build --delete-conflicting-outputs`.
- Riverpod 2.5 with `Provider`, `StateNotifierProvider.autoDispose.family`, `StreamProvider`.
- Sealed classes for state machines (`UploadProgress`, `AssignmentLockState`).
- `very_good_analysis` lint set; project-wide overrides preserved.
- `subagent-driven-development` for plan execution.
- AppDatabase-inside-testWidgets-body for widget tests.
- FK chain test seeding (assignments → features → submissions → photos → sync_jobs).
- `submittedBy` (NOT `enumeratorId`) on `SubmissionsCompanion.insert`.
- No automatic push; tag at the final task; user pushes manually.

## 12. Risks documented

- **Multi-device race on submit** — both devices can call StartUpload concurrently; `upload_submission_bundle` RPC is idempotent (upsert-on-conflict), but `submitted_at` may get stamped twice. Acceptable; second-stamp wins.
- **Biometric prompt cancellation** — treated as failure with a SnackBar; password fallback per master spec §10 lands in Phase 5.
- **Submitted-state read-only is client-only** — server still accepts upserts. If a user bypasses the lock, the server overwrites cleanly. Acceptable.
- **`go_router redirect` for closed-remotely** — assumes the lock state is read on every navigation; if the user is currently on a route when `closed_remotely` flips, the redirect fires on next navigation, not immediately. For 4b we accept this; Phase 5 polish can add a global listener that pops to the blocker route immediately.

## 13. Open items / Phase 5 dependencies

- Wire `BiometricService` into Get Maps too.
- Add OEM-aware WorkManager fallback or document caveats in user-facing help.
- Cross-isolate Drift sharing for the WorkManager dispatcher.
- Real auth-user-scoped Storage RLS for the `photos` bucket.
- Backfill of legacy `submittedBy='admin'` rows (one-time migration).
- Multi-device "submitted" sync (poll Supabase on app launch, surface server-side state).
- Failed-jobs Sentry/crash reporting.
