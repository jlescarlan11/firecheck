# FireCheck Mobile — Phase 4b (Upload Data flow) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Phase 4a debug long-press trigger with the proper Upload Data flow per master spec §8 Flow F: biometric gate → Review screen (summary + blockers + warnings + failed jobs) → Start Upload → per-item progress → Submitted banner. Wire real `submittedBy` from `AuthState.Authenticated`. Render read-only across home/detail/map when locked, plus a full-screen `AssignmentClosedBlocker` for the closed-remotely path with `Share` of the Phase 4a bundle.

**Architecture:** New `lib/features/review/` module split into `domain/` (pure value classes + validator), `data/` (combined source-data stream), `presentation/` (screen + sectioned widgets + use cases + StateNotifier). New `lib/features/assignment/data/submitted_assignment_lock.dart` watches sync_jobs and stamps `assignments.submitted_at` when all jobs for the assignment reach terminal-success. New `lib/features/assignment/presentation/assignment_lock_state.dart` (sealed: Unlocked | Submitted | ClosedRemotely) is consumed by home/detail/map for read-only propagation and by go_router for the ClosedRemotely redirect. Reuses Phase 4a's `BiometricGate`, `SyncController.triggerNow`, `SyncJobsRepository`, `FinalizeSubmissionUseCase`, `AssignmentLockRepository.lockStateStream`, and `PendingWorkBundle.exportFor`.

**Tech Stack additions:** None. `local_auth: ^2.2.0` already in pubspec; `share_plus` already in pubspec from Phase 4a; `USE_BIOMETRIC`/`USE_FINGERPRINT` already in `AndroidManifest.xml`. No schema bump (`assignments.submitted_at` from Phase 0; `assignments.closed_remotely` from Phase 4a).

**Phase 4b demo state:** Login → survey a building (with photo) → tap Done → repeat for all assignment features → tap Upload Data → biometric prompt → /review screen lists summary + zero blockers → tap Start Upload → progress bar fills → assignment shows "Submitted ✓ on YYYY-MM-DD" badge on Home; the SubmissionDetailScreen renders read-only with no Done button. Force-flip `assignments.closed_remotely=true` in Supabase → next worker drain raises 409 → `AssignmentLockRepository.markClosed` runs → `AssignmentClosedBlocker` overlays the app with a "Share" button that exports the Phase 4a JSON+ZIP bundle.

---

## File structure (Phase 4b)

### New files

```
lib/core/auth/current_user_provider.dart
lib/core/security/biometric_gate_provider.dart

lib/features/review/domain/upload_progress.dart
lib/features/review/domain/review_state.dart
lib/features/review/domain/review_validator.dart
lib/features/review/data/review_repository.dart
lib/features/review/presentation/review_providers.dart
lib/features/review/presentation/upload_progress_controller.dart
lib/features/review/presentation/review_screen.dart
lib/features/review/presentation/sections/summary_card.dart
lib/features/review/presentation/sections/failed_jobs_section.dart
lib/features/review/presentation/sections/validation_section.dart
lib/features/review/presentation/sections/start_upload_button.dart
lib/features/review/presentation/sections/upload_progress_section.dart
lib/features/review/presentation/sub/retry_dead_use_case.dart
lib/features/review/presentation/sub/start_upload_use_case.dart

lib/features/assignment/data/submitted_assignment_lock.dart
lib/features/assignment/presentation/assignment_lock_state.dart
lib/features/assignment/presentation/assignment_lock_providers.dart
lib/features/assignment/presentation/assignment_closed_blocker.dart
lib/features/assignment/presentation/submitted_banner.dart
```

### Modified files

```
lib/features/survey/building_form/presentation/submission_detail_screen.dart   # currentUserId + read-only
lib/features/map/presentation/map_screen.dart                                  # currentUserId + read-only add-mode
lib/features/home/presentation/home_screen.dart                                # Upload Data wired; long-press removed; Submitted banner
lib/core/router/app_router.dart                                                # /review route + ClosedRemotely redirect
lib/core/i18n/app_en.arb                                                       # +25 keys
lib/core/i18n/app_tl.arb                                                       # +25 keys (parity)
lib/main.dart                                                                  # SubmittedAssignmentLock listener
```

### New test files

```
test/core/auth/current_user_provider_test.dart
test/features/review/domain/review_validator_test.dart
test/features/review/data/review_repository_test.dart
test/features/review/presentation/sub/retry_dead_use_case_test.dart
test/features/review/presentation/sub/start_upload_use_case_test.dart
test/features/review/presentation/upload_progress_controller_test.dart
test/features/review/presentation/sections/summary_card_test.dart
test/features/review/presentation/sections/failed_jobs_section_test.dart
test/features/review/presentation/sections/validation_section_test.dart
test/features/review/presentation/sections/start_upload_button_test.dart
test/features/review/presentation/sections/upload_progress_section_test.dart
test/features/review/presentation/review_screen_test.dart
test/features/assignment/submitted_assignment_lock_test.dart
test/features/assignment/assignment_lock_state_test.dart
test/features/assignment/assignment_closed_blocker_test.dart
test/features/home/home_screen_upload_data_test.dart
test/features/survey/submission_detail_read_only_test.dart
test/integration/review_happy_path_test.dart
```

---

### Task 1: `currentUserIdProvider` — read userId from `AuthState.Authenticated`

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/auth/current_user_provider.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/auth/current_user_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAuthNotifier extends StateNotifier<AuthState> {
  _StubAuthNotifier(super.state);
}

void main() {
  test('returns userId for Authenticated', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _StubAuthNotifier(
            const Authenticated(userId: 'u-123', email: 'a@b.c'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(currentUserIdProvider), 'u-123');
  });

  test('returns null for Unauthenticated', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _StubAuthNotifier(const Unauthenticated()),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(currentUserIdProvider), isNull);
  });

  test('returns null for AuthChecking', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _StubAuthNotifier(const AuthChecking()),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(currentUserIdProvider), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/auth/current_user_provider_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: 'package:firecheck/core/auth/current_user_provider.dart'`.

- [ ] **Step 3: Implement the provider**

```dart
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the current Supabase user id, or null when not authenticated.
/// Replaces the Phase 4a `'admin'` placeholder at submission call sites.
final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth is Authenticated ? auth.userId : null;
});
```

- [ ] **Step 4: Run tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/auth/current_user_provider_test.dart
```

Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/auth/current_user_provider.dart test/core/auth/current_user_provider_test.dart && git commit -m "feat(auth): currentUserIdProvider exposes Authenticated.userId"
```

---

### Task 2: Replace `'admin'` placeholders with `currentUserIdProvider`

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/building_form/presentation/submission_detail_screen.dart`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/map/presentation/map_screen.dart`

- [ ] **Step 1: Add import to `submission_detail_screen.dart`**

Add this import line alongside the others at the top:

```dart
import 'package:firecheck/core/auth/current_user_provider.dart';
```

- [ ] **Step 2: Replace `'admin'` in `_ensureFirst` (lines 59-65)**

Change:

```dart
Future<void> _ensureFirst() async {
  final repo = ref.read(submissionRepositoryProvider);
  await repo.ensureDraftForFeature(
    featureId: widget.featureId,
    enumeratorId: 'admin', // Phase 4 will wire real auth
  );
}
```

To:

```dart
Future<void> _ensureFirst() async {
  final repo = ref.read(submissionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) {
    throw StateError('SubmissionDetailScreen reached without an authenticated user');
  }
  await repo.ensureDraftForFeature(
    featureId: widget.featureId,
    enumeratorId: userId,
  );
}
```

- [ ] **Step 3: Replace `'admin'` in `_addTab` (lines 67-76)**

Change:

```dart
Future<void> _addTab() async {
  final repo = ref.read(submissionRepositoryProvider);
  await repo.createAdditionalSubmission(
    featureId: widget.featureId,
    enumeratorId: 'admin',
  );
  final submissions =
      await repo.watchSubmissionsForFeature(widget.featureId).first;
  if (mounted) setState(() => _activeIndex = submissions.length - 1);
}
```

To:

```dart
Future<void> _addTab() async {
  final repo = ref.read(submissionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) {
    throw StateError('SubmissionDetailScreen._addTab without authenticated user');
  }
  await repo.createAdditionalSubmission(
    featureId: widget.featureId,
    enumeratorId: userId,
  );
  final submissions =
      await repo.watchSubmissionsForFeature(widget.featureId).first;
  if (mounted) setState(() => _activeIndex = submissions.length - 1);
}
```

- [ ] **Step 4: Add import to `map_screen.dart` and replace `'admin'`**

Add import:

```dart
import 'package:firecheck/core/auth/current_user_provider.dart';
```

Then in `_handleFeatureTap` (around lines 183-187), change:

```dart
final submissionRepo = ref.read(submissionRepositoryProvider);
final submission = await submissionRepo.ensureDraftForFeature(
  featureId: f.id,
  enumeratorId: 'admin',
);
```

To:

```dart
final submissionRepo = ref.read(submissionRepositoryProvider);
final userId = ref.read(currentUserIdProvider);
if (userId == null) {
  throw StateError('Map tap without authenticated user');
}
final submission = await submissionRepo.ensureDraftForFeature(
  featureId: f.id,
  enumeratorId: userId,
);
```

- [ ] **Step 5: Update existing tests that override `currentUserIdProvider`**

Run the full suite to confirm no regression on existing widget tests that now route through the provider (they should still pass because the auth-gated routes prevent the StateError in production):

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test
```

Expected: ≥ 240 passing (Phase 4a baseline). If `submission_detail_screen` widget tests fail with `StateError`, override `currentUserIdProvider` in their `ProviderScope`:

```dart
overrides: [
  currentUserIdProvider.overrideWith((ref) => 'test-user-id'),
],
```

Add this override to the failing tests' `ProviderScope` (or `ProviderContainer`).

- [ ] **Step 6: Verify no `'admin'` left in active code paths**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && grep -rn "'admin'" lib/ --include="*.dart"
```

Expected: only the comment line in `lib/core/sync/data/submission_payload_builder.dart` (line ~47, explaining the legacy coercion) remains. No active call sites.

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/building_form/presentation/submission_detail_screen.dart lib/features/map/presentation/map_screen.dart test/ && git commit -m "feat(auth): wire real submittedBy via currentUserIdProvider"
```

---

### Task 3: `BiometricGate` Riverpod provider

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/security/biometric_gate_provider.dart`

The existing `BiometricGate` (Phase 0) already implements `isAvailable()` + `authenticate({reason})`. We only need a Riverpod handle so widget tests can override with a fake.

- [ ] **Step 1: Implement provider**

```dart
import 'package:firecheck/core/security/biometric_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod handle on the singleton [BiometricGate]. Widget tests override
/// this with a `_FakeBiometricGate` (subclass returning fixed values) to
/// drive the Upload Data tap → biometric → navigate flow.
final biometricGateProvider = Provider<BiometricGate>((_) => BiometricGate());
```

- [ ] **Step 2: Verify `flutter analyze` clean**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/security/biometric_gate_provider.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/security/biometric_gate_provider.dart && git commit -m "feat(security): expose BiometricGate via Riverpod"
```

---

### Task 4: `UploadProgress` sealed class

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/domain/upload_progress.dart`
- Test: in Task 7 (covered together with `ReviewState`)

- [ ] **Step 1: Implement**

```dart
/// Drives the Review screen's render mode.
///
/// Idle             → show summary + validation + start button
/// InProgress       → swap to progress bar + collapsible per-item list
/// Completed        → success snackbar + transition to Locked (if 0 failed)
///                    or stay on Failed Jobs section (if >0 failed)
/// Locked           → screen unmounts; consumer routes back to Home
sealed class UploadProgress {
  const UploadProgress();
}

class Idle extends UploadProgress {
  const Idle();
}

class InProgress extends UploadProgress {
  const InProgress({required this.done, required this.total});
  final int done;
  final int total;

  @override
  bool operator ==(Object other) =>
      other is InProgress && other.done == done && other.total == total;
  @override
  int get hashCode => Object.hash(done, total);
}

class Completed extends UploadProgress {
  const Completed({required this.failedCount});
  final int failedCount;

  @override
  bool operator ==(Object other) =>
      other is Completed && other.failedCount == failedCount;
  @override
  int get hashCode => failedCount.hashCode;
}

class Locked extends UploadProgress {
  const Locked({required this.kind, this.submittedAt});
  final LockKind kind;
  final DateTime? submittedAt;

  @override
  bool operator ==(Object other) =>
      other is Locked && other.kind == kind && other.submittedAt == submittedAt;
  @override
  int get hashCode => Object.hash(kind, submittedAt);
}

enum LockKind { submitted, closedRemotely }
```

- [ ] **Step 2: Verify analyze clean**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/review/domain/upload_progress.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/domain/upload_progress.dart && git commit -m "feat(review): UploadProgress sealed (Idle|InProgress|Completed|Locked)"
```

---

### Task 5: `ReviewState` + supporting value classes

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/domain/review_state.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:firecheck/features/review/domain/upload_progress.dart';

/// Snapshot of everything the Review screen renders.
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

  /// Start Upload is enabled when:
  ///  - no blockers
  ///  - at least one complete-or-skipped feature to upload
  ///  - we're idle (not mid-upload)
  bool get canStartUpload =>
      blockers.isEmpty &&
      summary.completeFeatures > 0 &&
      upload is Idle;
}

class ReviewSummary {
  const ReviewSummary({
    required this.totalFeatures,
    required this.completeFeatures,
    required this.incompleteFeatures,
    required this.newFeaturesAdded,
    required this.photosPending,
  });

  final int totalFeatures;
  final int completeFeatures;
  final int incompleteFeatures;
  final int newFeaturesAdded;
  final int photosPending;

  @override
  bool operator ==(Object other) =>
      other is ReviewSummary &&
      other.totalFeatures == totalFeatures &&
      other.completeFeatures == completeFeatures &&
      other.incompleteFeatures == incompleteFeatures &&
      other.newFeaturesAdded == newFeaturesAdded &&
      other.photosPending == photosPending;

  @override
  int get hashCode => Object.hash(
        totalFeatures,
        completeFeatures,
        incompleteFeatures,
        newFeaturesAdded,
        photosPending,
      );
}

enum ReviewSeverity { blocker, warning }

class ReviewIssue {
  const ReviewIssue({
    required this.featureId,
    required this.featureLabel,
    required this.severity,
    required this.code,
    required this.messageKey,
  });

  final String featureId;
  final String featureLabel;
  final ReviewSeverity severity;

  /// Stable identifier for the rule (e.g. `photo_required`, `ra_9514_type_required`).
  /// Used for grouping + analytics. NOT shown to the user.
  final String code;

  /// ARB key for the user-facing message (e.g. `issuePhotoRequired`).
  final String messageKey;
}

class DeadJobRow {
  const DeadJobRow({
    required this.jobId,
    required this.entityType,
    required this.entityId,
    required this.attempts,
    required this.lastError,
  });

  final String jobId;
  final String entityType;
  final String entityId;
  final int attempts;
  final String lastError;
}
```

- [ ] **Step 2: Verify analyze clean**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/review/domain/review_state.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/domain/review_state.dart && git commit -m "feat(review): ReviewState + ReviewSummary + ReviewIssue + DeadJobRow"
```

---

### Task 6: `ReviewValidator` — pure function

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/domain/review_validator.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/domain/review_validator_test.dart`

**Spec rules (master spec §10):**
- **Blockers:** feature has zero finalized submissions; complete submission with no photo; building missing `ra_9514_type`; road with `width_meters ≤ 0`.
- **Warnings:** residential building (ra_9514_type ∈ {A, B}) without OLP `completed_at`; `cost_is_exact=true` but `cost_amount` is null.
- `does_not_exist=true` short-circuits all building/road blockers; photo is still required.

`ReviewSourceData` (defined in Task 7's repository) packs every row the validator needs into one snapshot.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/review_validator.dart';
import 'package:flutter_test/flutter_test.dart';

Feature _building(String id) => Feature(
      id: id,
      assignmentId: 'a-1',
      featureType: 'building',
      geometryGeojson: '{}',
      isNew: false,
      createdAt: DateTime(2026, 4, 27),
    );

Feature _road(String id) => Feature(
      id: id,
      assignmentId: 'a-1',
      featureType: 'road',
      geometryGeojson: '{}',
      isNew: false,
      createdAt: DateTime(2026, 4, 27),
    );

Submission _sub(String id, String featureId, {
  String syncStatus = 'ready_to_upload',
  bool doesNotExist = false,
}) =>
    Submission(
      id: id,
      featureId: featureId,
      submittedBy: 'u-1',
      doesNotExist: doesNotExist,
      remarks: null,
      syncStatus: syncStatus,
      overrideReason: null,
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

BuildingAttribute _bldg(String submissionId, {
  String? ra9514Type,
  bool costIsExact = false,
  double? costAmount,
  String? costEstimateRange,
}) =>
    BuildingAttribute(
      submissionId: submissionId,
      cbmsId: null,
      buildingName: 'name',
      ra9514Type: ra9514Type,
      storeys: 1,
      material: 'concrete',
      costIsExact: costIsExact,
      costAmount: costAmount,
      costEstimateRange: costEstimateRange,
      fireFightingFacilitiesJson: '[]',
      fireLoadJson: '[]',
    );

RoadAttribute _roadAttrs(String submissionId, {double? widthMeters}) =>
    RoadAttribute(
      submissionId: submissionId,
      isBridge: false,
      roadName: 'Main',
      widthMeters: widthMeters,
      roadFeaturesJson: '[]',
      othersDescription: null,
    );

void main() {
  test('empty assignment → 0 features, 0 issues, no upload', () {
    final state = buildReviewState(
      const ReviewSourceData(
        features: [],
        submissions: [],
        buildingAttrs: [],
        roadAttrs: [],
        householdSurveys: [],
        photoCountsBySubmission: {},
        deadJobs: [],
      ),
    );
    expect(state.summary.totalFeatures, 0);
    expect(state.blockers, isEmpty);
    expect(state.warnings, isEmpty);
    expect(state.canStartUpload, isFalse);
  });

  test('feature with no submission → blocker feature_has_no_finalized_submission', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: const [],
        buildingAttrs: const [],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {},
        deadJobs: const [],
      ),
    );
    expect(
      state.blockers.map((b) => b.code),
      contains('feature_has_no_finalized_submission'),
    );
  });

  test('complete building with no photo → photo_required blocker', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: 'C')],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 0},
        deadJobs: const [],
      ),
    );
    expect(
      state.blockers.map((b) => b.code),
      contains('photo_required'),
    );
  });

  test('building missing ra_9514_type → blocker', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: null)],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(
      state.blockers.map((b) => b.code),
      contains('ra_9514_type_required'),
    );
  });

  test('road with width=0 → width_meters_required blocker', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_road('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: const [],
        roadAttrs: [_roadAttrs('s-1', widthMeters: 0)],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(
      state.blockers.map((b) => b.code),
      contains('width_meters_required'),
    );
  });

  test('residential building (type A) with no OLP → warning olp_residential', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: 'A')],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(
      state.warnings.map((w) => w.code),
      contains('olp_residential'),
    );
  });

  test('cost_is_exact=true with null cost_amount → warning cost_amount_missing', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: 'C', costIsExact: true)],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(
      state.warnings.map((w) => w.code),
      contains('cost_amount_missing'),
    );
  });

  test('does_not_exist=true short-circuits ra_9514_type/width blockers but keeps photo blocker', () {
    final stateBuilding = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1', doesNotExist: true)],
        buildingAttrs: [_bldg('s-1', ra9514Type: null)],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 0},
        deadJobs: const [],
      ),
    );
    expect(
      stateBuilding.blockers.map((b) => b.code),
      isNot(contains('ra_9514_type_required')),
    );
    expect(
      stateBuilding.blockers.map((b) => b.code),
      contains('photo_required'),
    );
  });

  test('dead jobs surface as DeadJobRow rows', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: const [],
        submissions: const [],
        buildingAttrs: const [],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {},
        deadJobs: const [
          DeadJobRow(
            jobId: 'j-1',
            entityType: 'photo',
            entityId: 'p-1',
            attempts: 5,
            lastError: 'Network error',
          ),
        ],
      ),
    );
    expect(state.deadJobs, hasLength(1));
    expect(state.deadJobs.first.jobId, 'j-1');
  });

  test('summary counts: 2 features, 1 complete (with photo), 1 incomplete', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1'), _building('f-2')],
        submissions: [
          _sub('s-1', 'f-1'),
          _sub('s-2', 'f-2'),
        ],
        buildingAttrs: [
          _bldg('s-1', ra9514Type: 'C'),
          _bldg('s-2', ra9514Type: null),
        ],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1, 's-2': 0},
        deadJobs: const [],
      ),
    );
    expect(state.summary.totalFeatures, 2);
    expect(state.summary.completeFeatures, 1);
    expect(state.summary.incompleteFeatures, 1);
    expect(state.summary.photosPending, 1);
  });

  test('canStartUpload=true when no blockers and at least 1 complete', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: 'C')],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(state.canStartUpload, isTrue);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/domain/review_validator_test.dart
```

Expected: FAIL with `Target of URI doesn't exist`.

- [ ] **Step 3: Implement `buildReviewState`**

```dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';

/// Pure validator: takes a snapshot of source rows and produces ReviewState.
///
/// Per master spec §10. Treats `does_not_exist=true` as the existing
/// validateBuildingForm/validateRoadForm do — short-circuits content
/// blockers, but photo is always required.
ReviewState buildReviewState(ReviewSourceData data) {
  final blockers = <ReviewIssue>[];
  final warnings = <ReviewIssue>[];

  final submissionsByFeature = <String, List<Submission>>{};
  for (final s in data.submissions) {
    submissionsByFeature.putIfAbsent(s.featureId, () => []).add(s);
  }
  final buildingBySub = {for (final b in data.buildingAttrs) b.submissionId: b};
  final roadBySub = {for (final r in data.roadAttrs) r.submissionId: r};
  final householdBySub = {
    for (final h in data.householdSurveys) h.submissionId: h,
  };

  var completeFeatures = 0;
  var incompleteFeatures = 0;
  var newFeaturesAdded = 0;
  var photosPending = 0;

  bool _isFinalized(Submission s) =>
      s.syncStatus == 'ready_to_upload' ||
      s.syncStatus == 'queued' ||
      s.syncStatus == 'uploaded';

  for (final f in data.features) {
    if (f.isNew) newFeaturesAdded++;
    final subs = submissionsByFeature[f.id] ?? const <Submission>[];
    final finalized = subs.where(_isFinalized).toList();
    if (finalized.isEmpty) {
      incompleteFeatures++;
      blockers.add(ReviewIssue(
        featureId: f.id,
        featureLabel: _featureLabel(f),
        severity: ReviewSeverity.blocker,
        code: 'feature_has_no_finalized_submission',
        messageKey: 'issueFeatureNoSubmission',
      ));
      continue;
    }
    var anyComplete = false;
    for (final sub in finalized) {
      final photoCount = data.photoCountsBySubmission[sub.id] ?? 0;
      var subBlockers = 0;

      if (photoCount < 1) {
        subBlockers++;
        photosPending++;
        blockers.add(ReviewIssue(
          featureId: f.id,
          featureLabel: _featureLabel(f),
          severity: ReviewSeverity.blocker,
          code: 'photo_required',
          messageKey: 'issuePhotoRequired',
        ));
      }

      if (!sub.doesNotExist) {
        if (f.featureType == 'building') {
          final b = buildingBySub[sub.id];
          if (b == null || b.ra9514Type == null) {
            subBlockers++;
            blockers.add(ReviewIssue(
              featureId: f.id,
              featureLabel: _featureLabel(f),
              severity: ReviewSeverity.blocker,
              code: 'ra_9514_type_required',
              messageKey: 'issueRa9514Required',
            ));
          } else {
            // Warning: residential without OLP.
            final isResidential = b.ra9514Type == 'A' || b.ra9514Type == 'B';
            final olp = householdBySub[sub.id];
            if (isResidential && (olp == null || olp.completedAt == null)) {
              warnings.add(ReviewIssue(
                featureId: f.id,
                featureLabel: _featureLabel(f),
                severity: ReviewSeverity.warning,
                code: 'olp_residential',
                messageKey: 'issueOlpResidential',
              ));
            }
            // Warning: cost_is_exact but no amount.
            if (b.costIsExact && (b.costAmount == null)) {
              warnings.add(ReviewIssue(
                featureId: f.id,
                featureLabel: _featureLabel(f),
                severity: ReviewSeverity.warning,
                code: 'cost_amount_missing',
                messageKey: 'issueCostAmountMissing',
              ));
            }
          }
        } else if (f.featureType == 'road') {
          final r = roadBySub[sub.id];
          if (r == null || (r.widthMeters ?? 0) <= 0) {
            subBlockers++;
            blockers.add(ReviewIssue(
              featureId: f.id,
              featureLabel: _featureLabel(f),
              severity: ReviewSeverity.blocker,
              code: 'width_meters_required',
              messageKey: 'issueWidthRequired',
            ));
          }
        }
      }

      if (subBlockers == 0) anyComplete = true;
    }
    if (anyComplete) {
      completeFeatures++;
    } else {
      incompleteFeatures++;
    }
  }

  final summary = ReviewSummary(
    totalFeatures: data.features.length,
    completeFeatures: completeFeatures,
    incompleteFeatures: incompleteFeatures,
    newFeaturesAdded: newFeaturesAdded,
    photosPending: photosPending,
  );

  return ReviewState(
    summary: summary,
    warnings: warnings,
    blockers: blockers,
    deadJobs: data.deadJobs,
    upload: const Idle(),
  );
}

String _featureLabel(Feature f) {
  // Short, stable label for grouping. Detail screen owns the friendly name.
  return '${f.featureType[0].toUpperCase()}${f.featureType.substring(1)} ${f.id.substring(0, 6)}';
}
```

- [ ] **Step 4: Stub `ReviewSourceData` so the validator file compiles**

The repository file (Task 7) defines `ReviewSourceData` properly. For now create the stub so this task's tests compile:

```dart
// lib/features/review/data/review_repository.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/domain/review_state.dart';

/// Snapshot the validator consumes. Filled in by the repository in Task 7.
class ReviewSourceData {
  const ReviewSourceData({
    required this.features,
    required this.submissions,
    required this.buildingAttrs,
    required this.roadAttrs,
    required this.householdSurveys,
    required this.photoCountsBySubmission,
    required this.deadJobs,
  });
  final List<Feature> features;
  final List<Submission> submissions;
  final List<BuildingAttribute> buildingAttrs;
  final List<RoadAttribute> roadAttrs;
  final List<HouseholdSurvey> householdSurveys;
  final Map<String, int> photoCountsBySubmission;
  final List<DeadJobRow> deadJobs;
}
```

- [ ] **Step 5: Run tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/domain/review_validator_test.dart
```

Expected: 11 PASS.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/domain/review_validator.dart lib/features/review/data/review_repository.dart test/features/review/domain/review_validator_test.dart && git commit -m "feat(review): pure ReviewValidator with 11-case coverage"
```

---

### Task 7: `ReviewRepository` — combined source-data stream

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/data/review_repository.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/data/review_repository_test.dart`

`ReviewSourceData` was stubbed in Task 6. Now add the streaming method that drives it from Drift.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ReviewRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ReviewRepository(db);
  });
  tearDown(() async => db.close());

  Future<void> _seedAssignmentAndFeature() async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f-1',
          assignmentId: 'a-1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
  }

  test('emits a snapshot containing seeded features', () async {
    await _seedAssignmentAndFeature();

    final first = await repo.streamForAssignment('a-1').first;
    expect(first.features, hasLength(1));
    expect(first.features.first.id, 'f-1');
    expect(first.submissions, isEmpty);
    expect(first.deadJobs, isEmpty);
  });

  test('re-emits when a submission is added', () async {
    await _seedAssignmentAndFeature();
    final emitted = <int>[];
    final sub = repo.streamForAssignment('a-1').listen((data) {
      emitted.add(data.submissions.length);
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await sub.cancel();
    expect(emitted.last, 1);
  });

  test('photoCountsBySubmission counts photos per submission id', () async {
    await _seedAssignmentAndFeature();
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ));
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'p-1',
          submissionId: 's-1',
          localPath: '/tmp/x.jpg',
          capturedAt: DateTime(2026, 4, 27),
        ));

    final snap = await repo.streamForAssignment('a-1').first;
    expect(snap.photoCountsBySubmission['s-1'], 1);
  });

  test('deadJobs surfaces only sync_jobs with status=dead for this assignment', () async {
    await _seedAssignmentAndFeature();
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ));
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 'j-1',
          entityType: 'submission',
          entityId: 's-1',
          createdAt: DateTime(2026, 4, 27),
        ));
    await (db.update(db.syncJobs)..where((t) => t.id.equals('j-1'))).write(
      const SyncJobsCompanion(
        status: Value('dead'),
        attempts: Value(5),
        lastError: Value('Network error'),
      ),
    );

    final snap = await repo.streamForAssignment('a-1').first;
    expect(snap.deadJobs, hasLength(1));
    expect(snap.deadJobs.first.jobId, 'j-1');
    expect(snap.deadJobs.first.attempts, 5);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/data/review_repository_test.dart
```

Expected: FAIL with `The method 'streamForAssignment' isn't defined`.

- [ ] **Step 3: Replace the stubbed file with the full repository**

Overwrite `lib/features/review/data/review_repository.dart` (the stub from Task 6):

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/domain/review_state.dart';

/// Snapshot the validator consumes.
class ReviewSourceData {
  const ReviewSourceData({
    required this.features,
    required this.submissions,
    required this.buildingAttrs,
    required this.roadAttrs,
    required this.householdSurveys,
    required this.photoCountsBySubmission,
    required this.deadJobs,
  });
  final List<Feature> features;
  final List<Submission> submissions;
  final List<BuildingAttribute> buildingAttrs;
  final List<RoadAttribute> roadAttrs;
  final List<HouseholdSurvey> householdSurveys;
  final Map<String, int> photoCountsBySubmission;
  final List<DeadJobRow> deadJobs;
}

class ReviewRepository {
  ReviewRepository(this._db);
  final AppDatabase _db;

  /// Combined stream that re-emits whenever any source table changes for
  /// this assignment. Implementation: a single customSelect using a
  /// constant SELECT 1 with a `readsFrom` set drives the stream cadence;
  /// each emission triggers a fan-in fetch of the actual rows.
  Stream<ReviewSourceData> streamForAssignment(String assignmentId) {
    final trigger = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.features,
            _db.submissions,
            _db.buildingAttributes,
            _db.roadAttributes,
            _db.householdSurveys,
            _db.photos,
            _db.syncJobs,
          },
        )
        .watch();

    return trigger.asyncMap((_) async => _snapshot(assignmentId));
  }

  Future<ReviewSourceData> _snapshot(String assignmentId) async {
    final features = await (_db.select(_db.features)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .get();
    final featureIds = features.map((f) => f.id).toList();

    final submissions = featureIds.isEmpty
        ? <Submission>[]
        : await (_db.select(_db.submissions)
              ..where((t) => t.featureId.isIn(featureIds)))
            .get();
    final submissionIds = submissions.map((s) => s.id).toList();

    final buildingAttrs = submissionIds.isEmpty
        ? <BuildingAttribute>[]
        : await (_db.select(_db.buildingAttributes)
              ..where((t) => t.submissionId.isIn(submissionIds)))
            .get();
    final roadAttrs = submissionIds.isEmpty
        ? <RoadAttribute>[]
        : await (_db.select(_db.roadAttributes)
              ..where((t) => t.submissionId.isIn(submissionIds)))
            .get();
    final householdSurveys = submissionIds.isEmpty
        ? <HouseholdSurvey>[]
        : await (_db.select(_db.householdSurveys)
              ..where((t) => t.submissionId.isIn(submissionIds)))
            .get();

    final photoCounts = <String, int>{};
    if (submissionIds.isNotEmpty) {
      final photoRows = await (_db.select(_db.photos)
            ..where((t) => t.submissionId.isIn(submissionIds)))
          .get();
      for (final p in photoRows) {
        photoCounts[p.submissionId] = (photoCounts[p.submissionId] ?? 0) + 1;
      }
    }

    final deadJobRows = await _db.customSelect(
      '''
      SELECT j.id, j.entity_type, j.entity_id, j.attempts, j.last_error
      FROM sync_jobs j
      WHERE j.status = 'dead'
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
        OR (j.entity_type = 'new_feature' AND j.entity_id IN (
          SELECT id FROM features WHERE assignment_id = ?
        ))
      )
      ORDER BY j.created_at ASC
      ''',
      variables: [
        Variable.withString(assignmentId),
        Variable.withString(assignmentId),
        Variable.withString(assignmentId),
      ],
      readsFrom: {_db.syncJobs, _db.submissions, _db.features, _db.photos},
    ).get();

    final deadJobs = deadJobRows
        .map((r) => DeadJobRow(
              jobId: r.read<String>('id'),
              entityType: r.read<String>('entity_type'),
              entityId: r.read<String>('entity_id'),
              attempts: r.read<int>('attempts'),
              lastError: r.read<String?>('last_error') ?? '',
            ))
        .toList();

    return ReviewSourceData(
      features: features,
      submissions: submissions,
      buildingAttrs: buildingAttrs,
      roadAttrs: roadAttrs,
      householdSurveys: householdSurveys,
      photoCountsBySubmission: photoCounts,
      deadJobs: deadJobs,
    );
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/data/review_repository_test.dart
```

Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/data/review_repository.dart test/features/review/data/review_repository_test.dart && git commit -m "feat(review): ReviewRepository.streamForAssignment combined source-data stream"
```

---

### Task 8: `RetryDeadUseCase`

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/sub/retry_dead_use_case.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/sub/retry_dead_use_case_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/presentation/sub/retry_dead_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyTrigger {
  int triggerCount = 0;
  Future<void> call() async => triggerCount++;
}

void main() {
  late AppDatabase db;
  late _SpyTrigger trigger;
  late RetryDeadUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    trigger = _SpyTrigger();
    useCase = RetryDeadUseCase(db: db, triggerNow: trigger.call);
  });
  tearDown(() async => db.close());

  Future<String> _seedDeadJob({String id = 'j-1'}) async {
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: id,
          entityType: 'submission',
          entityId: 's-1',
          createdAt: DateTime(2026, 4, 27),
        ));
    await (db.update(db.syncJobs)..where((t) => t.id.equals(id))).write(
      SyncJobsCompanion(
        status: const Value('dead'),
        attempts: const Value(5),
        lastError: const Value('boom'),
        nextRetryAt: Value(DateTime(2026, 4, 28)),
      ),
    );
    return id;
  }

  test('retryOne flips dead → pending and resets attempts/error/retry_at', () async {
    final jobId = await _seedDeadJob();
    await useCase.retryOne(jobId);

    final row = await (db.select(db.syncJobs)..where((t) => t.id.equals(jobId)))
        .getSingle();
    expect(row.status, 'pending');
    expect(row.attempts, 0);
    expect(row.lastError, isNull);
    expect(row.nextRetryAt, isNull);
    expect(trigger.triggerCount, 1);
  });

  test('retryAll flips every dead job to pending', () async {
    await _seedDeadJob(id: 'j-1');
    await _seedDeadJob(id: 'j-2');
    await useCase.retryAll();

    final rows = await db.select(db.syncJobs).get();
    for (final r in rows) {
      expect(r.status, 'pending');
    }
    expect(trigger.triggerCount, 1);
  });

  test('retryOne is a no-op when job is not dead', () async {
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 'j-1',
          entityType: 'submission',
          entityId: 's-1',
          createdAt: DateTime(2026, 4, 27),
        ));
    await useCase.retryOne('j-1');

    final row = await (db.select(db.syncJobs)..where((t) => t.id.equals('j-1')))
        .getSingle();
    expect(row.status, 'pending'); // already pending; unchanged
    expect(trigger.triggerCount, 1); // still triggers worker
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sub/retry_dead_use_case_test.dart
```

Expected: FAIL with `Target of URI doesn't exist`.

- [ ] **Step 3: Implement**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';

typedef TriggerSync = Future<void> Function();

class RetryDeadUseCase {
  RetryDeadUseCase({required this.db, required this.triggerNow});
  final AppDatabase db;
  final TriggerSync triggerNow;

  Future<void> retryOne(String jobId) async {
    await (db.update(db.syncJobs)
          ..where((t) => t.id.equals(jobId) & t.status.equals('dead')))
        .write(const SyncJobsCompanion(
      status: Value('pending'),
      attempts: Value(0),
      lastError: Value(null),
      nextRetryAt: Value(null),
    ));
    await triggerNow();
  }

  Future<void> retryAll() async {
    await (db.update(db.syncJobs)..where((t) => t.status.equals('dead')))
        .write(const SyncJobsCompanion(
      status: Value('pending'),
      attempts: Value(0),
      lastError: Value(null),
      nextRetryAt: Value(null),
    ));
    await triggerNow();
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sub/retry_dead_use_case_test.dart
```

Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/sub/retry_dead_use_case.dart test/features/review/presentation/sub/retry_dead_use_case_test.dart && git commit -m "feat(review): RetryDeadUseCase (retryOne + retryAll + worker trigger)"
```

---

### Task 9: `StartUploadUseCase`

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/sub/start_upload_use_case.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/sub/start_upload_use_case_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/features/review/presentation/sub/start_upload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyTrigger {
  int count = 0;
  Future<void> call() async => count++;
}

void main() {
  late AppDatabase db;
  late _SpyTrigger trigger;
  late StartUploadUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    trigger = _SpyTrigger();
    useCase = StartUploadUseCase(
      db: db,
      finalize: FinalizeSubmissionUseCase(db),
      triggerNow: trigger.call,
    );
  });
  tearDown(() async => db.close());

  Future<void> _seedAssignment() async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f-1',
          assignmentId: 'a-1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
  }

  Future<void> _seedSubmission(String id, String status) async {
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: id,
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          syncStatus: Value(status),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ));
  }

  test('finalizes only ready_to_upload submissions, returns count', () async {
    await _seedAssignment();
    await _seedSubmission('s-ready', 'ready_to_upload');
    await _seedSubmission('s-draft', 'draft');
    await _seedSubmission('s-uploaded', 'uploaded');

    final result = await useCase.execute('a-1');
    expect(result.finalizedCount, 1);
    expect(trigger.count, 1);

    final ready = await (db.select(db.submissions)
          ..where((t) => t.id.equals('s-ready')))
        .getSingle();
    expect(ready.syncStatus, 'queued'); // FinalizeUseCase moves it to queued
  });

  test('idempotent — re-running with no remaining ready_to_upload returns 0', () async {
    await _seedAssignment();
    await _seedSubmission('s-1', 'ready_to_upload');
    await useCase.execute('a-1');
    final result = await useCase.execute('a-1');
    expect(result.finalizedCount, 0);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sub/start_upload_use_case_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';

typedef TriggerSync = Future<void> Function();

class StartUploadResult {
  const StartUploadResult({required this.finalizedCount});
  final int finalizedCount;
}

class StartUploadUseCase {
  StartUploadUseCase({
    required this.db,
    required this.finalize,
    required this.triggerNow,
  });
  final AppDatabase db;
  final FinalizeSubmissionUseCase finalize;
  final TriggerSync triggerNow;

  /// Finalizes every `ready_to_upload` submission belonging to this
  /// assignment, then triggers the sync worker. Idempotent — already-
  /// queued or already-uploaded submissions are skipped.
  Future<StartUploadResult> execute(String assignmentId) async {
    final ready = await (db.select(db.submissions).join([
      innerJoin(db.features, db.features.id.equalsExp(db.submissions.featureId)),
    ])
          ..where(db.features.assignmentId.equals(assignmentId) &
              db.submissions.syncStatus.equals('ready_to_upload')))
        .map((row) => row.readTable(db.submissions))
        .get();

    for (final s in ready) {
      await finalize.execute(s.id);
    }
    await triggerNow();
    return StartUploadResult(finalizedCount: ready.length);
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sub/start_upload_use_case_test.dart
```

Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/sub/start_upload_use_case.dart test/features/review/presentation/sub/start_upload_use_case_test.dart && git commit -m "feat(review): StartUploadUseCase finalizes ready_to_upload + triggers worker"
```

---

### Task 10: `UploadProgressController` (StateNotifier)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/upload_progress_controller.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/upload_progress_controller_test.dart`

Subscribes to a `Stream<List<SyncJob>>` (jobs for the current assignment) and emits the appropriate `UploadProgress` value.

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:async';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:flutter_test/flutter_test.dart';

SyncJob _job(String id, String status) => SyncJob(
      id: id,
      entityType: 'submission',
      entityId: 'e-$id',
      status: status,
      attempts: 0,
      blocksOnSubmissionId: null,
      lastError: null,
      nextRetryAt: null,
      createdAt: DateTime(2026, 4, 27),
    );

void main() {
  test('starts Idle', () {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    expect(notifier.state, isA<Idle>());
  });

  test('beginUpload + non-empty stream emits InProgress with done/total', () async {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    notifier.beginUpload();

    ctrl.add([_job('a', 'pending'), _job('b', 'in_progress'), _job('c', 'success')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(notifier.state, isA<InProgress>());
    final p = notifier.state as InProgress;
    expect(p.done, 1);
    expect(p.total, 3);
  });

  test('all-success → Completed(failedCount: 0)', () async {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    notifier.beginUpload();
    ctrl.add([_job('a', 'success'), _job('b', 'success')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(notifier.state, isA<Completed>());
    expect((notifier.state as Completed).failedCount, 0);
  });

  test('any dead → Completed(failedCount: N)', () async {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    notifier.beginUpload();
    ctrl.add([_job('a', 'success'), _job('b', 'dead')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(notifier.state, isA<Completed>());
    expect((notifier.state as Completed).failedCount, 1);
  });

  test('reset() returns to Idle', () async {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    notifier.beginUpload();
    ctrl.add([_job('a', 'success')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    notifier.reset();
    expect(notifier.state, isA<Idle>());
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/upload_progress_controller_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'dart:async';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// StateNotifier driving the Review screen's render mode based on
/// the live sync_jobs stream for the current assignment.
class UploadProgressController extends StateNotifier<UploadProgress> {
  UploadProgressController({required Stream<List<SyncJob>> jobsStream})
      : super(const Idle()) {
    _sub = jobsStream.listen(_onJobs);
  }

  late final StreamSubscription<List<SyncJob>> _sub;
  bool _uploading = false;

  /// Caller flips this on right before triggering the worker. While true,
  /// the controller computes InProgress/Completed; while false, all
  /// emissions are ignored (we stay Idle).
  void beginUpload() {
    _uploading = true;
    state = const InProgress(done: 0, total: 0);
  }

  void reset() {
    _uploading = false;
    state = const Idle();
  }

  void _onJobs(List<SyncJob> jobs) {
    if (!_uploading) return;
    if (jobs.isEmpty) {
      state = const Completed(failedCount: 0);
      return;
    }
    final done = jobs.where((j) => j.status == 'success').length;
    final dead = jobs.where((j) => j.status == 'dead').length;
    final terminal = done + dead;
    if (terminal == jobs.length) {
      state = Completed(failedCount: dead);
      return;
    }
    state = InProgress(done: done, total: jobs.length);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/upload_progress_controller_test.dart
```

Expected: 5 PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/upload_progress_controller.dart test/features/review/presentation/upload_progress_controller_test.dart && git commit -m "feat(review): UploadProgressController emits Idle|InProgress|Completed"
```

---

### Task 11: `AssignmentLockState` sealed + provider

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/assignment/presentation/assignment_lock_state.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/assignment/presentation/assignment_lock_providers.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/assignment/assignment_lock_state_test.dart`

`AssignmentLockState` combines two existing streams:
- `AssignmentRepository.watchCurrentAssignment()` (gives `submittedAt` + `closedRemotely`)
- `PendingWorkBundle.exportFor(assignmentId)` (called once when `closedRemotely` flips true; the resulting `File` becomes the `bundleFile` field).

- [ ] **Step 1: Write the failing test for the sealed class**

```dart
import 'dart:io';

import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Unlocked equality', () {
    expect(const Unlocked(), const Unlocked());
  });

  test('Submitted carries submittedAt', () {
    final s1 = Submitted(submittedAt: DateTime(2026, 4, 27));
    final s2 = Submitted(submittedAt: DateTime(2026, 4, 27));
    expect(s1.submittedAt, s2.submittedAt);
  });

  test('ClosedRemotely carries optional bundleFile', () {
    const c1 = ClosedRemotely(bundleFile: null);
    final c2 = ClosedRemotely(bundleFile: File('/tmp/x.zip'));
    expect(c1.bundleFile, isNull);
    expect(c2.bundleFile?.path, '/tmp/x.zip');
  });
}
```

- [ ] **Step 2: Implement the sealed class**

```dart
// lib/features/assignment/presentation/assignment_lock_state.dart
import 'dart:io';

/// User-facing lock state for the current assignment.
///
/// Closed-remotely overrides Submitted. (Phase 4b accepts that the
/// closed_remotely flag may flip after a successful submit; the user is
/// blocked regardless.)
sealed class AssignmentLockState {
  const AssignmentLockState();
}

class Unlocked extends AssignmentLockState {
  const Unlocked();
}

class Submitted extends AssignmentLockState {
  const Submitted({required this.submittedAt});
  final DateTime submittedAt;
}

class ClosedRemotely extends AssignmentLockState {
  const ClosedRemotely({required this.bundleFile});
  final File? bundleFile; // may be null briefly while bundle is generating
}
```

- [ ] **Step 3: Run the sealed class tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/assignment/assignment_lock_state_test.dart
```

Expected: 3 PASS.

- [ ] **Step 4: Implement the provider**

```dart
// lib/features/assignment/presentation/assignment_lock_providers.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the user-facing lock state for the current assignment by
/// combining the assignments row (submittedAt, closedRemotely) with a
/// lazily-generated bundle file for the closed-remotely path.
final assignmentLockStateProvider =
    StreamProvider<AssignmentLockState>((ref) async* {
  final repo = ref.watch(assignmentRepositoryProvider);
  final bundle = ref.watch(pendingWorkBundleProvider);

  await for (final assignment in repo.watchCurrentAssignment()) {
    if (assignment == null) {
      yield const Unlocked();
      continue;
    }
    if (assignment.closedRemotely) {
      yield const ClosedRemotely(bundleFile: null);
      try {
        final file = await bundle.exportFor(assignment.id);
        yield ClosedRemotely(bundleFile: file);
      } on Object {
        // Bundle export is best-effort; the blocker UI degrades gracefully
        // when bundleFile is null.
      }
    } else if (assignment.submittedAt != null) {
      yield Submitted(submittedAt: assignment.submittedAt!);
    } else {
      yield const Unlocked();
    }
  }
});

/// Convenience: synchronous bool that consumers can watch to gate
/// edit-affordances. True means edits should be blocked.
final isAssignmentLockedProvider = Provider<bool>((ref) {
  final state = ref.watch(assignmentLockStateProvider).value;
  return state is Submitted || state is ClosedRemotely;
});
```

- [ ] **Step 5: Verify analyze clean**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/assignment/presentation/assignment_lock_state.dart lib/features/assignment/presentation/assignment_lock_providers.dart
```

Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/assignment/presentation/assignment_lock_state.dart lib/features/assignment/presentation/assignment_lock_providers.dart test/features/assignment/assignment_lock_state_test.dart && git commit -m "feat(assignment): AssignmentLockState (Unlocked|Submitted|ClosedRemotely) + provider"
```

---

### Task 12: `SubmittedAssignmentLock` — watch-and-stamp

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/assignment/data/submitted_assignment_lock.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/assignment/submitted_assignment_lock_test.dart`

Per the spec §8.1 (with the SQL fix from spec self-review): the watcher counts ANY non-terminal sync_job (submission, photo, new_feature) belonging to the assignment. When zero remain AND `submitted_at` is null, it stamps `submitted_at = now`. Idempotent.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/submitted_assignment_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SubmittedAssignmentLock lock;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    lock = SubmittedAssignmentLock(db);
  });
  tearDown(() async => db.close());

  Future<void> _seedAssignment({DateTime? submittedAt}) async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
          submittedAt: Value(submittedAt),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f-1',
          assignmentId: 'a-1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ));
  }

  Future<void> _addJob(String id, String status, {String entityType = 'submission', String entityId = 's-1'}) async {
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: id,
          entityType: entityType,
          entityId: entityId,
          createdAt: DateTime(2026, 4, 27),
        ));
    if (status != 'pending') {
      await (db.update(db.syncJobs)..where((t) => t.id.equals(id))).write(
        SyncJobsCompanion(status: Value(status)),
      );
    }
  }

  test('stamps submittedAt when no non-terminal jobs remain', () async {
    await _seedAssignment();
    await _addJob('j-1', 'success');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNotNull);
  });

  test('does NOT stamp when a pending submission job remains', () async {
    await _seedAssignment();
    await _addJob('j-1', 'pending');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNull);
  });

  test('does NOT stamp when a pending photo job remains', () async {
    await _seedAssignment();
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'p-1',
          submissionId: 's-1',
          localPath: '/tmp/x.jpg',
          capturedAt: DateTime(2026, 4, 27),
        ));
    await _addJob('j-1', 'success'); // submission job done
    await _addJob('j-2', 'pending', entityType: 'photo', entityId: 'p-1');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNull);
  });

  test('does NOT stamp when a dead job remains', () async {
    await _seedAssignment();
    await _addJob('j-1', 'dead');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNull);
  });

  test('idempotent — does not overwrite existing submittedAt', () async {
    final original = DateTime(2026, 1, 1);
    await _seedAssignment(submittedAt: original);
    await _addJob('j-1', 'success');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, original);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/assignment/submitted_assignment_lock_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';

class SubmittedAssignmentLock {
  SubmittedAssignmentLock(this._db);
  final AppDatabase _db;

  /// Watches sync_jobs + submissions for the assignment. Whenever the set
  /// of non-terminal jobs (any of {pending, in_progress, dead}) reaches
  /// zero AND the assignment hasn't been stamped, stamps
  /// `assignments.submitted_at = DateTime.now()`. Idempotent.
  ///
  /// Counts submission, photo, AND new_feature jobs (a stuck photo or
  /// new-feature job must NOT silently allow stamping).
  Stream<void> watchAndStamp(String assignmentId) async* {
    final trigger = _db.customSelect(
      'SELECT 1',
      readsFrom: {_db.submissions, _db.syncJobs, _db.assignments},
    ).watch();

    await for (final _ in trigger) {
      if (await _shouldStampNow(assignmentId)) {
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
        OR (j.entity_type = 'new_feature' AND j.entity_id IN (
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
    return activeJobs.read<int>('c') == 0;
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/assignment/submitted_assignment_lock_test.dart
```

Expected: 5 PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/assignment/data/submitted_assignment_lock.dart test/features/assignment/submitted_assignment_lock_test.dart && git commit -m "feat(assignment): SubmittedAssignmentLock auto-stamps when all jobs done"
```

---

### Task 13: Wire `SubmittedAssignmentLock` listener in `main.dart`

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/main.dart`

The watcher needs to run for the lifetime of the app, scoped to the current assignment.

- [ ] **Step 1: Add a Riverpod provider for the lock + an autostart listener**

Append to `lib/core/sync/presentation/sync_providers.dart`:

```dart
import 'package:firecheck/features/assignment/data/submitted_assignment_lock.dart';

final submittedAssignmentLockProvider = Provider<SubmittedAssignmentLock>((ref) {
  return SubmittedAssignmentLock(ref.watch(appDatabaseProvider));
});
```

(If the import for `appDatabaseProvider` isn't already present in `sync_providers.dart`, add `import 'package:firecheck/features/home/presentation/home_providers.dart';`.)

- [ ] **Step 2: Extend `_SyncBootstrap` in `lib/main.dart` to subscribe**

Replace the body of `_SyncBootstrapState.initState()`:

```dart
@override
void initState() {
  super.initState();
  Future.microtask(() async {
    await ref.read(syncControllerProvider).start();
    _attachSubmittedLock();
  });
}

void _attachSubmittedLock() {
  // Pull the current assignment lazily and kick off the watcher.
  // Subscription lives for the rest of the app session.
  Future.microtask(() async {
    final repo = ref.read(assignmentRepositoryProvider);
    final assignment = await repo.getCurrentAssignment();
    if (assignment == null) return;
    ref
        .read(submittedAssignmentLockProvider)
        .watchAndStamp(assignment.id)
        .listen((_) {});
  });
}
```

Add the imports at the top of `main.dart`:

```dart
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
```

(`syncControllerProvider` is already imported.)

- [ ] **Step 3: Verify analyze clean + existing tests still pass**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/main.dart lib/core/sync/presentation/sync_providers.dart && flutter test
```

Expected: `No issues found!` and ≥ 240 + Phase 4b tasks-so-far passing.

- [ ] **Step 4: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/main.dart lib/core/sync/presentation/sync_providers.dart && git commit -m "feat(main): wire SubmittedAssignmentLock listener at app boot"
```

---

### Task 14: `review_providers.dart` — wire the Review screen's Riverpod graph

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/review_providers.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/review_validator.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/sub/retry_dead_use_case.dart';
import 'package:firecheck/features/review/presentation/sub/start_upload_use_case.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(appDatabaseProvider));
});

/// Snapshot of source data for the current assignment.
final reviewSourceProvider = StreamProvider<ReviewSourceData>((ref) async* {
  final assignment =
      await ref.watch(assignmentRepositoryProvider).getCurrentAssignment();
  if (assignment == null) {
    yield const ReviewSourceData(
      features: [],
      submissions: [],
      buildingAttrs: [],
      roadAttrs: [],
      householdSurveys: [],
      photoCountsBySubmission: {},
      deadJobs: [],
    );
    return;
  }
  yield* ref.watch(reviewRepositoryProvider).streamForAssignment(assignment.id);
});

/// Stream of sync_jobs for the current assignment, used by the upload
/// progress controller.
final assignmentJobsStreamProvider = StreamProvider((ref) async* {
  final assignment =
      await ref.watch(assignmentRepositoryProvider).getCurrentAssignment();
  if (assignment == null) {
    yield const <dynamic>[];
    return;
  }
  final db = ref.watch(appDatabaseProvider);
  yield* db.customSelect(
    '''
    SELECT j.* FROM sync_jobs j
    WHERE
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
      OR (j.entity_type = 'new_feature' AND j.entity_id IN (
        SELECT id FROM features WHERE assignment_id = ?
      ))
    ''',
    variables: [
      Variable.withString(assignment.id),
      Variable.withString(assignment.id),
      Variable.withString(assignment.id),
    ],
    readsFrom: {db.syncJobs, db.submissions, db.features, db.photos},
  ).watch().map((rows) => rows.map((r) => db.syncJobs.map(r.data)).toList());
});

final uploadProgressControllerProvider =
    StateNotifierProvider<UploadProgressController, UploadProgress>((ref) {
  final stream = ref.watch(assignmentJobsStreamProvider.stream);
  return UploadProgressController(jobsStream: stream);
});

/// Composite ReviewState — source data + current upload progress.
final reviewStateProvider = Provider<AsyncValue<ReviewState>>((ref) {
  final sourceAsync = ref.watch(reviewSourceProvider);
  final progress = ref.watch(uploadProgressControllerProvider);
  return sourceAsync.whenData((source) {
    final base = buildReviewState(source);
    return ReviewState(
      summary: base.summary,
      warnings: base.warnings,
      blockers: base.blockers,
      deadJobs: base.deadJobs,
      upload: progress,
    );
  });
});

final retryDeadUseCaseProvider = Provider<RetryDeadUseCase>((ref) {
  final controller = ref.watch(syncControllerProvider);
  return RetryDeadUseCase(
    db: ref.watch(appDatabaseProvider),
    triggerNow: controller.triggerNow,
  );
});

final startUploadUseCaseProvider = Provider<StartUploadUseCase>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final controller = ref.watch(syncControllerProvider);
  return StartUploadUseCase(
    db: db,
    finalize: FinalizeSubmissionUseCase(db),
    triggerNow: controller.triggerNow,
  );
});
```

The cast `db.syncJobs.map(r.data)` requires the right import. Add to the imports:

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
```

- [ ] **Step 2: Verify analyze clean**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/review/presentation/review_providers.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/review_providers.dart && git commit -m "feat(review): Riverpod graph (source/jobs/progress/state/use-cases)"
```

---

### Task 15: `_SummaryCard` widget

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/sections/summary_card.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/sections/summary_card_test.dart`

- [ ] **Step 1: Add ARB keys (preview — full set lands in Task 23)**

Add these five keys to `lib/core/i18n/app_en.arb` (and parity to `app_tl.arb`). For now this widget needs them; Task 23 finalises the rest.

```json
"summaryFeatures": "{n} features",
"@summaryFeatures": { "placeholders": { "n": {"type": "int"} } },
"summaryComplete": "{n} complete",
"@summaryComplete": { "placeholders": { "n": {"type": "int"} } },
"summaryIncomplete": "{n} incomplete",
"@summaryIncomplete": { "placeholders": { "n": {"type": "int"} } },
"summaryNewFeatures": "{n} new features added",
"@summaryNewFeatures": { "placeholders": { "n": {"type": "int"} } },
"summaryPhotosPending": "{n} photos pending",
"@summaryPhotosPending": { "placeholders": { "n": {"type": "int"} } },
```

Tagalog parity (`app_tl.arb`):

```json
"summaryFeatures": "{n} na istruktura",
"summaryComplete": "{n} tapos na",
"summaryIncomplete": "{n} kulang pa",
"summaryNewFeatures": "{n} bagong idinagdag",
"summaryPhotosPending": "{n} larawan ang kulang",
```

Regenerate localizations:

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter gen-l10n
```

- [ ] **Step 2: Write the failing widget test**

```dart
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/presentation/sections/summary_card.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all 5 stat rows', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SummaryCard(
            summary: ReviewSummary(
              totalFeatures: 7,
              completeFeatures: 5,
              incompleteFeatures: 2,
              newFeaturesAdded: 1,
              photosPending: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('7'), findsWidgets);
    expect(find.textContaining('5'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('1'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/summary_card_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Implement the widget**

```dart
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({required this.summary, super.key});
  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rows = [
      l.summaryFeatures(summary.totalFeatures),
      l.summaryComplete(summary.completeFeatures),
      l.summaryIncomplete(summary.incompleteFeatures),
      l.summaryNewFeatures(summary.newFeaturesAdded),
      l.summaryPhotosPending(summary.photosPending),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (text) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(text, style: const TextStyle(fontSize: 14)),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/summary_card_test.dart
```

Expected: 1 PASS.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/sections/summary_card.dart test/features/review/presentation/sections/summary_card_test.dart lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/ && git commit -m "feat(review): SummaryCard widget renders all 5 stats"
```

---

### Task 16: `_FailedJobsSection` widget

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/sections/failed_jobs_section.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/sections/failed_jobs_section_test.dart`

- [ ] **Step 1: Add ARB keys**

`app_en.arb`:
```json
"failedJobsTitle": "Failed ({n})",
"@failedJobsTitle": { "placeholders": { "n": {"type": "int"} } },
"retryButton": "Retry",
"retryAllButton": "Retry all",
```
`app_tl.arb`:
```json
"failedJobsTitle": "Nabigo ({n})",
"retryButton": "Subukan muli",
"retryAllButton": "Subukan lahat",
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing widget test**

```dart
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/presentation/sections/failed_jobs_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('returns SizedBox.shrink when no dead jobs', (tester) async {
    var retryAllCount = 0;
    var retryOneIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FailedJobsSection(
            deadJobs: const [],
            onRetryAll: () => retryAllCount++,
            onRetryOne: (id) => retryOneIds.add(id),
          ),
        ),
      ),
    );
    expect(find.textContaining('Failed'), findsNothing);
  });

  testWidgets('renders 1 row + Retry all + per-row Retry', (tester) async {
    var retryAllCount = 0;
    var retryOneIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FailedJobsSection(
            deadJobs: const [
              DeadJobRow(
                jobId: 'j-1',
                entityType: 'photo',
                entityId: 'p-1',
                attempts: 5,
                lastError: 'Network',
              ),
            ],
            onRetryAll: () => retryAllCount++,
            onRetryOne: retryOneIds.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.textContaining('Retry all'), findsOneWidget);

    await tester.tap(find.textContaining('Retry all'));
    expect(retryAllCount, 1);

    await tester.tap(find.byKey(const Key('failedJobs.retry-j-1')));
    expect(retryOneIds, ['j-1']);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/failed_jobs_section_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Implement**

```dart
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class FailedJobsSection extends StatelessWidget {
  const FailedJobsSection({
    required this.deadJobs,
    required this.onRetryAll,
    required this.onRetryOne,
    super.key,
  });

  final List<DeadJobRow> deadJobs;
  final VoidCallback onRetryAll;
  final void Function(String jobId) onRetryOne;

  @override
  Widget build(BuildContext context) {
    if (deadJobs.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return Card(
      color: const Color(0xFFFFF5F5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.failedJobsTitle(deadJobs.length),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFC53030),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onRetryAll,
                  child: Text(l.retryAllButton),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...deadJobs.map(
              (j) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${j.entityType} · ${j.entityId.substring(0, 6)}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            j.lastError,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: Key('failedJobs.retry-${j.jobId}'),
                      icon: const Icon(Icons.refresh, color: Color(0xFFC53030)),
                      onPressed: () => onRetryOne(j.jobId),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/failed_jobs_section_test.dart
```

Expected: 2 PASS.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/sections/failed_jobs_section.dart test/features/review/presentation/sections/failed_jobs_section_test.dart lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/ && git commit -m "feat(review): FailedJobsSection (per-row + Retry all)"
```

---

### Task 17: `_ValidationSection` widget (blockers + warnings)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/sections/validation_section.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/sections/validation_section_test.dart`

- [ ] **Step 1: Add ARB keys**

`app_en.arb`:
```json
"validationBlockersTitle": "Must fix before upload ({n})",
"@validationBlockersTitle": { "placeholders": { "n": {"type": "int"} } },
"validationWarningsTitle": "Recommended ({n})",
"@validationWarningsTitle": { "placeholders": { "n": {"type": "int"} } },
"goToFeature": "Go to feature",
"issuePhotoRequired": "At least one photo required",
"issueRa9514Required": "RA 9514 type not selected",
"issueWidthRequired": "Width must be greater than 0 m",
"issueOlpResidential": "OLP household survey not completed",
"issueCostAmountMissing": "Exact cost selected but amount is empty",
"issueFeatureNoSubmission": "Feature has no finalized submission",
```
`app_tl.arb`:
```json
"validationBlockersTitle": "Kailangang ayusin bago i-upload ({n})",
"validationWarningsTitle": "Inirerekomenda ({n})",
"goToFeature": "Pumunta sa feature",
"issuePhotoRequired": "Kailangan ng kahit isang larawan",
"issueRa9514Required": "Hindi pa napipili ang uri ng RA 9514",
"issueWidthRequired": "Ang lapad ay dapat higit sa 0 m",
"issueOlpResidential": "Hindi pa kumpleto ang OLP household survey",
"issueCostAmountMissing": "Napili ang eksaktong halaga pero walang halaga",
"issueFeatureNoSubmission": "Walang natapos na submission para sa feature na ito",
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing widget test**

```dart
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/presentation/sections/validation_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hidden when no issues', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValidationSection(
            issues: const [],
            severity: ReviewSeverity.blocker,
            onGoToFeature: (_) {},
          ),
        ),
      ),
    );
    expect(find.textContaining('fix before upload'), findsNothing);
  });

  testWidgets('groups issues by feature, shows Go-to-feature link', (tester) async {
    String? tappedFeature;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValidationSection(
            issues: const [
              ReviewIssue(
                featureId: 'f-1',
                featureLabel: 'Building 123abc',
                severity: ReviewSeverity.blocker,
                code: 'photo_required',
                messageKey: 'issuePhotoRequired',
              ),
            ],
            severity: ReviewSeverity.blocker,
            onGoToFeature: (id) => tappedFeature = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Must fix before upload'), findsOneWidget);
    expect(find.text('Building 123abc'), findsOneWidget);
    expect(find.textContaining('photo'), findsOneWidget);

    await tester.tap(find.text('Go to feature'));
    expect(tappedFeature, 'f-1');
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/validation_section_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Implement**

```dart
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class ValidationSection extends StatelessWidget {
  const ValidationSection({
    required this.issues,
    required this.severity,
    required this.onGoToFeature,
    super.key,
  });

  final List<ReviewIssue> issues;
  final ReviewSeverity severity;
  final void Function(String featureId) onGoToFeature;

  String _resolveMessage(AppLocalizations l, String key) {
    switch (key) {
      case 'issuePhotoRequired':
        return l.issuePhotoRequired;
      case 'issueRa9514Required':
        return l.issueRa9514Required;
      case 'issueWidthRequired':
        return l.issueWidthRequired;
      case 'issueOlpResidential':
        return l.issueOlpResidential;
      case 'issueCostAmountMissing':
        return l.issueCostAmountMissing;
      case 'issueFeatureNoSubmission':
        return l.issueFeatureNoSubmission;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final isBlocker = severity == ReviewSeverity.blocker;
    final color = isBlocker ? const Color(0xFFC53030) : const Color(0xFFB7791F);
    final title = isBlocker
        ? l.validationBlockersTitle(issues.length)
        : l.validationWarningsTitle(issues.length);

    final byFeature = <String, List<ReviewIssue>>{};
    final labels = <String, String>{};
    for (final i in issues) {
      byFeature.putIfAbsent(i.featureId, () => []).add(i);
      labels[i.featureId] = i.featureLabel;
    }

    return Card(
      color: isBlocker ? const Color(0xFFFFF5F5) : const Color(0xFFFFFAF0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isBlocker ? Icons.error_outline : Icons.warning_amber_outlined,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
              ],
            ),
            const SizedBox(height: 8),
            ...byFeature.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(labels[entry.key] ?? entry.key,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    ...entry.value.map(
                      (i) => Padding(
                        padding: const EdgeInsets.only(left: 12, top: 2),
                        child: Text('• ${_resolveMessage(l, i.messageKey)}'),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => onGoToFeature(entry.key),
                        child: Text(l.goToFeature),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/validation_section_test.dart
```

Expected: 2 PASS.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/sections/validation_section.dart test/features/review/presentation/sections/validation_section_test.dart lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/ && git commit -m "feat(review): ValidationSection (blockers + warnings, grouped + deep-link)"
```

---

### Task 18: `_StartUploadButton` widget

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/sections/start_upload_button.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/sections/start_upload_button_test.dart`

- [ ] **Step 1: Add ARB keys**

`app_en.arb`:
```json
"startUploadButton": "Start Upload",
"startUploadDisabledTooltip": "Fix the blockers above first",
```
`app_tl.arb`:
```json
"startUploadButton": "Simulan ang Pag-upload",
"startUploadDisabledTooltip": "Ayusin muna ang mga problema sa itaas",
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing widget test**

```dart
import 'package:firecheck/features/review/presentation/sections/start_upload_button.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('disabled with blockers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StartUploadButton(enabled: false, onPressed: () {}),
        ),
      ),
    );
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('enabled when ready, fires onPressed', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StartUploadButton(enabled: true, onPressed: () => pressed++),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    expect(pressed, 1);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/start_upload_button_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Implement**

```dart
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class StartUploadButton extends StatelessWidget {
  const StartUploadButton({
    required this.enabled,
    required this.onPressed,
    super.key,
  });
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final btn = SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(l.startUploadButton),
        ),
      ),
    );
    if (enabled) return btn;
    return Tooltip(
      message: l.startUploadDisabledTooltip,
      child: btn,
    );
  }
}
```

- [ ] **Step 5: Run test**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/start_upload_button_test.dart
```

Expected: 2 PASS.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/sections/start_upload_button.dart test/features/review/presentation/sections/start_upload_button_test.dart lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/ && git commit -m "feat(review): StartUploadButton with disabled tooltip"
```

---

### Task 19: `_UploadProgressSection` widget

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/sections/upload_progress_section.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/sections/upload_progress_section_test.dart`

- [ ] **Step 1: Add ARB keys**

`app_en.arb`:
```json
"uploadProgressLabel": "Uploading {done} of {total} items…",
"@uploadProgressLabel": { "placeholders": { "done": {"type": "int"}, "total": {"type": "int"} } },
"uploadProgressShowDetails": "Show details",
"uploadCompleteSuccess": "All {n} items uploaded.",
"@uploadCompleteSuccess": { "placeholders": { "n": {"type": "int"} } },
"uploadCompleteWithFailures": "{n} items failed. Check Failed section.",
"@uploadCompleteWithFailures": { "placeholders": { "n": {"type": "int"} } },
```
`app_tl.arb`:
```json
"uploadProgressLabel": "Ina-upload ang {done} sa {total} items…",
"uploadProgressShowDetails": "Ipakita ang detalye",
"uploadCompleteSuccess": "Lahat ng {n} items ay naka-upload na.",
"uploadCompleteWithFailures": "{n} items ang nabigo. Tingnan ang Failed.",
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing widget test**

```dart
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/sections/upload_progress_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('InProgress shows progress bar with done/total label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UploadProgressSection(
            progress: const InProgress(done: 2, total: 5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('5'), findsWidgets);
  });

  testWidgets('Completed(0) shows success message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UploadProgressSection(progress: const Completed(failedCount: 0)),
        ),
      ),
    );
    expect(find.textContaining('uploaded'), findsOneWidget);
  });

  testWidgets('Idle/Locked render nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: UploadProgressSection(progress: Idle())),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/upload_progress_section_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Implement**

```dart
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class UploadProgressSection extends StatelessWidget {
  const UploadProgressSection({required this.progress, super.key});
  final UploadProgress progress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return switch (progress) {
      Idle() => const SizedBox.shrink(),
      Locked() => const SizedBox.shrink(),
      InProgress(:final done, :final total) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.uploadProgressLabel(done, total)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: total == 0 ? null : done / total),
              ],
            ),
          ),
        ),
      Completed(:final failedCount) => Card(
          color: failedCount == 0
              ? const Color(0xFFE6FFFA)
              : const Color(0xFFFFF5F5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              failedCount == 0
                  ? l.uploadCompleteSuccess(0)
                  : l.uploadCompleteWithFailures(failedCount),
            ),
          ),
        ),
    };
  }
}
```

- [ ] **Step 5: Run test**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/sections/upload_progress_section_test.dart
```

Expected: 3 PASS.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/sections/upload_progress_section.dart test/features/review/presentation/sections/upload_progress_section_test.dart lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/ && git commit -m "feat(review): UploadProgressSection (sealed-switch render)"
```

---

### Task 20: `ReviewScreen` composer

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/review/presentation/review_screen.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/review/presentation/review_screen_test.dart`

- [ ] **Step 1: Add ARB keys**

`app_en.arb`:
```json
"reviewTitle": "Review & Upload",
```
`app_tl.arb`:
```json
"reviewTitle": "Suriin at I-upload",
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing widget test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders title and SummaryCard', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          assignmentRepositoryProvider.overrideWithValue(
            AssignmentRepository(client: throw_unimplemented(), db: db),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Review & Upload'), findsOneWidget);
  });
}

dynamic throw_unimplemented() => throw UnimplementedError();
```

(`AssignmentRepository` requires a `SupabaseClient` constructor arg which we can stub since the screen never calls `fetchAndUpsertCurrent`. The harness above throws if the screen *does* call into Supabase, surfacing accidental network access early.)

- [ ] **Step 3: Run test to verify it fails**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/review_screen_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Implement**

```dart
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
import 'package:firecheck/features/review/presentation/sections/failed_jobs_section.dart';
import 'package:firecheck/features/review/presentation/sections/start_upload_button.dart';
import 'package:firecheck/features/review/presentation/sections/summary_card.dart';
import 'package:firecheck/features/review/presentation/sections/upload_progress_section.dart';
import 'package:firecheck/features/review/presentation/sections/validation_section.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final stateAsync = ref.watch(reviewStateProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.reviewTitle)),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) {
          final inProgressOrCompleted = state.upload is InProgress ||
              state.upload is Completed;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (inProgressOrCompleted)
                UploadProgressSection(progress: state.upload)
              else ...[
                SummaryCard(summary: state.summary),
                const SizedBox(height: 8),
                FailedJobsSection(
                  deadJobs: state.deadJobs,
                  onRetryAll: () =>
                      ref.read(retryDeadUseCaseProvider).retryAll(),
                  onRetryOne: (id) =>
                      ref.read(retryDeadUseCaseProvider).retryOne(id),
                ),
                const SizedBox(height: 8),
                ValidationSection(
                  issues: state.blockers,
                  severity: ReviewSeverity.blocker,
                  onGoToFeature: (id) => context.go('/feature/$id'),
                ),
                const SizedBox(height: 8),
                ValidationSection(
                  issues: state.warnings,
                  severity: ReviewSeverity.warning,
                  onGoToFeature: (id) => context.go('/feature/$id'),
                ),
                const SizedBox(height: 16),
                StartUploadButton(
                  enabled: state.canStartUpload,
                  onPressed: () => _start(context, ref),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(uploadProgressControllerProvider.notifier);
    controller.beginUpload();
    final useCase = ref.read(startUploadUseCaseProvider);
    final assignment = await ref
        .read(reviewStateProvider)
        .whenOrNull(data: (s) => s.summary);
    if (assignment == null) return;
    // Read the assignment id directly so we don't depend on snapshot
    // wiring. The reviewSourceProvider already handles "no assignment".
    final repo = ref.read(uploadAssignmentResolverProvider);
    final id = await repo.currentId();
    if (id != null) {
      await useCase.execute(id);
    }
  }
}

/// Tiny resolver shim used by the screen to fetch the current assignment id
/// without re-walking the full reviewSourceProvider stream. Centralised
/// here (rather than per-screen) so future screens can reuse it.
final uploadAssignmentResolverProvider =
    Provider<_AssignmentResolver>((ref) => _AssignmentResolver(ref));

class _AssignmentResolver {
  _AssignmentResolver(this._ref);
  final Ref _ref;
  Future<String?> currentId() async {
    final repo = _ref.read(assignmentRepositoryProvider);
    final a = await repo.getCurrentAssignment();
    return a?.id;
  }
}
```

Add the import for `assignmentRepositoryProvider` at the top:

```dart
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
```

- [ ] **Step 5: Run test**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/review/presentation/review_screen_test.dart
```

Expected: 1 PASS.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/review/presentation/review_screen.dart test/features/review/presentation/review_screen_test.dart lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/ && git commit -m "feat(review): ReviewScreen composes sections + drives StartUpload"
```

---

### Task 21: `SubmittedBanner` + Home read-only mode + Upload Data biometric gate

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/assignment/presentation/submitted_banner.dart`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/home/presentation/home_screen.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/home/home_screen_upload_data_test.dart`

- [ ] **Step 1: Add ARB keys**

`app_en.arb`:
```json
"submittedBadge": "Submitted ✓",
"submittedAt": "Submitted on {date}",
"@submittedAt": { "placeholders": { "date": {"type": "String"} } },
"biometricGateReason": "Verify it's you to upload",
"biometricFailedSnackbar": "Biometric verification failed. Try again.",
```
`app_tl.arb`:
```json
"submittedBadge": "Naipasa na ✓",
"submittedAt": "Naipasa noong {date}",
"biometricGateReason": "Patunayan ang sarili para mag-upload",
"biometricFailedSnackbar": "Hindi nakumpirma. Subukan muli.",
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Implement `SubmittedBanner`**

```dart
// lib/features/assignment/presentation/submitted_banner.dart
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class SubmittedBanner extends StatelessWidget {
  const SubmittedBanner({required this.submittedAt, super.key});
  final DateTime submittedAt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final formatted =
        '${submittedAt.year}-${submittedAt.month.toString().padLeft(2, '0')}-${submittedAt.day.toString().padLeft(2, '0')}';
    return Card(
      color: const Color(0xFFE6FFFA),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF276749)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.submittedBadge,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600,
                          color: Color(0xFF276749))),
                  const SizedBox(height: 2),
                  Text(l.submittedAt(formatted),
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Write the failing widget test for Home**

```dart
import 'package:firecheck/core/security/biometric_gate.dart';
import 'package:firecheck/core/security/biometric_gate_provider.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBiometric extends BiometricGate {
  _FakeBiometric({this.available = true, this.willAuthenticate = true});
  final bool available;
  final bool willAuthenticate;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate({required String reason}) async =>
      willAuthenticate;
}

void main() {
  testWidgets('Upload Data tap → biometric success → router push observed',
      (tester) async {
    var navigated = '';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biometricGateProvider.overrideWithValue(_FakeBiometric()),
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(const Unlocked()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateRoute: (settings) {
            navigated = settings.name ?? '';
            return MaterialPageRoute(builder: (_) => const SizedBox());
          },
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload Data'));
    await tester.pumpAndSettle();
    expect(navigated, '/review');
  });

  testWidgets('SubmittedBanner replaces progress card when locked',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(Submitted(submittedAt: DateTime(2026, 4, 27))),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Submitted'), findsOneWidget);
    expect(find.text('Upload Data'), findsNothing);
  });
}
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/home/home_screen_upload_data_test.dart
```

Expected: FAIL.

- [ ] **Step 5: Replace `home_screen.dart`**

Read the existing file first, then overwrite. The new file removes the debug long-press, replaces the Phase 4 placeholder with the real biometric → /review wiring, and conditionally renders `SubmittedBanner` when locked.

```dart
import 'package:firecheck/core/security/biometric_gate_provider.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/submitted_banner.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final asyncSnap = ref.watch(progressProvider);
    final lock = ref.watch(assignmentLockStateProvider).value;
    final isLocked = lock is Submitted || lock is ClosedRemotely;

    return Scaffold(
      appBar: AppBar(title: const Text('FireCheck')),
      body: asyncSnap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (snap) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (lock is Submitted)
                SubmittedBanner(submittedAt: lock.submittedAt)
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.assignmentProgress,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          l.featuresLabel(
                              snap.completedFeatures, snap.totalFeatures),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        LinearProgressIndicator(
                          value: snap.totalFeatures == 0
                              ? 0
                              : snap.completedFeatures / snap.totalFeatures,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.jobCountsLabel(
                              snap.queuedJobs, snap.failedJobs, snap.deadJobs),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _ActionTile(
                title: l.gatherData,
                subtitle: l.gatherDataSubtitle,
                onTap: () => context.go('/map'),
              ),
              _ActionTile(
                title: l.getMaps,
                subtitle: l.getMapsSubtitle,
                onTap: () => context.go('/get-maps'),
              ),
              if (!isLocked)
                _ActionTile(
                  title: l.uploadData,
                  subtitle: l.uploadDataSubtitle,
                  onTap: () => _onUploadDataTap(context, ref, l),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onUploadDataTap(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final biometric = ref.read(biometricGateProvider);
    final available = await biometric.isAvailable();
    if (!available) {
      if (context.mounted) context.go('/review');
      return;
    }
    final ok = await biometric.authenticate(reason: l.biometricGateReason);
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
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
```

The Phase 4a debug long-press trigger is GONE. The Phase 4 "coming soon" placeholder is GONE.

- [ ] **Step 6: Run all tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test
```

Expected: 280+ passing (Phase 4b additions through Task 21). If pre-existing `home_screen_test.dart` fails because it asserts the old long-press or "coming soon" text, update those assertions to match the new flow.

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/assignment/presentation/submitted_banner.dart lib/features/home/presentation/home_screen.dart test/features/home/ lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/ && git commit -m "feat(home): biometric → /review; SubmittedBanner; debug trigger removed"
```

---

### Task 22: `submission_detail_screen` read-only mode

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/building_form/presentation/submission_detail_screen.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/submission_detail_read_only_test.dart`

When the assignment is locked, hide the Done button and the photo strip's "+ Photo" chip. Form sections rendered as `IgnorePointer` so users can review data but can't change it.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hides Done button when assignment is Submitted',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
          submittedAt: Value(DateTime(2026, 4, 27)),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f-1',
          assignmentId: 'a-1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          syncStatus: const Value('uploaded'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(Submitted(submittedAt: DateTime(2026, 4, 27))),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SubmissionDetailScreen(featureId: 'f-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Done'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/submission_detail_read_only_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Modify `_Footer` to consult the lock provider**

In `submission_detail_screen.dart`, add the import:

```dart
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
```

Then in `_Footer.build`, immediately after `final l = AppLocalizations.of(context)!;`, add:

```dart
final isLocked = ref.watch(isAssignmentLockedProvider);
if (isLocked) return const SizedBox.shrink();
```

- [ ] **Step 4: Wrap form bodies in `IgnorePointer` when locked**

In `_SubmissionDetailScreenState.build`'s `data:` callback, replace the `Expanded(child: isRoad ? RoadForm(...) : BuildingForm(...))` with:

```dart
Expanded(
  child: Consumer(
    builder: (context, ref2, _) {
      final locked = ref2.watch(isAssignmentLockedProvider);
      final form = isRoad
          ? RoadForm(
              submissionId: active.id,
              featureId: widget.featureId,
            )
          : BuildingForm(
              submissionId: active.id,
              featureId: widget.featureId,
            );
      return IgnorePointer(ignoring: locked, child: form);
    },
  ),
),
```

Add the lock provider import at the top:

```dart
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
```

(`Consumer` already comes from `flutter_riverpod`.)

- [ ] **Step 5: Hide PhotoStrip add-chip via the lock provider too**

Inside the `data:` callback (just above `_Footer`), wrap the `PhotoStrip` in a Consumer that hides the strip when locked OR pass an `enabled` flag if `PhotoStrip` already has one. Read it first:

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && grep -n "class PhotoStrip" lib/features/survey/photo_capture/presentation/photo_strip.dart
```

If `PhotoStrip` does not accept an `enabled` parameter, wrap with `IgnorePointer`:

```dart
Consumer(builder: (context, ref2, _) {
  final locked = ref2.watch(isAssignmentLockedProvider);
  return IgnorePointer(
    ignoring: locked,
    child: PhotoStrip(submissionId: active.id),
  );
}),
```

- [ ] **Step 6: Run tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/submission_detail_read_only_test.dart
```

Expected: 1 PASS.

- [ ] **Step 7: Run full suite to confirm no regression**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test
```

Expected: 285+ passing.

- [ ] **Step 8: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/building_form/presentation/submission_detail_screen.dart test/features/survey/submission_detail_read_only_test.dart && git commit -m "feat(detail): read-only mode when assignment locked"
```

---

### Task 23: `AssignmentClosedBlocker` overlay + map_screen read-only + router redirect

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/assignment/presentation/assignment_closed_blocker.dart`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/map/presentation/map_screen.dart`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/router/app_router.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/assignment/assignment_closed_blocker_test.dart`

- [ ] **Step 1: Add ARB keys**

`app_en.arb`:
```json
"assignmentClosedTitle": "Assignment closed",
"assignmentClosedBody": "This assignment was closed remotely. Tap Share to send your local data to your supervisor.",
"shareBundleAction": "Share bundle",
```
`app_tl.arb`:
```json
"assignmentClosedTitle": "Sarado na ang takda",
"assignmentClosedBody": "Sarado na ang takda na ito sa server. I-tap ang Share para ipadala ang lokal na datos sa supervisor mo.",
"shareBundleAction": "Ibahagi ang bundle",
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Implement the blocker widget**

```dart
// lib/features/assignment/presentation/assignment_closed_blocker.dart
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class AssignmentClosedBlocker extends ConsumerWidget {
  const AssignmentClosedBlocker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final lock = ref.watch(assignmentLockStateProvider).value;
    if (lock is! ClosedRemotely) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: Color(0xFFC53030)),
                const SizedBox(height: 12),
                Text(l.assignmentClosedTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 18)),
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

- [ ] **Step 3: Write the widget test**

```dart
import 'dart:io';

import 'package:firecheck/features/assignment/presentation/assignment_closed_blocker.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders title + body when ClosedRemotely', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(const ClosedRemotely(bundleFile: null)),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AssignmentClosedBlocker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Assignment closed'), findsOneWidget);
    expect(find.textContaining('Share'), findsNothing); // no bundle yet
  });

  testWidgets('renders Share button when bundle file present', (tester) async {
    final tempFile = File('${Directory.systemTemp.path}/dummy-bundle.zip')
      ..writeAsBytesSync(const [1, 2, 3]);
    addTearDown(tempFile.deleteSync);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(ClosedRemotely(bundleFile: tempFile)),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AssignmentClosedBlocker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Share'), findsOneWidget);
  });

  testWidgets('returns SizedBox.shrink when not closed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(const Unlocked()),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AssignmentClosedBlocker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Assignment closed'), findsNothing);
  });
}
```

Run:

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/assignment/assignment_closed_blocker_test.dart
```

Expected: 3 PASS.

- [ ] **Step 4: Modify `app_router.dart` — add `/review` route + ClosedRemotely redirect + blocker route**

Add the imports at the top:

```dart
import 'package:firecheck/features/assignment/presentation/assignment_closed_blocker.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
```

Extend the redirect logic — replace the existing `redirect:` callback with:

```dart
redirect: (context, state) {
  final auth = ref.read(authStateProvider);
  final lock = ref.read(assignmentLockStateProvider).value;
  final onLogin = state.matchedLocation == '/login';
  final onBlocker = state.matchedLocation == '/blocker';

  // Auth gate
  final authRedirect = switch (auth) {
    AuthChecking() => null,
    Unauthenticated() => onLogin ? null : '/login',
    Authenticated() => onLogin ? '/' : null,
  };
  if (authRedirect != null) return authRedirect;

  // ClosedRemotely lock blocks every screen except /login and /blocker.
  if (lock is ClosedRemotely && !onLogin && !onBlocker) {
    return '/blocker';
  }
  return null;
},
```

Add the `/review` and `/blocker` routes inside the `routes:` list:

```dart
GoRoute(
  path: '/review',
  builder: (context, state) => const ReviewScreen(),
),
GoRoute(
  path: '/blocker',
  builder: (context, state) => const AssignmentClosedBlocker(),
),
```

Verify analyze clean:

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/router/app_router.dart
```

- [ ] **Step 5: map_screen — disable add-mode pill when locked**

In `map_screen.dart`, inside `_MapScreenState.build`, replace the `_addModeActive` handling on the pill with a Consumer-aware version:

```dart
// Just before building the bottom Row of pills, add:
final isLocked = ref.watch(isAssignmentLockedProvider);

// In the existing `_pill` for add-mode, change `onTap` to:
onTap: isLocked
    ? null
    : () => setState(() => _addModeActive = !_addModeActive),
```

Add the import:

```dart
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
```

If `_pill` doesn't already accept a nullable `onTap`, update its signature to do so and visually grey out the pill when `onTap == null`:

```dart
Widget _pill(String label, {required bool on, VoidCallback? onTap, Key? key}) {
  return InkWell(
    key: key,
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.5 : 1.0,
      child: /* existing decoration */,
    ),
  );
}
```

(Keep the existing decoration; only the `onTap` and outer `Opacity` change.)

- [ ] **Step 6: Run all tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test
```

Expected: ≥ 290 passing.

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/assignment/presentation/assignment_closed_blocker.dart lib/core/router/app_router.dart lib/features/map/presentation/map_screen.dart test/features/assignment/assignment_closed_blocker_test.dart lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/ && git commit -m "feat(assignment): ClosedRemotely blocker + /review route + map read-only"
```

---

### Task 24: Integration test — full Flow F happy path

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/integration/review_happy_path_test.dart`

End-to-end test using `FakeSyncApi`. Seeds an assignment with 2 ready_to_upload submissions (each with a photo); opens `/review`; asserts no blockers; taps Start Upload; pumps until `Completed(failedCount: 0)`; asserts `assignments.submitted_at` is stamped.

- [ ] **Step 1: Write the test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/submitted_assignment_lock.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flow F happy path: review → start → submitted_at stamped',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed assignment + 2 features + 2 ready_to_upload submissions w/ photo + ra_9514_type
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ));
    for (final i in [1, 2]) {
      await db.into(db.features).insert(FeaturesCompanion.insert(
            id: 'f-$i',
            assignmentId: 'a-1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: DateTime(2026, 4, 27),
          ));
      await db.into(db.submissions).insert(SubmissionsCompanion.insert(
            id: 's-$i',
            featureId: 'f-$i',
            submittedBy: const Value('00000000-0000-0000-0000-00000000000$i'),
            syncStatus: const Value('ready_to_upload'),
            createdAt: DateTime(2026, 4, 27),
            updatedAt: DateTime(2026, 4, 27),
          ));
      await db.into(db.buildingAttributes).insert(BuildingAttributesCompanion.insert(
            submissionId: 's-$i',
            buildingName: const Value('Bldg $i'),
            ra9514Type: const Value('C'),
          ));
      await db.into(db.photos).insert(PhotosCompanion.insert(
            id: 'p-$i',
            submissionId: 's-$i',
            localPath: '/tmp/p-$i.jpg',
            capturedAt: DateTime(2026, 4, 27),
          ));
    }

    final fakeApi = FakeSyncApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncApiProvider.overrideWithValue(fakeApi as SyncApi),
          currentUserIdProvider.overrideWith(
            (_) => '00000000-0000-0000-0000-000000000001',
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Summary should show 2 features, 2 complete, 0 incomplete.
    expect(find.textContaining('2'), findsWidgets);

    // Tap Start Upload
    await tester.tap(find.text('Start Upload'));
    await tester.pumpAndSettle();
    // Settle a few extra frames for the sync worker to drain.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Manually run the SubmittedAssignmentLock once
    await SubmittedAssignmentLock(db).watchAndStamp('a-1').first;

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNotNull, reason: 'submitted_at should be stamped');
  }, skip: true);
  // Marked skip: requires the SyncController triggerNow to be wired with
  // its real worker — manual happy path on the emulator covers this in
  // Task 25. The integration test stays in tree as a documentation
  // anchor; flip skip:false once the SyncController gets a synchronous
  // drain helper (Phase 5).
}
```

The reasoning for `skip: true` is preserved in the comment — the SyncController's `triggerNow` is fire-and-forget; awaiting drain in a widget test requires either a synchronous drain or extensive `pump(Duration)` polling. Manual happy path on the emulator (Task 25) is the authoritative verification for the worker's progress + stamp behavior.

- [ ] **Step 2: Verify the test parses + skips cleanly**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/integration/review_happy_path_test.dart
```

Expected: `00:01 +0 ~1: All tests skipped.`

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add test/integration/review_happy_path_test.dart && git commit -m "test(integration): Flow F skeleton (documentation anchor; skip: true)"
```

---

### Task 25: Final verification + tag

**Files:** none (verification + git tag).

- [ ] **Step 1: Manual happy-path test on Pixel 7 emulator**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter run -d emulator-5554
```

Walk through Flow F:

1. Sign in as `admin@admin.com`.
2. Tap **Get Maps** → wait for "Ready to gather data".
3. Tap **Open map** → tap a polygon → fill the building form (RA 9514 type, storeys, material, cost, fire load) → take a photo → tap **Done**. Repeat for every feature in the assignment.
4. Return to Home (the progress card should read "N of N features").
5. Tap **Upload Data** → biometric prompt fires (use the emulator's "More → Fingerprint → Touch sensor" or the device PIN fallback).
6. `/review` screen opens. Verify:
   - Summary: total = N, complete = N, photos pending = 0
   - Failed: hidden
   - Blockers: empty
   - Warnings: optional
   - **Start Upload** is enabled.
7. Tap **Start Upload** → progress bar fills as items complete.
8. After `Completed(0)`, return to Home. Verify the **Submitted ✓ on YYYY-MM-DD** banner is shown and **Upload Data** is hidden.
9. Tap a previously-surveyed feature → verify the form renders read-only and the **Done** button is hidden.

Document any discrepancies (screenshot + symptom) in a follow-up commit BEFORE tagging.

- [ ] **Step 2: Run full automated suite**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze && flutter test
```

Expected:
- `flutter analyze`: `No issues found!`
- `flutter test`: ≥ 280 PASS (Phase 4a baseline 240 + ≥ 40 Phase 4b additions). Skipped: 1 (`review_happy_path_test.dart`).

If analyze warns about unused imports / leftover deprecated calls, fix and amend the latest commit only if the touched files are still in your working tree.

- [ ] **Step 3: Build a debug APK**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter build apk --debug
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. Build time ≈ 1-3 min.

- [ ] **Step 4: Tag the release locally**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git tag -a phase-4b-upload-flow -m "Phase 4b — Review screen + Upload Data flow + Submitted lock + ClosedRemotely blocker + biometric gate + real submittedBy wiring"
```

Verify:

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git tag -n -l phase-4b-upload-flow && git log --oneline -1
```

- [ ] **Step 5: Stop. Push is user-gated.**

Do NOT run `git push` or `git push --tags`. Hand control back to the user with this status:

```
Phase 4b complete locally.
Commits ahead of origin/main: <N>
New tag: phase-4b-upload-flow
flutter analyze: clean
flutter test: <COUNT> passed, 1 skipped
APK built: build/app/outputs/flutter-apk/app-debug.apk

Push when ready:
  git push origin main
  git push origin phase-4b-upload-flow
```

---

