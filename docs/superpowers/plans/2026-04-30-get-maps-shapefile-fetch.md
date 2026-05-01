# Get Maps — Shapefile Fetch from Drive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire "Get Maps" to fetch input shapefiles from Google Drive, import them into Drift, and then proceed with the existing Mapbox tile-pack download — leaving the enumerator fully equipped for offline work.

**Architecture:** Google OAuth via `google_sign_in` + `FlutterSecureStorage` guards `/get-maps` behind a new `/sign-in` screen. `GetMapsNotifier` gains Drive discovery, assignment picking, storage pre-check, zip download, shapefile import, and delta-skip steps before handing off to the existing tile-pack flow. `ShapefileImporter` handles unzip → validate → reproject → Drift write atomically in a single transaction.

**Tech Stack:** Flutter/Dart, Riverpod (`StateNotifier`), Drift ORM, go_router, `google_sign_in ^6.2.1`, `googleapis ^13.2.0`, `extension_google_sign_in_as_googleapis_auth ^2.0.12`, `proj4dart ^2.1.0`, `disk_space ^0.2.0`, `archive ^3.4.0` (existing)

---

## File Map

### New files
| Path | Responsibility |
|------|----------------|
| `lib/core/drive/drive_assignment.dart` | `DriveAssignment` value type |
| `lib/core/drive/drive_download_event.dart` | `DriveDownloadEvent` sealed class |
| `lib/core/drive/drive_api.dart` | `DriveApi` abstract interface |
| `lib/core/drive/fake_drive_api.dart` | `FakeDriveApi` for tests |
| `lib/core/drive/google_drive_api.dart` | `GoogleDriveApi` real impl (googleapis) |
| `lib/core/device/storage_checker.dart` | `StorageChecker` abstract + fake + real |
| `lib/core/sync/shapefile/dbf_parser.dart` | DBF binary → fields + records |
| `lib/core/sync/shapefile/shp_parser.dart` | SHP binary → sealed geometry list |
| `lib/core/sync/shapefile/shapefile_validator.dart` | Structure / CRS / column validation |
| `lib/core/sync/shapefile/reprojector.dart` | EPSG:32651 → EPSG:4326 via proj4dart |
| `lib/core/sync/shapefile/shapefile_importer.dart` | Orchestrates unzip → validate → reproject → Drift |
| `lib/features/auth/data/google_auth_repository.dart` | `GoogleAuthRepository` abstract interface |
| `lib/features/auth/data/fake_google_auth_repository.dart` | `FakeGoogleAuthRepository` |
| `lib/features/auth/data/google_sign_in_auth_repository.dart` | `GoogleSignInAuthRepository` real impl |
| `lib/features/auth/presentation/google_auth_providers.dart` | `GoogleAuthState`, `GoogleAuthNotifier`, providers |
| `lib/features/auth/presentation/sign_in_screen.dart` | One-time Google Sign-In screen |

### Modified files
| Path | Change |
|------|--------|
| `pubspec.yaml` | +5 packages |
| `lib/core/errors/failure.dart` | +`ShapefileValidationFailure`, +`NoAssignmentsFailure` |
| `lib/core/db/tables/assignments.dart` | +`driveModifiedTime`, +`driveFolderId` nullable columns |
| `lib/core/db/database.dart` | `schemaVersion` 6 → 7, migration `if (from < 7)` block |
| `lib/features/assignment/data/assignment_repository.dart` | +`getDriveModifiedTime`, −`fetchAndUpsertCurrent` |
| `lib/features/assignment/domain/get_maps_state.dart` | +5 new state classes, −`FetchingFeatures`, updated `overallProgress` |
| `lib/features/assignment/presentation/assignment_providers.dart` | `GetMapsNotifier` restructured + new deps + providers |
| `lib/features/assignment/presentation/get_maps_screen.dart` | +5 new view widgets, −`_FetchingFeaturesView` |
| `lib/core/i18n/app_en.arb` | +10 l10n keys, −`fetchingFeatures` |
| `lib/core/i18n/app_tl.arb` | same keys as en |
| `lib/core/router/app_router.dart` | +`/sign-in` route, +Google auth redirect guard |

---

### Task 1: Add packages

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the five packages**

In `pubspec.yaml` under `# platform`, after `flutter_secure_storage: ^9.2.2`, add:

```yaml
  # google
  google_sign_in: ^6.2.1
  googleapis: ^13.2.0
  extension_google_sign_in_as_googleapis_auth: ^2.0.12
  proj4dart: ^2.1.0
  disk_space: ^0.2.0
```

- [ ] **Step 2: Fetch and verify**

Run: `flutter pub get`
Expected: exits 0, no version conflicts.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add google_sign_in, googleapis, proj4dart, disk_space (US-17 T1)"
```

---

### Task 2: Failure types

**Files:**
- Modify: `lib/core/errors/failure.dart`
- Test: `test/core/errors/failure_us17_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/errors/failure_us17_test.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShapefileValidationFailure', () {
    test('carries message', () {
      const f = ShapefileValidationFailure("buildings.dbf is missing 'feat_id'");
      expect(f.message, contains('feat_id'));
      expect(f, isA<Failure>());
    });
  });

  group('NoAssignmentsFailure', () {
    test('has supervisor-guidance message', () {
      const f = NoAssignmentsFailure();
      expect(f.message, contains('supervisor'));
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/errors/failure_us17_test.dart`
Expected: FAIL — `ShapefileValidationFailure` undefined.

- [ ] **Step 3: Implement**

Append to `lib/core/errors/failure.dart`:

```dart
/// Shapefile import rejected: wrong CRS, missing layer, or missing column.
class ShapefileValidationFailure extends Failure {
  const ShapefileValidationFailure(super.message);
}

/// Drive inbox has no folders accessible to the signed-in user.
class NoAssignmentsFailure extends Failure {
  const NoAssignmentsFailure()
      : super(
          'No assignments shared with you yet — ask your supervisor to share '
          'the assignment folder with the Google account you signed in with.',
        );
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/core/errors/failure_us17_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/errors/failure.dart test/core/errors/failure_us17_test.dart
git commit -m "feat(errors): ShapefileValidationFailure + NoAssignmentsFailure (US-17 T2)"
```

---

### Task 3: Drive value types

**Files:**
- Create: `lib/core/drive/drive_assignment.dart`
- Create: `lib/core/drive/drive_download_event.dart`
- Test: `test/core/drive/drive_types_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/drive/drive_types_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = DriveAssignment(
    assignmentId: 'brgy-001',
    inputZipFileId: 'file-xyz',
    inputZipModifiedTime: '2026-04-28T10:00:00Z',
    driveFolderId: 'folder-abc',
  );

  group('DriveAssignment', () {
    test('alreadyDownloaded defaults to false', () {
      expect(base.alreadyDownloaded, isFalse);
    });

    test('copyWith sets alreadyDownloaded, preserves other fields', () {
      final updated = base.copyWith(alreadyDownloaded: true);
      expect(updated.alreadyDownloaded, isTrue);
      expect(updated.assignmentId, 'brgy-001');
      expect(updated.inputZipFileId, 'file-xyz');
    });
  });

  group('DriveDownloadEvent', () {
    test('DriveDownloadProgress exposes downloaded + total', () {
      const e = DriveDownloadProgress(downloaded: 512, total: 1024);
      expect(e.downloaded, 512);
      expect(e.total, 1024);
    });

    test('DriveDownloadComplete exposes bytes', () {
      final e = DriveDownloadComplete(Uint8List(8));
      expect(e.bytes.length, 8);
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/drive/drive_types_test.dart`
Expected: FAIL — files not found.

- [ ] **Step 3: Implement drive_assignment.dart**

```dart
// lib/core/drive/drive_assignment.dart
class DriveAssignment {
  const DriveAssignment({
    required this.assignmentId,
    required this.inputZipFileId,
    required this.inputZipModifiedTime,
    required this.driveFolderId,
    this.alreadyDownloaded = false,
  });

  final String assignmentId;
  final String inputZipFileId;
  final String inputZipModifiedTime;
  final String driveFolderId;
  final bool alreadyDownloaded;

  DriveAssignment copyWith({bool? alreadyDownloaded}) => DriveAssignment(
        assignmentId: assignmentId,
        inputZipFileId: inputZipFileId,
        inputZipModifiedTime: inputZipModifiedTime,
        driveFolderId: driveFolderId,
        alreadyDownloaded: alreadyDownloaded ?? this.alreadyDownloaded,
      );
}
```

- [ ] **Step 4: Implement drive_download_event.dart**

```dart
// lib/core/drive/drive_download_event.dart
import 'dart:typed_data';

sealed class DriveDownloadEvent {
  const DriveDownloadEvent();
}

class DriveDownloadProgress extends DriveDownloadEvent {
  const DriveDownloadProgress({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
}

class DriveDownloadComplete extends DriveDownloadEvent {
  const DriveDownloadComplete(this.bytes);
  final Uint8List bytes;
}
```

- [ ] **Step 5: Run to confirm pass**

Run: `flutter test test/core/drive/drive_types_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/drive/drive_assignment.dart lib/core/drive/drive_download_event.dart \
        test/core/drive/drive_types_test.dart
git commit -m "feat(drive): DriveAssignment + DriveDownloadEvent value types (US-17 T3)"
```

---

### Task 4: DriveApi + FakeDriveApi

**Files:**
- Create: `lib/core/drive/drive_api.dart`
- Create: `lib/core/drive/fake_drive_api.dart`
- Test: `test/core/drive/fake_drive_api_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/drive/fake_drive_api_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/drive/fake_drive_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _brgy001 = DriveAssignment(
  assignmentId: 'brgy-001',
  inputZipFileId: 'file-1',
  inputZipModifiedTime: '2026-04-28T10:00:00Z',
  driveFolderId: 'folder-1',
);

void main() {
  test('listAssignments returns configured list', () async {
    final api = FakeDriveApi(assignments: [_brgy001]);
    expect(await api.listAssignments(), hasLength(1));
  });

  test('listAssignments throws when listError configured', () async {
    final api = FakeDriveApi(listError: Exception('network'));
    expect(api.listAssignments(), throwsException);
  });

  test('getInputZipSize returns configured size', () async {
    final api = FakeDriveApi(assignments: [_brgy001], zipSize: 2048);
    expect(await api.getInputZipSize('brgy-001'), 2048);
  });

  test('downloadInputZip yields single complete event', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final api = FakeDriveApi(assignments: [_brgy001], downloadComplete: bytes);
    final events = await api.downloadInputZip('brgy-001').toList();
    expect(events, hasLength(1));
    expect((events.first as DriveDownloadComplete).bytes, bytes);
  });

  test('downloadInputZip yields custom event list', () async {
    final api = FakeDriveApi(
      assignments: [_brgy001],
      downloadEvents: [
        const DriveDownloadProgress(downloaded: 512, total: 1024),
        DriveDownloadComplete(Uint8List(0)),
      ],
    );
    final events = await api.downloadInputZip('brgy-001').toList();
    expect(events.first, isA<DriveDownloadProgress>());
    expect(events.last, isA<DriveDownloadComplete>());
  });

  test('downloadInputZip throws when downloadError configured', () async {
    final api = FakeDriveApi(
      assignments: [_brgy001],
      downloadError: Exception('timeout'),
    );
    expect(api.downloadInputZip('brgy-001').first, throwsException);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/drive/fake_drive_api_test.dart`
Expected: FAIL — `FakeDriveApi` not found.

- [ ] **Step 3: Implement drive_api.dart**

```dart
// lib/core/drive/drive_api.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

abstract class DriveApi {
  /// Lists /firecheck/inbox/ subfolders readable by the signed-in user.
  Future<List<DriveAssignment>> listAssignments();

  /// Size of input.zip in bytes from Drive file metadata.
  Future<int> getInputZipSize(String assignmentId);

  /// Streams download events for input.zip.
  Stream<DriveDownloadEvent> downloadInputZip(String assignmentId);
}
```

- [ ] **Step 4: Implement fake_drive_api.dart**

```dart
// lib/core/drive/fake_drive_api.dart
import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

class FakeDriveApi implements DriveApi {
  FakeDriveApi({
    List<DriveAssignment>? assignments,
    int zipSize = 1024,
    Uint8List? downloadComplete,
    List<DriveDownloadEvent>? downloadEvents,
    Exception? listError,
    Exception? downloadError,
  })  : _assignments = assignments ?? [],
        _zipSize = zipSize,
        _downloadComplete = downloadComplete,
        _downloadEvents = downloadEvents,
        _listError = listError,
        _downloadError = downloadError;

  final List<DriveAssignment> _assignments;
  final int _zipSize;
  final Uint8List? _downloadComplete;
  final List<DriveDownloadEvent>? _downloadEvents;
  final Exception? _listError;
  final Exception? _downloadError;

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    if (_listError != null) throw _listError;
    return List.unmodifiable(_assignments);
  }

  @override
  Future<int> getInputZipSize(String assignmentId) async => _zipSize;

  @override
  Stream<DriveDownloadEvent> downloadInputZip(String assignmentId) async* {
    if (_downloadError != null) throw _downloadError;
    if (_downloadEvents != null) {
      for (final e in _downloadEvents) {
        yield e;
      }
      return;
    }
    yield DriveDownloadComplete(_downloadComplete ?? Uint8List(0));
  }
}
```

- [ ] **Step 5: Run to confirm pass**

Run: `flutter test test/core/drive/fake_drive_api_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/drive/drive_api.dart lib/core/drive/fake_drive_api.dart \
        test/core/drive/fake_drive_api_test.dart
git commit -m "feat(drive): DriveApi abstract + FakeDriveApi (US-17 T4)"
```

---

### Task 5: StorageChecker

**Files:**
- Create: `lib/core/device/storage_checker.dart`
- Test: `test/core/device/storage_checker_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/device/storage_checker_test.dart
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeStorageChecker returns configured bytes', () async {
    final checker = FakeStorageChecker(availableBytes: 50 * 1024 * 1024);
    expect(await checker.getAvailableBytes(), 50 * 1024 * 1024);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/device/storage_checker_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/device/storage_checker.dart
import 'package:disk_space/disk_space.dart';

abstract class StorageChecker {
  Future<int> getAvailableBytes();
}

class FakeStorageChecker implements StorageChecker {
  const FakeStorageChecker({required this.availableBytes});
  final int availableBytes;

  @override
  Future<int> getAvailableBytes() async => availableBytes;
}

class DeviceStorageChecker implements StorageChecker {
  const DeviceStorageChecker();

  @override
  Future<int> getAvailableBytes() async {
    final freeMb = await DiskSpace.getFreeDiskSpace;
    if (freeMb == null) return 0;
    return (freeMb * 1024 * 1024).round();
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/core/device/storage_checker_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/device/storage_checker.dart test/core/device/storage_checker_test.dart
git commit -m "feat(device): StorageChecker abstract + fake + real (US-17 T5)"
```

---

### Task 6: GoogleAuthRepository + FakeGoogleAuthRepository

**Files:**
- Create: `lib/features/auth/data/google_auth_repository.dart`
- Create: `lib/features/auth/data/fake_google_auth_repository.dart`
- Test: `test/features/auth/fake_google_auth_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/auth/fake_google_auth_repository_test.dart
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts signed-in when configured', () async {
    final repo = FakeGoogleAuthRepository(startSignedIn: true);
    expect(await repo.isSignedIn(), isTrue);
  });

  test('starts signed-out when configured', () async {
    final repo = FakeGoogleAuthRepository(startSignedIn: false);
    expect(await repo.isSignedIn(), isFalse);
  });

  test('signIn sets isSignedIn to true', () async {
    final repo = FakeGoogleAuthRepository(startSignedIn: false);
    await repo.signIn();
    expect(await repo.isSignedIn(), isTrue);
  });

  test('signOut sets isSignedIn to false', () async {
    final repo = FakeGoogleAuthRepository(startSignedIn: true);
    await repo.signOut();
    expect(await repo.isSignedIn(), isFalse);
  });

  test('getEnumeratorId returns test-enumerator', () async {
    final repo = FakeGoogleAuthRepository();
    expect(await repo.getEnumeratorId(), 'test-enumerator');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/features/auth/fake_google_auth_repository_test.dart`
Expected: FAIL — files not found.

- [ ] **Step 3: Implement google_auth_repository.dart**

```dart
// lib/features/auth/data/google_auth_repository.dart
abstract class GoogleAuthRepository {
  Future<bool> isSignedIn();
  Future<void> signIn();
  Future<void> signOut();

  /// Returns the local-part of the signed-in Gmail address (e.g. 'jlescarlan11').
  Future<String> getEnumeratorId();
}
```

- [ ] **Step 4: Implement fake_google_auth_repository.dart**

```dart
// lib/features/auth/data/fake_google_auth_repository.dart
import 'package:firecheck/features/auth/data/google_auth_repository.dart';

class FakeGoogleAuthRepository implements GoogleAuthRepository {
  FakeGoogleAuthRepository({bool startSignedIn = true})
      : _signedIn = startSignedIn;

  bool _signedIn;

  @override
  Future<bool> isSignedIn() async => _signedIn;

  @override
  Future<void> signIn() async => _signedIn = true;

  @override
  Future<void> signOut() async => _signedIn = false;

  @override
  Future<String> getEnumeratorId() async => 'test-enumerator';
}
```

- [ ] **Step 5: Run to confirm pass**

Run: `flutter test test/features/auth/fake_google_auth_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/data/google_auth_repository.dart \
        lib/features/auth/data/fake_google_auth_repository.dart \
        test/features/auth/fake_google_auth_repository_test.dart
git commit -m "feat(auth): GoogleAuthRepository abstract + FakeGoogleAuthRepository (US-17 T6)"
```

---

### Task 7: GoogleAuthNotifier + GoogleSignInAuthRepository

**Files:**
- Create: `lib/features/auth/presentation/google_auth_providers.dart`
- Create: `lib/features/auth/data/google_sign_in_auth_repository.dart`
- Test: `test/features/auth/google_auth_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/auth/google_auth_notifier_test.dart
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transitions loading → signedIn when repo is signed-in', () async {
    final notifier = GoogleAuthNotifier(FakeGoogleAuthRepository(startSignedIn: true));
    expect(notifier.state, GoogleAuthState.loading);
    await Future.microtask(() {});
    expect(notifier.state, GoogleAuthState.signedIn);
  });

  test('transitions loading → signedOut when repo is not signed-in', () async {
    final notifier = GoogleAuthNotifier(FakeGoogleAuthRepository(startSignedIn: false));
    await Future.microtask(() {});
    expect(notifier.state, GoogleAuthState.signedOut);
  });

  test('signIn transitions to signedIn', () async {
    final notifier = GoogleAuthNotifier(FakeGoogleAuthRepository(startSignedIn: false));
    await Future.microtask(() {});
    await notifier.signIn();
    expect(notifier.state, GoogleAuthState.signedIn);
  });

  test('signOut transitions to signedOut', () async {
    final notifier = GoogleAuthNotifier(FakeGoogleAuthRepository(startSignedIn: true));
    await Future.microtask(() {});
    await notifier.signOut();
    expect(notifier.state, GoogleAuthState.signedOut);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/features/auth/google_auth_notifier_test.dart`
Expected: FAIL — `GoogleAuthNotifier` not found.

- [ ] **Step 3: Implement google_auth_providers.dart**

```dart
// lib/features/auth/presentation/google_auth_providers.dart
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum GoogleAuthState { loading, signedIn, signedOut }

class GoogleAuthNotifier extends StateNotifier<GoogleAuthState> {
  GoogleAuthNotifier(this._repo) : super(GoogleAuthState.loading) {
    _init();
  }

  final GoogleAuthRepository _repo;

  Future<void> _init() async {
    final signed = await _repo.isSignedIn();
    if (!mounted) return;
    state = signed ? GoogleAuthState.signedIn : GoogleAuthState.signedOut;
  }

  Future<void> signIn() async {
    await _repo.signIn();
    if (!mounted) return;
    state = GoogleAuthState.signedIn;
  }

  Future<void> signOut() async {
    await _repo.signOut();
    if (!mounted) return;
    state = GoogleAuthState.signedOut;
  }
}

/// Overridden in main.dart with GoogleSignInAuthRepository.
final googleAuthRepositoryProvider = Provider<GoogleAuthRepository>((ref) {
  throw UnimplementedError('Override googleAuthRepositoryProvider in main.dart');
});

final googleAuthNotifierProvider =
    StateNotifierProvider<GoogleAuthNotifier, GoogleAuthState>((ref) {
  return GoogleAuthNotifier(ref.watch(googleAuthRepositoryProvider));
});
```

- [ ] **Step 4: Implement google_sign_in_auth_repository.dart**

```dart
// lib/features/auth/data/google_sign_in_auth_repository.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInAuthRepository implements GoogleAuthRepository {
  GoogleSignInAuthRepository({
    required GoogleSignIn googleSignIn,
    required FlutterSecureStorage secureStorage,
  })  : _googleSignIn = googleSignIn,
        _secureStorage = secureStorage;

  final GoogleSignIn _googleSignIn;
  final FlutterSecureStorage _secureStorage;

  static const _tokenKey = 'google_refresh_token';

  @override
  Future<bool> isSignedIn() async {
    final stored = await _secureStorage.read(key: _tokenKey);
    if (stored != null) return true;
    return _googleSignIn.isSignedIn();
  }

  @override
  Future<void> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) throw const AuthFailure('Google Sign-In cancelled');
    final auth = await account.authentication;
    final token = auth.idToken ?? auth.accessToken;
    if (token != null) {
      await _secureStorage.write(key: _tokenKey, value: token);
    }
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _secureStorage.delete(key: _tokenKey);
  }

  @override
  Future<String> getEnumeratorId() async {
    final account = _googleSignIn.currentUser;
    if (account == null) throw const AuthFailure('Not signed in to Google');
    return account.email.split('@').first;
  }
}
```

- [ ] **Step 5: Run to confirm pass**

Run: `flutter test test/features/auth/google_auth_notifier_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/presentation/google_auth_providers.dart \
        lib/features/auth/data/google_sign_in_auth_repository.dart \
        test/features/auth/google_auth_notifier_test.dart
git commit -m "feat(auth): GoogleAuthNotifier + GoogleSignInAuthRepository (US-17 T7)"
```

---

### Task 8: Drift migration v7

**Files:**
- Modify: `lib/core/db/tables/assignments.dart`
- Modify: `lib/core/db/database.dart`
- Test: `test/core/db/migration_v6_to_v7_test.dart`
- Run codegen after schema change.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/db/migration_v6_to_v7_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion is at least 7', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(7));
  });

  test('assignments.driveModifiedTime is nullable and defaults to null', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('a1')))
        .getSingle();
    expect(row.driveModifiedTime, isNull);
    expect(row.driveFolderId, isNull);
  });

  test('assignments.driveModifiedTime and driveFolderId can be set', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a2',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            driveModifiedTime: const Value('2026-04-28T10:00:00Z'),
            driveFolderId: const Value('folder-abc'),
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('a2')))
        .getSingle();
    expect(row.driveModifiedTime, '2026-04-28T10:00:00Z');
    expect(row.driveFolderId, 'folder-abc');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/db/migration_v6_to_v7_test.dart`
Expected: FAIL — `driveModifiedTime` column not found on `AssignmentsCompanion`.

- [ ] **Step 3: Add columns to assignments table**

In `lib/core/db/tables/assignments.dart`, before the `primaryKey` getter:

```dart
  TextColumn get driveModifiedTime => text().nullable()();
  TextColumn get driveFolderId => text().nullable()();
```

- [ ] **Step 4: Update database.dart**

In `lib/core/db/database.dart`:

Change `int get schemaVersion => 6;` to:
```dart
  @override
  int get schemaVersion => 7;
```

Add after the `if (from < 6)` block inside `onUpgrade`:
```dart
          if (from < 7) {
            await m.addColumn(assignments, assignments.driveModifiedTime);
            await m.addColumn(assignments, assignments.driveFolderId);
          }
```

- [ ] **Step 5: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: exits 0, `database.g.dart` regenerated with `driveModifiedTime` and `driveFolderId` in `AssignmentsCompanion`.

- [ ] **Step 6: Run to confirm pass**

Run: `flutter test test/core/db/migration_v6_to_v7_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/core/db/tables/assignments.dart lib/core/db/database.dart \
        lib/core/db/database.g.dart test/core/db/migration_v6_to_v7_test.dart
git commit -m "feat(db): Drift migration v7 — drive_modified_time + drive_folder_id on assignments (US-17 T8)"
```

---

### Task 9: AssignmentRepository — getDriveModifiedTime + remove fetchAndUpsertCurrent

**Files:**
- Modify: `lib/features/assignment/data/assignment_repository.dart`
- Test: `test/features/assignment/assignment_repository_us17_test.dart`

Note: `fetchAndUpsertCurrent()` is removed here. Its only caller (`GetMapsNotifier.start()`) is rewritten in T17. The rest of `GetMapsNotifier` compiles without it because the call site is replaced there.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/assignment/assignment_repository_us17_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test('getDriveModifiedTime returns null for unknown assignment', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = AssignmentRepository(db: db);
    expect(await repo.getDriveModifiedTime('unknown'), isNull);
  });

  test('getDriveModifiedTime returns stored value', () async {
    final db = _db();
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'brgy-001',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            driveModifiedTime: const Value('2026-04-28T10:00:00Z'),
            createdAt: DateTime.now(),
          ),
        );
    final repo = AssignmentRepository(db: db);
    expect(
      await repo.getDriveModifiedTime('brgy-001'),
      '2026-04-28T10:00:00Z',
    );
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/features/assignment/assignment_repository_us17_test.dart`
Expected: FAIL — `getDriveModifiedTime` undefined; also constructor signature mismatch (`client` required).

- [ ] **Step 3: Update AssignmentRepository**

In `lib/features/assignment/data/assignment_repository.dart`:

1. Make `client` optional by changing the constructor to:
```dart
  AssignmentRepository({this.client, required this.db});
  final SupabaseClient? client;
```

2. Delete the entire `fetchAndUpsertCurrent()` method (lines 14–78).

3. Add `getDriveModifiedTime` before `getCurrentAssignment`:
```dart
  Future<String?> getDriveModifiedTime(String assignmentId) async {
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    return row?.driveModifiedTime;
  }
```

4. In `upsertBundle`, the `client` field is not called — leave it; it's still used by `SyncWorker` in later stories.

- [ ] **Step 4: Fix the assignmentRepositoryProvider to pass null for client**

In `lib/features/assignment/presentation/assignment_providers.dart`, the `assignmentRepositoryProvider` currently passes `client: ref.watch(supabaseClientProvider)`. Keep that unchanged — it still compiles because `client` is now `SupabaseClient?`. No change needed.

- [ ] **Step 5: Run to confirm pass**

Run: `flutter test test/features/assignment/assignment_repository_us17_test.dart`
Expected: PASS.

- [ ] **Step 6: Run full test suite to catch regressions**

Run: `flutter test`
Expected: all existing tests pass (no callers of `fetchAndUpsertCurrent` in tests).

- [ ] **Step 7: Commit**

```bash
git add lib/features/assignment/data/assignment_repository.dart \
        test/features/assignment/assignment_repository_us17_test.dart
git commit -m "feat(assignment): getDriveModifiedTime, remove fetchAndUpsertCurrent (US-17 T9)"
```

---

### Task 10: DbfParser

**Files:**
- Create: `lib/core/sync/shapefile/dbf_parser.dart`
- Test: `test/core/sync/shapefile/dbf_parser_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/sync/shapefile/dbf_parser_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal dBASE III file with the given fields and records.
Uint8List buildDbf({
  required List<({String name, int length})> fields,
  required List<Map<String, String>> records,
}) {
  final numFields = fields.length;
  final headerSize = 32 + numFields * 32 + 1;
  final recordSize = 1 + fields.fold(0, (s, f) => s + f.length);
  final totalSize = headerSize + records.length * recordSize + 1;

  final bytes = Uint8List(totalSize);
  final data = ByteData.sublistView(bytes);

  bytes[0] = 3; // dBASE III
  data.setInt32(4, records.length, Endian.little);
  data.setInt16(8, headerSize, Endian.little);
  data.setInt16(10, recordSize, Endian.little);

  for (var i = 0; i < fields.length; i++) {
    final off = 32 + i * 32;
    final name = fields[i].name;
    for (var j = 0; j < name.length && j < 11; j++) {
      bytes[off + j] = name.codeUnitAt(j);
    }
    bytes[off + 11] = 0x43; // 'C'
    bytes[off + 16] = fields[i].length;
  }
  bytes[32 + numFields * 32] = 0x0D; // header terminator

  for (var i = 0; i < records.length; i++) {
    var off = headerSize + i * recordSize;
    bytes[off] = 0x20; // active record
    off++;
    for (final field in fields) {
      final val = (records[i][field.name] ?? '').padRight(field.length);
      for (var j = 0; j < field.length; j++) {
        bytes[off + j] = j < val.length ? val.codeUnitAt(j) : 0x20;
      }
      off += field.length;
    }
  }
  bytes[totalSize - 1] = 0x1A; // EOF
  return bytes;
}

void main() {
  const parser = DbfParser();

  test('parses field names and record values', () {
    final dbf = buildDbf(
      fields: [
        (name: 'feat_id', length: 10),
        (name: 'bldg_use', length: 20),
      ],
      records: [
        {'feat_id': 'BLD-001', 'bldg_use': 'residential'},
      ],
    );
    final result = parser.parse(dbf);
    expect(result.fields, hasLength(2));
    expect(result.fields.first.name, 'feat_id');
    expect(result.records, hasLength(1));
    expect(result.records.first['feat_id'], 'BLD-001');
    expect(result.records.first['bldg_use'], 'residential');
  });

  test('trims whitespace from field values', () {
    final dbf = buildDbf(
      fields: [(name: 'feat_id', length: 10)],
      records: [
        {'feat_id': 'X1'},
      ],
    );
    final result = parser.parse(dbf);
    expect(result.records.first['feat_id'], 'X1');
  });

  test('returns zero records for empty record section', () {
    final dbf = buildDbf(fields: [(name: 'feat_id', length: 10)], records: []);
    expect(parser.parse(dbf).records, isEmpty);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/sync/shapefile/dbf_parser_test.dart`
Expected: FAIL — `DbfParser` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/sync/shapefile/dbf_parser.dart
import 'dart:typed_data';

class DbfField {
  const DbfField({required this.name, required this.type, required this.length});
  final String name;
  final String type;
  final int length;
}

class DbfResult {
  const DbfResult({required this.fields, required this.records});
  final List<DbfField> fields;
  final List<Map<String, String>> records;
}

class DbfParser {
  const DbfParser();

  DbfResult parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final recordCount = data.getInt32(4, Endian.little);
    final headerSize = data.getInt16(8, Endian.little);
    final recordSize = data.getInt16(10, Endian.little);

    final fields = <DbfField>[];
    var offset = 32;
    while (offset < headerSize - 1 && bytes[offset] != 0x0D) {
      final nameBytes = bytes.sublist(offset, offset + 11);
      final nullIdx = nameBytes.indexOf(0);
      final name = String.fromCharCodes(
        nullIdx >= 0 ? nameBytes.sublist(0, nullIdx) : nameBytes,
      );
      final type = String.fromCharCode(bytes[offset + 11]);
      final length = bytes[offset + 16];
      fields.add(DbfField(name: name, type: type, length: length));
      offset += 32;
    }

    final records = <Map<String, String>>[];
    var recordOffset = headerSize;
    for (var i = 0; i < recordCount; i++) {
      if (recordOffset >= bytes.length) break;
      final deletionFlag = bytes[recordOffset];
      if (deletionFlag != 0x2A) {
        var fieldOffset = recordOffset + 1;
        final record = <String, String>{};
        for (final field in fields) {
          final end = (fieldOffset + field.length).clamp(0, bytes.length);
          final raw = String.fromCharCodes(bytes.sublist(fieldOffset, end));
          record[field.name] = raw.trim();
          fieldOffset += field.length;
        }
        records.add(record);
      }
      recordOffset += recordSize;
    }

    return DbfResult(fields: fields, records: records);
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/core/sync/shapefile/dbf_parser_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/dbf_parser.dart \
        test/core/sync/shapefile/dbf_parser_test.dart
git commit -m "feat(shapefile): DbfParser (US-17 T10)"
```

---

### Task 11: ShpParser

**Files:**
- Create: `lib/core/sync/shapefile/shp_parser.dart`
- Test: `test/core/sync/shapefile/shp_parser_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/sync/shapefile/shp_parser_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/shp_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal SHP containing a single polygon or polyline.
Uint8List buildPolygonShp(List<List<List<double>>> rings) {
  return _buildShp(shapeType: 5, parts: rings);
}

Uint8List buildPolylineShp(List<List<List<double>>> parts) {
  return _buildShp(shapeType: 3, parts: parts);
}

Uint8List _buildShp({
  required int shapeType,
  required List<List<List<double>>> parts,
}) {
  final totalPoints = parts.fold(0, (s, r) => s + r.length);
  final numParts = parts.length;
  final contentBytes =
      4 + 32 + 4 + 4 + numParts * 4 + totalPoints * 16; // type+bbox+np+npts+parts+points
  final totalBytes = 100 + 8 + contentBytes;
  final bytes = Uint8List(totalBytes);
  final data = ByteData.sublistView(bytes);

  // File header
  data.setInt32(0, 9994, Endian.big);
  data.setInt32(24, totalBytes ~/ 2, Endian.big);
  data.setInt32(28, 1000, Endian.little);
  data.setInt32(32, shapeType, Endian.little);

  // Record header
  data.setInt32(100, 1, Endian.big);
  data.setInt32(104, contentBytes ~/ 2, Endian.big);

  // Content
  var off = 108;
  data.setInt32(off, shapeType, Endian.little);
  off += 4;
  off += 32; // bounding box (zeroed)
  data.setInt32(off, numParts, Endian.little);
  off += 4;
  data.setInt32(off, totalPoints, Endian.little);
  off += 4;

  var partStart = 0;
  for (var i = 0; i < numParts; i++) {
    data.setInt32(off, partStart, Endian.little);
    off += 4;
    partStart += parts[i].length;
  }
  for (final ring in parts) {
    for (final pt in ring) {
      data.setFloat64(off, pt[0], Endian.little);
      off += 8;
      data.setFloat64(off, pt[1], Endian.little);
      off += 8;
    }
  }
  return bytes;
}

void main() {
  const parser = ShpParser();

  final square = [
    [0.0, 0.0],
    [1.0, 0.0],
    [1.0, 1.0],
    [0.0, 1.0],
    [0.0, 0.0],
  ];

  test('parses polygon → ShpPolygon with correct ring coordinates', () {
    final shp = buildPolygonShp([square]);
    final result = parser.parse(shp);
    expect(result, hasLength(1));
    final geom = result.first as ShpPolygon;
    expect(geom.rings, hasLength(1));
    expect(geom.rings.first, hasLength(5));
    expect(geom.rings.first.first[0], closeTo(0.0, 1e-9));
  });

  test('parses polyline → ShpPolyline with correct part coordinates', () {
    final line = [[0.0, 0.0], [1.0, 1.0]];
    final shp = buildPolylineShp([line]);
    final result = parser.parse(shp);
    expect(result, hasLength(1));
    final geom = result.first as ShpPolyline;
    expect(geom.parts, hasLength(1));
    expect(geom.parts.first.last[0], closeTo(1.0, 1e-9));
  });

  test('polygon toGeoJson produces Polygon type', () {
    final shp = buildPolygonShp([square]);
    final geom = parser.parse(shp).first as ShpPolygon;
    final json = geom.toGeoJson();
    expect(json['type'], 'Polygon');
    expect((json['coordinates'] as List).first, hasLength(5));
  });

  test('polyline toGeoJson produces LineString for single part', () {
    final line = [[0.0, 0.0], [1.0, 1.0]];
    final shp = buildPolylineShp([line]);
    final geom = parser.parse(shp).first as ShpPolyline;
    expect(geom.toGeoJson()['type'], 'LineString');
  });

  test('polyline toGeoJson produces MultiLineString for multiple parts', () {
    final line = [[0.0, 0.0], [1.0, 1.0]];
    final shp = buildPolylineShp([line, line]);
    final geom = parser.parse(shp).first as ShpPolyline;
    expect(geom.toGeoJson()['type'], 'MultiLineString');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/sync/shapefile/shp_parser_test.dart`
Expected: FAIL — `ShpParser` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/sync/shapefile/shp_parser.dart
import 'dart:typed_data';

sealed class ShpGeometry {
  const ShpGeometry();
  Map<String, dynamic> toGeoJson();
}

class ShpPolygon extends ShpGeometry {
  const ShpPolygon(this.rings);
  final List<List<List<double>>> rings;

  @override
  Map<String, dynamic> toGeoJson() => {
        'type': 'Polygon',
        'coordinates': rings,
      };
}

class ShpPolyline extends ShpGeometry {
  const ShpPolyline(this.parts);
  final List<List<List<double>>> parts;

  @override
  Map<String, dynamic> toGeoJson() {
    if (parts.length == 1) {
      return {'type': 'LineString', 'coordinates': parts.first};
    }
    return {'type': 'MultiLineString', 'coordinates': parts};
  }
}

class ShpParser {
  const ShpParser();

  List<ShpGeometry> parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final geometries = <ShpGeometry>[];
    var offset = 100; // skip file header

    while (offset + 8 <= bytes.length) {
      final contentWords = data.getInt32(offset + 4, Endian.big);
      final contentBytes = contentWords * 2;
      offset += 8;
      if (offset + contentBytes > bytes.length) break;

      final shapeType = data.getInt32(offset, Endian.little);

      if (shapeType == 5 || shapeType == 15 || shapeType == 25) {
        geometries.add(_parsePolygon(data, offset));
      } else if (shapeType == 3 || shapeType == 13 || shapeType == 23) {
        geometries.add(_parsePolyline(data, offset));
      }

      offset += contentBytes;
    }

    return geometries;
  }

  ShpPolygon _parsePolygon(ByteData data, int offset) {
    final numParts = data.getInt32(offset + 36, Endian.little);
    final numPoints = data.getInt32(offset + 40, Endian.little);
    return ShpPolygon(_readParts(data, offset, numParts, numPoints));
  }

  ShpPolyline _parsePolyline(ByteData data, int offset) {
    final numParts = data.getInt32(offset + 36, Endian.little);
    final numPoints = data.getInt32(offset + 40, Endian.little);
    return ShpPolyline(_readParts(data, offset, numParts, numPoints));
  }

  List<List<List<double>>> _readParts(
    ByteData data,
    int offset,
    int numParts,
    int numPoints,
  ) {
    final partIndices = <int>[];
    for (var i = 0; i < numParts; i++) {
      partIndices.add(data.getInt32(offset + 44 + i * 4, Endian.little));
    }

    final pointsBase = offset + 44 + numParts * 4;
    final allPoints = <List<double>>[];
    for (var i = 0; i < numPoints; i++) {
      final x = data.getFloat64(pointsBase + i * 16, Endian.little);
      final y = data.getFloat64(pointsBase + i * 16 + 8, Endian.little);
      allPoints.add([x, y]);
    }

    final result = <List<List<double>>>[];
    for (var i = 0; i < numParts; i++) {
      final start = partIndices[i];
      final end = i < numParts - 1 ? partIndices[i + 1] : numPoints;
      result.add(allPoints.sublist(start, end));
    }
    return result;
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/core/sync/shapefile/shp_parser_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/shp_parser.dart \
        test/core/sync/shapefile/shp_parser_test.dart
git commit -m "feat(shapefile): ShpParser (US-17 T11)"
```

---

### Task 12: ShapefileValidator

**Files:**
- Create: `lib/core/sync/shapefile/shapefile_validator.dart`
- Test: `test/core/sync/shapefile/shapefile_validator_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/sync/shapefile/shapefile_validator_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const _validPrj =
    'PROJCS["WGS_1984_UTM_Zone_51N",...AUTHORITY["EPSG","32651"]]';

Map<String, Uint8List> _baseFiles() => {
      'boundary.shp': Uint8List(1),
      'boundary.dbf': Uint8List(1),
      'boundary.shx': Uint8List(1),
      'boundary.prj': Uint8List.fromList(_validPrj.codeUnits),
      'buildings.shp': Uint8List(1),
      'buildings.dbf': Uint8List(1),
      'buildings.shx': Uint8List(1),
      'buildings.prj': Uint8List.fromList(_validPrj.codeUnits),
      'roads.shp': Uint8List(1),
      'roads.dbf': Uint8List(1),
      'roads.shx': Uint8List(1),
      'roads.prj': Uint8List.fromList(_validPrj.codeUnits),
    };

Map<String, List<DbfField>> _validFields() => {
      'boundary': [DbfField(name: 'feat_id', type: 'C', length: 10)],
      'buildings': [
        DbfField(name: 'feat_id', type: 'C', length: 10),
        DbfField(name: 'bldg_use', type: 'C', length: 50),
        DbfField(name: 'bldg_type', type: 'C', length: 50),
      ],
      'roads': [
        DbfField(name: 'feat_id', type: 'C', length: 10),
        DbfField(name: 'road_type', type: 'C', length: 50),
      ],
    };

void main() {
  const v = ShapefileValidator();

  test('valid files and fields → does not throw', () {
    expect(() => v.validate(_baseFiles(), _validFields()), returnsNormally);
  });

  test('missing buildings.shp → throws ShapefileValidationFailure', () {
    final files = _baseFiles()..remove('buildings.shp');
    expect(
      () => v.validate(files, _validFields()),
      throwsA(isA<ShapefileValidationFailure>()
          .having((f) => f.message, 'message', contains('buildings.shp'))),
    );
  });

  test('wrong CRS in boundary.prj → throws with CRS info', () {
    final files = _baseFiles();
    files['boundary.prj'] =
        Uint8List.fromList('GEOGCS["GCS_WGS_1984"...]'.codeUnits);
    expect(
      () => v.validate(files, _validFields()),
      throwsA(isA<ShapefileValidationFailure>()
          .having((f) => f.message, 'message', contains('32651'))),
    );
  });

  test('missing bldg_use column → throws citing column', () {
    final fields = _validFields();
    fields['buildings'] = [DbfField(name: 'feat_id', type: 'C', length: 10)];
    expect(
      () => v.validate(_baseFiles(), fields),
      throwsA(isA<ShapefileValidationFailure>()
          .having((f) => f.message, 'message', contains('bldg_use'))),
    );
  });

  test('missing road_type column → throws citing column', () {
    final fields = _validFields();
    fields['roads'] = [DbfField(name: 'feat_id', type: 'C', length: 10)];
    expect(
      () => v.validate(_baseFiles(), fields),
      throwsA(isA<ShapefileValidationFailure>()
          .having((f) => f.message, 'message', contains('road_type'))),
    );
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/sync/shapefile/shapefile_validator_test.dart`
Expected: FAIL — `ShapefileValidator` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/sync/shapefile/shapefile_validator.dart
import 'dart:typed_data';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';

class ShapefileValidator {
  const ShapefileValidator();

  static const _layers = ['boundary', 'buildings', 'roads'];
  static const _extensions = ['.shp', '.dbf', '.shx', '.prj'];
  static const _buildingCols = ['feat_id', 'bldg_use', 'bldg_type'];
  static const _roadCols = ['feat_id', 'road_type'];

  void validate(
    Map<String, Uint8List> files,
    Map<String, List<DbfField>> dbfFields,
  ) {
    for (final layer in _layers) {
      for (final ext in _extensions) {
        if (!files.containsKey('$layer$ext')) {
          throw ShapefileValidationFailure('Missing required file: $layer$ext');
        }
      }
    }

    for (final layer in _layers) {
      final prj = String.fromCharCodes(files['$layer.prj']!);
      if (!prj.contains('32651')) {
        throw ShapefileValidationFailure(
          '$layer.prj does not use EPSG:32651. '
          'Found: ${prj.length > 60 ? prj.substring(0, 60) : prj}',
        );
      }
    }

    _checkColumns('buildings', dbfFields['buildings'] ?? [], _buildingCols);
    _checkColumns('roads', dbfFields['roads'] ?? [], _roadCols);
  }

  void _checkColumns(
    String layer,
    List<DbfField> fields,
    List<String> required,
  ) {
    final names = fields.map((f) => f.name).toSet();
    for (final col in required) {
      if (!names.contains(col)) {
        throw ShapefileValidationFailure(
          "$layer.dbf is missing required column '$col'",
        );
      }
    }
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/core/sync/shapefile/shapefile_validator_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/shapefile_validator.dart \
        test/core/sync/shapefile/shapefile_validator_test.dart
git commit -m "feat(shapefile): ShapefileValidator (US-17 T12)"
```

---

### Task 13: Reprojector

**Files:**
- Create: `lib/core/sync/shapefile/reprojector.dart`
- Test: `test/core/sync/shapefile/reprojector_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/sync/shapefile/reprojector_test.dart
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Reprojector reprojector;

  setUp(() => reprojector = Reprojector());

  test('central-meridian easting maps to exactly 123° longitude', () {
    // (500000, y) in UTM 51N lies exactly on the 123°E central meridian.
    final result = reprojector.reproject(500000.0, 1000000.0);
    expect(result[0], closeTo(123.0, 0.001)); // longitude
    expect(result[1], closeTo(9.04, 0.05));   // latitude ~9°N
  });

  test('reprojectRing transforms all points in a ring', () {
    final ring = [
      [500000.0, 1000000.0],
      [501000.0, 1000000.0],
      [501000.0, 1001000.0],
      [500000.0, 1001000.0],
      [500000.0, 1000000.0],
    ];
    final result = reprojector.reprojectRing(ring);
    expect(result, hasLength(5));
    expect(result.first[0], closeTo(123.0, 0.01));
    expect(result.last[0], closeTo(123.0, 0.01));
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/sync/shapefile/reprojector_test.dart`
Expected: FAIL — `Reprojector` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/sync/shapefile/reprojector.dart
import 'package:proj4dart/proj4dart.dart';

class Reprojector {
  Reprojector() {
    _from = Projection.parse(
      '+proj=utm +zone=51 +datum=WGS84 +units=m +no_defs',
    );
    _to = Projection.parse('+proj=longlat +datum=WGS84 +no_defs');
  }

  late final Projection _from;
  late final Projection _to;

  /// Returns [longitude, latitude] in EPSG:4326 for a given UTM 51N coordinate.
  List<double> reproject(double easting, double northing) {
    final pt = _from.transform(_to, Point(x: easting, y: northing));
    return [pt.x, pt.y];
  }

  List<List<double>> reprojectRing(List<List<double>> ring) =>
      ring.map((pt) => reproject(pt[0], pt[1])).toList();
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/core/sync/shapefile/reprojector_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/reprojector.dart \
        test/core/sync/shapefile/reprojector_test.dart
git commit -m "feat(shapefile): Reprojector EPSG:32651→4326 via proj4dart (US-17 T13)"
```

---

### Task 14: ShapefileImporter

**Files:**
- Create: `lib/core/sync/shapefile/shapefile_importer.dart`
- Test: `test/core/sync/shapefile/shapefile_importer_test.dart`

The test constructs a complete in-memory zip to exercise the full pipeline.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/sync/shapefile/shapefile_importer_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:flutter_test/flutter_test.dart';

// ── helpers ────────────────────────────────────────────────────────────────

Uint8List _buildDbf({
  required List<({String name, int length})> fields,
  required List<Map<String, String>> records,
}) {
  final numFields = fields.length;
  final headerSize = 32 + numFields * 32 + 1;
  final recordSize = 1 + fields.fold(0, (s, f) => s + f.length);
  final totalSize = headerSize + records.length * recordSize + 1;
  final bytes = Uint8List(totalSize);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 3;
  data.setInt32(4, records.length, Endian.little);
  data.setInt16(8, headerSize, Endian.little);
  data.setInt16(10, recordSize, Endian.little);
  for (var i = 0; i < fields.length; i++) {
    final off = 32 + i * 32;
    final name = fields[i].name;
    for (var j = 0; j < name.length && j < 11; j++) {
      bytes[off + j] = name.codeUnitAt(j);
    }
    bytes[off + 11] = 0x43;
    bytes[off + 16] = fields[i].length;
  }
  bytes[32 + numFields * 32] = 0x0D;
  for (var i = 0; i < records.length; i++) {
    var off = headerSize + i * recordSize;
    bytes[off++] = 0x20;
    for (final f in fields) {
      final val = (records[i][f.name] ?? '').padRight(f.length);
      for (var j = 0; j < f.length; j++) {
        bytes[off + j] = j < val.length ? val.codeUnitAt(j) : 0x20;
      }
      off += f.length;
    }
  }
  bytes[totalSize - 1] = 0x1A;
  return bytes;
}

Uint8List _buildPolygonShp(List<List<List<double>>> rings) {
  final total = rings.fold(0, (s, r) => s + r.length);
  final content = 4 + 32 + 4 + 4 + rings.length * 4 + total * 16;
  final all = 100 + 8 + content;
  final bytes = Uint8List(all);
  final data = ByteData.sublistView(bytes);
  data.setInt32(0, 9994, Endian.big);
  data.setInt32(24, all ~/ 2, Endian.big);
  data.setInt32(28, 1000, Endian.little);
  data.setInt32(32, 5, Endian.little);
  data.setInt32(100, 1, Endian.big);
  data.setInt32(104, content ~/ 2, Endian.big);
  var off = 108;
  data.setInt32(off, 5, Endian.little); off += 4 + 32;
  data.setInt32(off, rings.length, Endian.little); off += 4;
  data.setInt32(off, total, Endian.little); off += 4;
  var ps = 0;
  for (var i = 0; i < rings.length; i++) {
    data.setInt32(off, ps, Endian.little); off += 4; ps += rings[i].length;
  }
  for (final r in rings) {
    for (final p in r) {
      data.setFloat64(off, p[0], Endian.little); off += 8;
      data.setFloat64(off, p[1], Endian.little); off += 8;
    }
  }
  return bytes;
}

Uint8List _buildPolylineShp(List<List<List<double>>> parts) {
  final total = parts.fold(0, (s, r) => s + r.length);
  final content = 4 + 32 + 4 + 4 + parts.length * 4 + total * 16;
  final all = 100 + 8 + content;
  final bytes = Uint8List(all);
  final data = ByteData.sublistView(bytes);
  data.setInt32(0, 9994, Endian.big);
  data.setInt32(24, all ~/ 2, Endian.big);
  data.setInt32(28, 1000, Endian.little);
  data.setInt32(32, 3, Endian.little);
  data.setInt32(100, 1, Endian.big);
  data.setInt32(104, content ~/ 2, Endian.big);
  var off = 108;
  data.setInt32(off, 3, Endian.little); off += 4 + 32;
  data.setInt32(off, parts.length, Endian.little); off += 4;
  data.setInt32(off, total, Endian.little); off += 4;
  var ps = 0;
  for (var i = 0; i < parts.length; i++) {
    data.setInt32(off, ps, Endian.little); off += 4; ps += parts[i].length;
  }
  for (final r in parts) {
    for (final p in r) {
      data.setFloat64(off, p[0], Endian.little); off += 8;
      data.setFloat64(off, p[1], Endian.little); off += 8;
    }
  }
  return bytes;
}

const _prj = 'PROJCS["WGS_1984_UTM_Zone_51N",AUTHORITY["EPSG","32651"]]';

Uint8List _makeValidZip() {
  final arc = Archive();

  final boundaryRing = [
    [500000.0, 1000000.0], [501000.0, 1000000.0],
    [501000.0, 1001000.0], [500000.0, 1001000.0], [500000.0, 1000000.0],
  ];
  arc
    ..addFile(ArchiveFile('boundary.shp', -1, _buildPolygonShp([boundaryRing])))
    ..addFile(ArchiveFile('boundary.dbf', -1,
        _buildDbf(fields: [(name: 'feat_id', length: 10)],
            records: [{'feat_id': 'BOUND-1'}])))
    ..addFile(ArchiveFile('boundary.shx', -1, Uint8List(100)))
    ..addFile(ArchiveFile('boundary.prj', -1, utf8.encode(_prj)));

  final bldgRing = [
    [500100.0, 1000100.0], [500200.0, 1000100.0],
    [500200.0, 1000200.0], [500100.0, 1000200.0], [500100.0, 1000100.0],
  ];
  arc
    ..addFile(ArchiveFile('buildings.shp', -1, _buildPolygonShp([bldgRing])))
    ..addFile(ArchiveFile('buildings.dbf', -1,
        _buildDbf(
          fields: [
            (name: 'feat_id', length: 10),
            (name: 'bldg_use', length: 20),
            (name: 'bldg_type', length: 20),
          ],
          records: [{'feat_id': 'BLD-001', 'bldg_use': 'residential', 'bldg_type': 'house'}],
        )))
    ..addFile(ArchiveFile('buildings.shx', -1, Uint8List(100)))
    ..addFile(ArchiveFile('buildings.prj', -1, utf8.encode(_prj)));

  final roadLine = [[500050.0, 1000050.0], [500150.0, 1000150.0]];
  arc
    ..addFile(ArchiveFile('roads.shp', -1, _buildPolylineShp([roadLine])))
    ..addFile(ArchiveFile('roads.dbf', -1,
        _buildDbf(
          fields: [(name: 'feat_id', length: 10), (name: 'road_type', length: 20)],
          records: [{'feat_id': 'RD-001', 'road_type': 'local'}],
        )))
    ..addFile(ArchiveFile('roads.shx', -1, Uint8List(100)))
    ..addFile(ArchiveFile('roads.prj', -1, utf8.encode(_prj)));

  return Uint8List.fromList(ZipEncoder().encode(arc)!);
}

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;
  late ShapefileImporter importer;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    importer = ShapefileImporter(
      db: db,
      validator: const ShapefileValidator(),
      dbfParser: const DbfParser(),
      reprojector: Reprojector(),
    );
  });

  tearDown(() => db.close());

  test('valid zip → assignment row + 1 building + 1 road in Drift', () async {
    final result = await importer.importInputZip(
      _makeValidZip(),
      'brgy-001',
      '2026-04-28T10:00:00Z',
      'folder-abc',
      'test-enumerator',
    );

    expect(result.buildingCount, 1);
    expect(result.roadCount, 1);

    final assignment = await (db.select(db.assignments)
          ..where((t) => t.id.equals('brgy-001')))
        .getSingleOrNull();
    expect(assignment, isNotNull);
    expect(assignment!.driveModifiedTime, '2026-04-28T10:00:00Z');
    expect(assignment.driveFolderId, 'folder-abc');

    final features = await (db.select(db.features)
          ..where((t) => t.assignmentId.equals('brgy-001')))
        .get();
    expect(features, hasLength(2));
    expect(features.where((f) => f.featureType == 'building'), hasLength(1));
    expect(features.where((f) => f.featureType == 'road'), hasLength(1));
  });

  test('missing layer → ShapefileValidationFailure, no Drift writes', () async {
    final arc = Archive();
    arc.addFile(ArchiveFile('boundary.shp', -1, Uint8List(0)));
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(arc)!);

    expect(
      () => importer.importInputZip(zipBytes, 'x', 't', 'f', 'e'),
      throwsA(isA<ShapefileValidationFailure>()),
    );

    final rows = await db.select(db.assignments).get();
    expect(rows, isEmpty);
  });

  test('corrupt zip → throws, no Drift writes', () async {
    expect(
      () => importer.importInputZip(Uint8List(10), 'x', 't', 'f', 'e'),
      throwsA(anything),
    );
    expect(await db.select(db.assignments).get(), isEmpty);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/sync/shapefile/shapefile_importer_test.dart`
Expected: FAIL — `ShapefileImporter` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/sync/shapefile/shapefile_importer.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/sync/shapefile/shp_parser.dart';

class ImportResult {
  const ImportResult({
    required this.buildingCount,
    required this.roadCount,
    required this.boundaryGeojson,
  });
  final int buildingCount;
  final int roadCount;
  final String boundaryGeojson;
}

class ShapefileImporter {
  ShapefileImporter({
    required this.db,
    required this.validator,
    required this.dbfParser,
    required this.reprojector,
  });

  final AppDatabase db;
  final ShapefileValidator validator;
  final DbfParser dbfParser;
  final Reprojector reprojector;

  final _shpParser = const ShpParser();

  Future<ImportResult> importInputZip(
    Uint8List zipBytes,
    String assignmentId,
    String driveModifiedTime,
    String driveFolderId,
    String enumeratorId,
  ) async {
    // Unzip
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final files = <String, Uint8List>{};
    for (final f in archive) {
      if (f.isFile) {
        files[f.name] = Uint8List.fromList(f.content as List<int>);
      }
    }

    // Parse DBF fields for validation
    final boundaryFields = dbfParser.parse(files['boundary.dbf']!).fields;
    final buildingFields = dbfParser.parse(files['buildings.dbf']!).fields;
    final roadFields = dbfParser.parse(files['roads.dbf']!).fields;

    validator.validate(files, {
      'boundary': boundaryFields,
      'buildings': buildingFields,
      'roads': roadFields,
    });

    // Parse all geometries and records
    final boundaryGeoms = _shpParser.parse(files['boundary.shp']!);
    final buildingGeoms = _shpParser.parse(files['buildings.shp']!);
    final roadGeoms = _shpParser.parse(files['roads.shp']!);

    final buildingRecords = dbfParser.parse(files['buildings.dbf']!).records;
    final roadRecords = dbfParser.parse(files['roads.dbf']!).records;

    // Reproject boundary (first polygon, all rings)
    final boundaryGeojson = _reprojectGeom(boundaryGeoms.first);

    // Write everything in a single Drift transaction
    await db.transaction(() async {
      await db.into(db.assignments).insertOnConflictUpdate(
            AssignmentsCompanion.insert(
              id: assignmentId,
              enumeratorId: enumeratorId,
              campaignId: assignmentId,
              boundaryPolygonGeojson: jsonEncode(boundaryGeojson),
              downloadedAt: Value(DateTime.now()),
              driveModifiedTime: Value(driveModifiedTime),
              driveFolderId: Value(driveFolderId),
              createdAt: DateTime.now(),
            ),
          );

      for (var i = 0; i < buildingRecords.length; i++) {
        if (i >= buildingGeoms.length) break;
        final featId = buildingRecords[i]['feat_id'] ?? 'bld-$i';
        await db.into(db.features).insertOnConflictUpdate(
              FeaturesCompanion.insert(
                id: '$assignmentId/$featId',
                assignmentId: assignmentId,
                featureType: 'building',
                geometryGeojson: jsonEncode(_reprojectGeom(buildingGeoms[i])),
                isNew: const Value(false),
                createdAt: DateTime.now(),
              ),
            );
      }

      for (var i = 0; i < roadRecords.length; i++) {
        if (i >= roadGeoms.length) break;
        final featId = roadRecords[i]['feat_id'] ?? 'rd-$i';
        await db.into(db.features).insertOnConflictUpdate(
              FeaturesCompanion.insert(
                id: '$assignmentId/$featId',
                assignmentId: assignmentId,
                featureType: 'road',
                geometryGeojson: jsonEncode(_reprojectGeom(roadGeoms[i])),
                isNew: const Value(false),
                createdAt: DateTime.now(),
              ),
            );
      }
    });

    return ImportResult(
      buildingCount: buildingRecords.length,
      roadCount: roadRecords.length,
      boundaryGeojson: jsonEncode(boundaryGeojson),
    );
  }

  Map<String, dynamic> _reprojectGeom(ShpGeometry geom) {
    return switch (geom) {
      ShpPolygon(:final rings) => {
          'type': 'Polygon',
          'coordinates': rings.map(reprojector.reprojectRing).toList(),
        },
      ShpPolyline(:final parts) when parts.length == 1 => {
          'type': 'LineString',
          'coordinates': reprojector.reprojectRing(parts.first),
        },
      ShpPolyline(:final parts) => {
          'type': 'MultiLineString',
          'coordinates': parts.map(reprojector.reprojectRing).toList(),
        },
    };
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/core/sync/shapefile/shapefile_importer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/shapefile_importer.dart \
        test/core/sync/shapefile/shapefile_importer_test.dart
git commit -m "feat(shapefile): ShapefileImporter unzip→validate→reproject→Drift (US-17 T14)"
```

---

### Task 15: GoogleDriveApi

**Files:**
- Create: `lib/core/drive/google_drive_api.dart`

No unit tests: requires real Google credentials. Tested via `FakeDriveApi` in all notifier tests; integration-tested manually on-device.

- [ ] **Step 1: Implement**

```dart
// lib/core/drive/google_drive_api.dart
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;

class GoogleDriveApi implements DriveApi {
  GoogleDriveApi({required GoogleSignIn googleSignIn})
      : _googleSignIn = googleSignIn;

  final GoogleSignIn _googleSignIn;

  // Populated during listAssignments() for use in download methods.
  final _fileIdCache = <String, String>{}; // assignmentId → inputZip fileId

  Future<gdrive.DriveApi> _api() async {
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) throw const AuthFailure('Not signed in to Google');
    return gdrive.DriveApi(client);
  }

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    final api = await _api();

    // Locate /firecheck folder
    final firecheckResult = await api.files.list(
      q: "name = 'firecheck' and mimeType = 'application/vnd.google-apps.folder'"
          " and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final firecheckId = firecheckResult.files?.firstOrNull?.id;
    if (firecheckId == null) return [];

    // Locate /firecheck/inbox
    final inboxResult = await api.files.list(
      q: "name = 'inbox' and mimeType = 'application/vnd.google-apps.folder'"
          " and '$firecheckId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final inboxId = inboxResult.files?.firstOrNull?.id;
    if (inboxId == null) return [];

    // List assignment subfolders
    final foldersResult = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder'"
          " and '$inboxId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );

    final assignments = <DriveAssignment>[];
    for (final folder in foldersResult.files ?? []) {
      final zipResult = await api.files.list(
        q: "name = 'input.zip' and '${folder.id}' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,modifiedTime)',
      );
      final zip = zipResult.files?.firstOrNull;
      if (zip == null) continue;

      final fileId = zip.id!;
      final assignmentId = folder.name!;
      _fileIdCache[assignmentId] = fileId;

      assignments.add(DriveAssignment(
        assignmentId: assignmentId,
        inputZipFileId: fileId,
        inputZipModifiedTime: zip.modifiedTime!.toIso8601String(),
        driveFolderId: folder.id!,
      ));
    }

    return assignments;
  }

  @override
  Future<int> getInputZipSize(String assignmentId) async {
    final fileId = _fileIdCache[assignmentId];
    if (fileId == null) return 0;
    final api = await _api();
    final meta = await api.files.get(fileId, $fields: 'size') as gdrive.File;
    return int.tryParse(meta.size ?? '0') ?? 0;
  }

  @override
  Stream<DriveDownloadEvent> downloadInputZip(String assignmentId) async* {
    final fileId = _fileIdCache[assignmentId];
    if (fileId == null) throw const NetworkFailure('Assignment file not cached');
    final api = await _api();

    final media = await api.files.get(
      fileId,
      downloadOptions: gdrive.DownloadOptions.fullMedia,
    ) as gdrive.Media;

    final chunks = <int>[];
    var downloaded = 0;
    final total = media.length ?? 0;

    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
      downloaded += chunk.length;
      yield DriveDownloadProgress(downloaded: downloaded, total: total);
    }

    yield DriveDownloadComplete(Uint8List.fromList(chunks));
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/drive/google_drive_api.dart
git commit -m "feat(drive): GoogleDriveApi real Drive v3 impl (US-17 T15)"
```

---

### Task 16: GetMapsState expansion

**Files:**
- Modify: `lib/features/assignment/domain/get_maps_state.dart`
- Test: `test/features/assignment/get_maps_state_test.dart` (modify existing)

- [ ] **Step 1: Write the failing test**

Append to `test/features/assignment/get_maps_state_test.dart` (or create it if absent):

```dart
// test/features/assignment/get_maps_state_test.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('overallProgress', () {
    test('Idle → 0', () => expect(const Idle().overallProgress, 0));

    test('DiscoveringAssignments → 0.02', () {
      expect(const DiscoveringAssignments().overallProgress, 0.02);
    });

    test('PickingAssignment → 0.02', () {
      expect(
        PickingAssignment(assignments: [], selectedId: '').overallProgress,
        0.02,
      );
    });

    test('InsufficientStorage → 0.02', () {
      expect(
        InsufficientStorage(requiredBytes: 100, availableBytes: 10)
            .overallProgress,
        0.02,
      );
    });

    test('DownloadingShapefiles mid-way → between 0.02 and 0.30', () {
      final s = DownloadingShapefiles(downloaded: 500, total: 1000);
      expect(s.overallProgress, closeTo(0.02 + 0.28 * 0.5, 1e-9));
    });

    test('DownloadingShapefiles zero total → 0.02', () {
      expect(
        DownloadingShapefiles(downloaded: 0, total: 0).overallProgress,
        0.02,
      );
    });

    test('ImportingShapefiles → 0.35', () {
      expect(const ImportingShapefiles().overallProgress, 0.35);
    });

    test('DownloadingTiles mid-way → between 0.35 and 1.0', () {
      final s = DownloadingTiles(downloadedBytes: 1, totalBytes: 2);
      expect(s.overallProgress, closeTo(0.35 + 0.65 * 0.5, 1e-9));
    });

    test('Ready → 1', () {
      expect(Ready(featureCount: 0, totalBytes: 0).overallProgress, 1);
    });

    test('Cancelled → 0', () => expect(const Cancelled().overallProgress, 0));

    test('GetMapsError → 0', () {
      expect(
        GetMapsError(const NetworkFailure()).overallProgress,
        0,
      );
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/features/assignment/get_maps_state_test.dart`
Expected: FAIL — `DiscoveringAssignments` etc. not found.

- [ ] **Step 3: Rewrite get_maps_state.dart**

```dart
// lib/features/assignment/domain/get_maps_state.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/errors/failure.dart';

sealed class GetMapsState {
  const GetMapsState();
  double get overallProgress;
}

class Idle extends GetMapsState {
  const Idle();
  @override
  double get overallProgress => 0;
}

class DiscoveringAssignments extends GetMapsState {
  const DiscoveringAssignments();
  @override
  double get overallProgress => 0.02;
}

class PickingAssignment extends GetMapsState {
  const PickingAssignment({required this.assignments, required this.selectedId});
  final List<DriveAssignment> assignments;
  final String selectedId;
  @override
  double get overallProgress => 0.02;
}

class InsufficientStorage extends GetMapsState {
  const InsufficientStorage({
    required this.requiredBytes,
    required this.availableBytes,
  });
  final int requiredBytes;
  final int availableBytes;
  @override
  double get overallProgress => 0.02;
}

class DownloadingShapefiles extends GetMapsState {
  const DownloadingShapefiles({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
  @override
  double get overallProgress =>
      0.02 + 0.28 * (total == 0 ? 0 : downloaded / total);
}

class ImportingShapefiles extends GetMapsState {
  const ImportingShapefiles();
  @override
  double get overallProgress => 0.35;
}

class DownloadingTiles extends GetMapsState {
  const DownloadingTiles({
    required this.downloadedBytes,
    required this.totalBytes,
  });
  final int downloadedBytes;
  final int totalBytes;
  double get tileProgress =>
      totalBytes == 0 ? 0 : downloadedBytes / totalBytes;
  @override
  double get overallProgress => 0.35 + 0.65 * tileProgress;
}

class Ready extends GetMapsState {
  const Ready({required this.featureCount, required this.totalBytes});
  final int featureCount;
  final int totalBytes;
  @override
  double get overallProgress => 1;
}

class Cancelled extends GetMapsState {
  const Cancelled();
  @override
  double get overallProgress => 0;
}

class GetMapsError extends GetMapsState {
  const GetMapsError(this.failure);
  final Failure failure;
  @override
  double get overallProgress => 0;
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/features/assignment/get_maps_state_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/assignment/domain/get_maps_state.dart \
        test/features/assignment/get_maps_state_test.dart
git commit -m "feat(get-maps): GetMapsState expansion — new states + updated overallProgress (US-17 T16)"
```

---

### Task 17: GetMapsNotifier expansion

**Files:**
- Modify: `lib/features/assignment/presentation/assignment_providers.dart`
- Test: `test/features/assignment/get_maps_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/assignment/get_maps_notifier_test.dart
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/drive/fake_drive_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal valid zip builder (same helpers as T14 test — copy here or extract to test helper).
// For brevity, we use a complete fake that bypasses real zip parsing by injecting a custom
// ShapefileImporter stub. But for a real integration test, reuse _makeValidZip() from T14.
//
// Here we test notifier state transitions using FakeDriveApi + a ShapefileImporter backed by
// an in-memory DB so actual zip parsing is exercised end-to-end in the importer tests.
// In these notifier tests we supply a complete in-memory zip.

// Re-declare helpers from T14 test (copy the three builder functions here):
// _buildDbf, _buildPolygonShp, _buildPolylineShp, _makeValidZip
// (omitted for brevity — copy from shapefile_importer_test.dart)

// For the notifier tests, use FakeDriveApi.downloadComplete with an empty Uint8List
// and a subclassed ShapefileImporter that skips real parsing.

class _NoopImporter extends ShapefileImporter {
  _NoopImporter(AppDatabase db)
      : super(
          db: db,
          validator: const ShapefileValidator(),
          dbfParser: const DbfParser(),
          reprojector: Reprojector(),
        );

  int callCount = 0;

  @override
  Future<ImportResult> importInputZip(
    Uint8List zipBytes,
    String assignmentId,
    String driveModifiedTime,
    String driveFolderId,
    String enumeratorId,
  ) async {
    callCount++;
    // Write a minimal assignment so _startTileDownload can read it.
    await db.into(db.assignments).insertOnConflictUpdate(
          AssignmentsCompanion.insert(
            id: assignmentId,
            enumeratorId: enumeratorId,
            campaignId: assignmentId,
            boundaryPolygonGeojson: '{"type":"Polygon","coordinates":[[]]}',
            downloadedAt: Value(DateTime.now()),
            driveModifiedTime: Value(driveModifiedTime),
            driveFolderId: Value(driveFolderId),
            createdAt: DateTime.now(),
          ),
        );
    return ImportResult(buildingCount: 1, roadCount: 1, boundaryGeojson: '{}');
  }
}

const _brgy001 = DriveAssignment(
  assignmentId: 'brgy-001',
  inputZipFileId: 'f1',
  inputZipModifiedTime: '2026-04-28T10:00:00Z',
  driveFolderId: 'folder-1',
);

GetMapsNotifier _makeNotifier({
  List<DriveAssignment>? assignments,
  Exception? listError,
  Exception? downloadError,
  int availableBytes = 100 * 1024 * 1024,
  List<DriveDownloadEvent>? downloadEvents,
  AppDatabase? db,
  _NoopImporter? importer,
}) {
  final database = db ?? AppDatabase.forTesting(NativeDatabase.memory());
  return GetMapsNotifier(
    assignmentRepo: AssignmentRepository(db: database),
    packRepo: OfflineTilePackRepository(database),
    packAdapter: FakeOfflinePackAdapter(),
    featureRepo: FeatureRepository(database),
    driveApi: FakeDriveApi(
      assignments: assignments ?? [_brgy001],
      listError: listError,
      downloadEvents: downloadEvents,
      downloadError: downloadError,
    ),
    googleAuthRepo: FakeGoogleAuthRepository(),
    shapefileImporter: importer ?? _NoopImporter(database),
    storageChecker: FakeStorageChecker(availableBytes: availableBytes),
  );
}

void main() {
  test('empty assignment list → GetMapsError with NoAssignmentsFailure', () async {
    final n = _makeNotifier(assignments: []);
    await n.start();
    expect(n.state, isA<GetMapsError>());
    expect((n.state as GetMapsError).failure, isA<NoAssignmentsFailure>());
  });

  test('Drive list error → GetMapsError', () async {
    final n = _makeNotifier(listError: Exception('network'));
    await n.start();
    expect(n.state, isA<GetMapsError>());
  });

  test('start → PickingAssignment with one assignment', () async {
    final n = _makeNotifier();
    await n.start();
    expect(n.state, isA<PickingAssignment>());
    final s = n.state as PickingAssignment;
    expect(s.assignments, hasLength(1));
    expect(s.selectedId, 'brgy-001');
  });

  test('selectAssignment updates selectedId', () async {
    const a2 = DriveAssignment(
      assignmentId: 'brgy-002',
      inputZipFileId: 'f2',
      inputZipModifiedTime: '2026-04-28T11:00:00Z',
      driveFolderId: 'folder-2',
    );
    final n = _makeNotifier(assignments: [_brgy001, a2]);
    await n.start();
    n.selectAssignment('brgy-002');
    expect((n.state as PickingAssignment).selectedId, 'brgy-002');
  });

  test('insufficient storage → InsufficientStorage state', () async {
    final n = _makeNotifier(availableBytes: 0);
    await n.start();
    await n.confirmDownload();
    expect(n.state, isA<InsufficientStorage>());
  });

  test('confirmDownload happy path → transitions through import to DownloadingTiles', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final imp = _NoopImporter(db);
    final n = _makeNotifier(db: db, importer: imp);
    await n.start();
    await n.confirmDownload();
    // After confirmDownload with FakeOfflinePackAdapter (no events), state
    // stays at DownloadingTiles(0, 0) since FakeOfflinePackAdapter emits nothing.
    expect(n.state, isA<DownloadingTiles>());
    expect(imp.callCount, 1);
  });

  test('delta skip: alreadyDownloaded=true skips importer call', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    // Pre-seed the assignment with matching modifiedTime so delta check fires.
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'brgy-001',
            enumeratorId: 'e',
            campaignId: 'brgy-001',
            boundaryPolygonGeojson: '{}',
            driveModifiedTime: const Value('2026-04-28T10:00:00Z'),
            createdAt: DateTime.now(),
          ),
        );
    final imp = _NoopImporter(db);
    final n = _makeNotifier(db: db, importer: imp);
    await n.start();
    // The assignment should be marked alreadyDownloaded=true.
    final s = n.state as PickingAssignment;
    expect(s.assignments.first.alreadyDownloaded, isTrue);
    await n.confirmDownload();
    expect(imp.callCount, 0); // importer NOT called
    expect(n.state, isA<DownloadingTiles>());
  });

  test('download stream error → GetMapsError', () async {
    final n = _makeNotifier(downloadError: Exception('timeout'));
    await n.start();
    await n.confirmDownload();
    expect(n.state, isA<GetMapsError>());
  });

  test('cancel during download → Cancelled', () async {
    final n = _makeNotifier();
    await n.start();
    // Start confirmDownload but cancel immediately via cancel().
    unawaited(n.confirmDownload());
    await n.cancel();
    expect(n.state, isA<Cancelled>());
  });

  test('reset after cancel → Idle', () async {
    final n = _makeNotifier();
    await n.start();
    await n.cancel();
    n.reset();
    expect(n.state, isA<Idle>());
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/features/assignment/get_maps_notifier_test.dart`
Expected: FAIL — `GetMapsNotifier` missing new constructor params.

- [ ] **Step 3: Rewrite assignment_providers.dart**

```dart
// lib/features/assignment/presentation/assignment_providers.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// ── base providers ──────────────────────────────────────────────────────────

final assignmentRepositoryProvider = Provider<AssignmentRepository>((ref) {
  return AssignmentRepository(db: ref.watch(appDatabaseProvider));
});

final offlineTilePackRepositoryProvider =
    Provider<OfflineTilePackRepository>((ref) {
  return OfflineTilePackRepository(ref.watch(appDatabaseProvider));
});

final offlinePackAdapterProvider = Provider<OfflinePackAdapter>((ref) {
  return FakeOfflinePackAdapter();
});

final featureRepositoryProvider = Provider<FeatureRepository>((ref) {
  return FeatureRepository(ref.watch(appDatabaseProvider));
});

/// Overridden in main.dart with GoogleDriveApi.
final driveApiProvider = Provider<DriveApi>((ref) {
  throw UnimplementedError('Override driveApiProvider in main.dart');
});

/// Overridden in main.dart with ShapefileImporter backed by real DB.
final shapefileImporterProvider = Provider<ShapefileImporter>((ref) {
  throw UnimplementedError('Override shapefileImporterProvider in main.dart');
});

/// Overridden in main.dart with DeviceStorageChecker.
final storageCheckerProvider = Provider<StorageChecker>((ref) {
  throw UnimplementedError('Override storageCheckerProvider in main.dart');
});

// ── notifier ────────────────────────────────────────────────────────────────

class GetMapsNotifier extends StateNotifier<GetMapsState> {
  GetMapsNotifier({
    required this.assignmentRepo,
    required this.packRepo,
    required this.packAdapter,
    required this.featureRepo,
    required this.driveApi,
    required this.googleAuthRepo,
    required this.shapefileImporter,
    required this.storageChecker,
  }) : super(const Idle());

  final AssignmentRepository assignmentRepo;
  final OfflineTilePackRepository packRepo;
  final OfflinePackAdapter packAdapter;
  final FeatureRepository featureRepo;
  final DriveApi driveApi;
  final GoogleAuthRepository googleAuthRepo;
  final ShapefileImporter shapefileImporter;
  final StorageChecker storageChecker;

  static const _styleUri = 'mapbox://styles/mapbox/streets-v12';
  static const _minZoom = 12;
  static const _maxZoom = 17;

  bool _cancelled = false;

  Future<void> start() async {
    _cancelled = false;
    state = const DiscoveringAssignments();

    List rawAssignments;
    try {
      rawAssignments = await driveApi.listAssignments();
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()));
      return;
    }

    if (rawAssignments.isEmpty) {
      state = const GetMapsError(NoAssignmentsFailure());
      return;
    }

    // Delta check: mark assignments whose modifiedTime matches stored value.
    final assignments = await Future.wait(
      rawAssignments.map((a) async {
        final stored = await assignmentRepo.getDriveModifiedTime(a.assignmentId);
        return stored == a.inputZipModifiedTime
            ? a.copyWith(alreadyDownloaded: true)
            : a;
      }),
    );

    if (!mounted) return;
    state = PickingAssignment(
      assignments: assignments,
      selectedId: assignments.first.assignmentId,
    );
  }

  void selectAssignment(String id) {
    final s = state;
    if (s is! PickingAssignment) return;
    state = PickingAssignment(assignments: s.assignments, selectedId: id);
  }

  Future<void> confirmDownload() async {
    final s = state;
    if (s is! PickingAssignment) return;

    final selected =
        s.assignments.firstWhere((a) => a.assignmentId == s.selectedId);

    // Storage pre-check
    final needed = await driveApi.getInputZipSize(selected.assignmentId);
    final available = await storageChecker.getAvailableBytes();
    if (available < needed) {
      if (!mounted) return;
      state = InsufficientStorage(
          requiredBytes: needed, availableBytes: available);
      return;
    }

    // Delta skip
    if (selected.alreadyDownloaded) {
      await _startTileDownload();
      return;
    }

    // Download shapefiles
    if (!mounted) return;
    state = DownloadingShapefiles(downloaded: 0, total: needed);
    List<int>? zipBytes;

    try {
      await for (final event in driveApi.downloadInputZip(selected.assignmentId)) {
        if (_cancelled || !mounted) return;
        switch (event) {
          case DriveDownloadProgress(:final downloaded, :final total):
            state = DownloadingShapefiles(downloaded: downloaded, total: total);
          case DriveDownloadComplete(:final bytes):
            zipBytes = bytes;
        }
      }
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()));
      return;
    }

    if (_cancelled || !mounted) return;
    if (zipBytes == null) {
      state = const GetMapsError(NetworkFailure('Download completed with no data'));
      return;
    }

    // Import shapefiles
    state = const ImportingShapefiles();
    try {
      final enumeratorId = await googleAuthRepo.getEnumeratorId();
      await shapefileImporter.importInputZip(
        Uint8List.fromList(zipBytes),
        selected.assignmentId,
        selected.inputZipModifiedTime,
        selected.driveFolderId,
        enumeratorId,
      );
    } on ShapefileValidationFailure catch (f) {
      if (!mounted) return;
      state = GetMapsError(f);
      return;
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(StorageFailure(e.toString()));
      return;
    }

    await _startTileDownload();
  }

  Future<void> _startTileDownload() async {
    if (!mounted) return;
    final assignment = await assignmentRepo.getCurrentAssignment();
    if (!mounted) return;
    if (assignment == null) {
      state = const GetMapsError(
          StorageFailure('Assignment not found after import'));
      return;
    }

    final packId = const Uuid().v4();
    await packRepo.upsert(
      id: packId,
      assignmentId: assignment.id,
      regionBoundsGeojson: assignment.boundaryPolygonGeojson,
    );

    if (!mounted) return;
    state = const DownloadingTiles(downloadedBytes: 0, totalBytes: 0);

    final stream = packAdapter.createPack(
      regionGeojson: assignment.boundaryPolygonGeojson,
      styleUri: _styleUri,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );

    try {
      await for (final event in stream) {
        if (!mounted) return;
        switch (event) {
          case OfflinePackProgress(:final downloaded, :final total):
            state =
                DownloadingTiles(downloadedBytes: downloaded, totalBytes: total);
            await packRepo.updateProgress(packId, downloaded, total);
          case OfflinePackComplete():
            await packRepo.markReady(packId);
            final features = await featureRepo
                .watchFeaturesForAssignment(assignment.id)
                .first;
            final currentTotal = state is DownloadingTiles
                ? (state as DownloadingTiles).totalBytes
                : 0;
            state = Ready(
                featureCount: features.length, totalBytes: currentTotal);
            return;
          case OfflinePackError(:final message):
            await packRepo.markError(packId, message);
            state = GetMapsError(StorageFailure(message));
            return;
        }
      }
    } on Object catch (e) {
      if (!mounted) return;
      state = GetMapsError(StorageFailure(e.toString()));
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    await packAdapter.cancelAllPacks();
    if (!mounted) return;
    state = const Cancelled();
  }

  void reset() {
    _cancelled = false;
    state = const Idle();
  }
}

final getMapsNotifierProvider =
    StateNotifierProvider<GetMapsNotifier, GetMapsState>((ref) {
  return GetMapsNotifier(
    assignmentRepo: ref.watch(assignmentRepositoryProvider),
    packRepo: ref.watch(offlineTilePackRepositoryProvider),
    packAdapter: ref.watch(offlinePackAdapterProvider),
    featureRepo: ref.watch(featureRepositoryProvider),
    driveApi: ref.watch(driveApiProvider),
    googleAuthRepo: ref.watch(googleAuthRepositoryProvider),
    shapefileImporter: ref.watch(shapefileImporterProvider),
    storageChecker: ref.watch(storageCheckerProvider),
  );
});

final currentAssignmentProvider = StreamProvider<Assignment?>((ref) {
  return ref.watch(assignmentRepositoryProvider).watchCurrentAssignment();
});
```

Note: Add `import 'dart:typed_data';` at the top if Dart requires it for `Uint8List.fromList`.

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/features/assignment/get_maps_notifier_test.dart`
Expected: PASS.

- [ ] **Step 5: Run full suite**

Run: `flutter test`
Expected: all tests pass (old `FetchingFeatures` references removed from screen and state).

- [ ] **Step 6: Commit**

```bash
git add lib/features/assignment/presentation/assignment_providers.dart \
        test/features/assignment/get_maps_notifier_test.dart
git commit -m "feat(get-maps): GetMapsNotifier Drive flow + delta check (US-17 T17)"
```

---

### Task 18: L10n strings

**Files:**
- Modify: `lib/core/i18n/app_en.arb`
- Modify: `lib/core/i18n/app_tl.arb`

- [ ] **Step 1: Remove fetchingFeatures and add new keys in app_en.arb**

Remove this entry from `lib/core/i18n/app_en.arb`:
```json
  "fetchingFeatures": "Fetching buildings…",
```

Add before `"downloadingTiles"`:
```json
  "discoveringAssignments": "Looking for your assignments…",
  "pickAssignmentTitle": "Select your assignment",
  "downloadSelected": "Download Selected",
  "alreadyDownloadedBadge": "Downloaded",
  "notDownloadedBadge": "Not downloaded",
  "downloadingShapefiles": "Downloading shapefiles…",
  "importingShapefiles": "Importing…",
  "insufficientStorageTitle": "Not enough storage",
  "insufficientStorageBody": "Need {needed} MB free. You have {available} MB available.",
  "@insufficientStorageBody": {
    "placeholders": {
      "needed": {"type": "int"},
      "available": {"type": "int"}
    }
  },
  "freeSpaceHint": "Free up space and come back",
  "noAssignmentsMessage": "No assignments shared with you yet — ask your supervisor to share the assignment folder with the Google account you signed in with.",
  "signInWithGoogle": "Sign in with Google",
  "signInError": "Sign-in failed. Please try again.",
```

- [ ] **Step 2: Mirror keys in app_tl.arb**

In `lib/core/i18n/app_tl.arb`, remove:
```json
  "fetchingFeatures": "Kinukuha ang mga gusali…",
```

Add the same keys with Tagalog translations:
```json
  "discoveringAssignments": "Hinahanap ang iyong mga takdang-aralin…",
  "pickAssignmentTitle": "Piliin ang iyong takdang-aralin",
  "downloadSelected": "I-download ang Napili",
  "alreadyDownloadedBadge": "Na-download na",
  "notDownloadedBadge": "Hindi pa na-download",
  "downloadingShapefiles": "Dina-download ang mga shapefile…",
  "importingShapefiles": "Ini-import…",
  "insufficientStorageTitle": "Hindi sapat ang storage",
  "insufficientStorageBody": "Kailangan ng {needed} MB. Mayroon kang {available} MB.",
  "@insufficientStorageBody": {
    "placeholders": {
      "needed": {"type": "int"},
      "available": {"type": "int"}
    }
  },
  "freeSpaceHint": "Mag-free ng espasyo at bumalik",
  "noAssignmentsMessage": "Wala pang assignment na ibinabahagi sa iyo — hilingin sa iyong superbisor na ibahagi ang folder ng assignment sa Google account na iyong ginamit sa pag-sign in.",
  "signInWithGoogle": "Mag-sign in gamit ang Google",
  "signInError": "Nabigo ang pag-sign in. Pakisubukan muli.",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: `lib/generated/l10n/app_localizations.dart` updated; no errors.

- [ ] **Step 4: Verify compile**

Run: `flutter build apk --debug 2>&1 | head -30`
Expected: compiles without `undefined` errors on l10n keys.

- [ ] **Step 5: Commit**

```bash
git add lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/
git commit -m "feat(i18n): l10n keys for Drive/shapefile flow (US-17 T18)"
```

---

### Task 19: SignInScreen

**Files:**
- Create: `lib/features/auth/presentation/sign_in_screen.dart`
- Test: `test/features/auth/sign_in_screen_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/auth/sign_in_screen_test.dart
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget w, {FakeGoogleAuthRepository? repo}) {
  final r = repo ?? FakeGoogleAuthRepository(startSignedIn: false);
  return ProviderScope(
    overrides: [
      googleAuthRepositoryProvider.overrideWithValue(r),
    ],
    child: MaterialApp(home: w),
  );
}

void main() {
  testWidgets('renders Sign in with Google button', (tester) async {
    await tester.pumpWidget(_wrap(const SignInScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('tapping button calls signIn', (tester) async {
    final repo = FakeGoogleAuthRepository(startSignedIn: false);
    await tester.pumpWidget(_wrap(const SignInScreen(), repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(await repo.isSignedIn(), isTrue);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/features/auth/sign_in_screen_test.dart`
Expected: FAIL — `SignInScreen` not found.

- [ ] **Step 3: Implement**

```dart
// lib/features/auth/presentation/sign_in_screen.dart
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(googleAuthNotifierProvider.notifier).signIn();
      if (mounted) context.go('/get-maps');
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context)!.signInError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      // No back button — this is a one-time onboarding gate.
      appBar: AppBar(automaticallyImplyLeading: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: _loading ? null : _signIn,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.signInWithGoogle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/features/auth/sign_in_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/presentation/sign_in_screen.dart \
        test/features/auth/sign_in_screen_test.dart
git commit -m "feat(auth): SignInScreen Google OAuth onboarding (US-17 T19)"
```

---

### Task 20: Router update

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Test: `test/core/router/app_router_google_auth_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/router/app_router_google_auth_test.dart
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app(FakeGoogleAuthRepository repo) {
  return ProviderScope(
    overrides: [
      googleAuthRepositoryProvider.overrideWithValue(repo),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        final router = ref.watch(appRouterProvider);
        return MaterialApp.router(routerConfig: router);
      },
    ),
  );
}

void main() {
  testWidgets('navigating /get-maps while signed-out redirects to /sign-in',
      (tester) async {
    final repo = FakeGoogleAuthRepository(startSignedIn: false);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final router = tester.element(find.byType(MaterialApp)).read(appRouterProvider);
    router.go('/get-maps');
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('/sign-in while signed-in redirects to /get-maps', (tester) async {
    final repo = FakeGoogleAuthRepository(startSignedIn: true);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final router = tester.element(find.byType(MaterialApp)).read(appRouterProvider);
    router.go('/sign-in');
    await tester.pumpAndSettle();

    expect(find.byType(GetMapsScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/core/router/app_router_google_auth_test.dart`
Expected: FAIL — `/sign-in` route missing, no Google auth redirect.

- [ ] **Step 3: Update app_router.dart**

```dart
// lib/core/router/app_router.dart  (full replacement)
import 'package:firecheck/features/assignment/presentation/assignment_closed_blocker.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:firecheck/features/auth/presentation/login_screen.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/olp_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final supabaseNotifier = ref.watch(authStateProvider.notifier);
  final googleNotifier = ref.watch(googleAuthNotifierProvider.notifier);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: Listenable.merge([
      _AuthListenable(supabaseNotifier),
      _GoogleAuthListenable(googleNotifier),
    ]),
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final lock = ref.read(assignmentLockStateProvider).value;
      final googleAuth = ref.read(googleAuthNotifierProvider);
      final loc = state.matchedLocation;

      // Supabase auth gate
      final authRedirect = switch (auth) {
        AuthChecking() => null,
        Unauthenticated() => loc == '/login' ? null : '/login',
        Authenticated() => loc == '/login' ? '/' : null,
      };
      if (authRedirect != null) return authRedirect;

      // ClosedRemotely lock
      if (lock is ClosedRemotely && loc != '/login' && loc != '/blocker') {
        return '/blocker';
      }

      // Google auth gate
      if (loc == '/get-maps' && googleAuth == GoogleAuthState.signedOut) {
        return '/sign-in';
      }
      if (loc == '/sign-in' && googleAuth == GoogleAuthState.signedIn) {
        return '/get-maps';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/',
        builder: (context, state) {
          final auth = ref.watch(authStateProvider);
          if (auth is AuthChecking) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return const HomeScreen();
        },
      ),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/get-maps', builder: (_, __) => const GetMapsScreen()),
      GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
      GoRoute(
        path: '/feature/:featureId',
        builder: (context, state) => SubmissionDetailScreen(
          featureId: state.pathParameters['featureId']!,
        ),
      ),
      GoRoute(
        path: '/feature/:featureId/olp/result',
        builder: (context, state) => OlpResultScreen(
          submissionId: state.uri.queryParameters['submissionId'] ?? '',
          featureId: state.pathParameters['featureId']!,
        ),
      ),
      GoRoute(path: '/review', builder: (_, __) => const ReviewScreen()),
      GoRoute(
          path: '/blocker', builder: (_, __) => const AssignmentClosedBlocker()),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(StateNotifier<AuthState> notifier) {
    _dispose = notifier.addListener((_) => notifyListeners());
  }
  late final VoidCallback _dispose;
  @override
  void dispose() {
    _dispose();
    super.dispose();
  }
}

class _GoogleAuthListenable extends ChangeNotifier {
  _GoogleAuthListenable(StateNotifier<GoogleAuthState> notifier) {
    _dispose = notifier.addListener((_) => notifyListeners());
  }
  late final VoidCallback _dispose;
  @override
  void dispose() {
    _dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/core/router/app_router_google_auth_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/router/app_router.dart \
        test/core/router/app_router_google_auth_test.dart
git commit -m "feat(router): /sign-in route + Google auth guard on /get-maps (US-17 T20)"
```

---

### Task 21: GetMapsScreen expansion

**Files:**
- Modify: `lib/features/assignment/presentation/get_maps_screen.dart`
- Test: `test/features/assignment/get_maps_screen_us17_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/assignment/get_maps_screen_us17_test.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(GetMapsState initialState) {
  return ProviderScope(
    overrides: [
      getMapsNotifierProvider.overrideWith((_) => _FakeNotifier(initialState)),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: GetMapsScreen(),
    ),
  );
}

class _FakeNotifier extends StateNotifier<GetMapsState> {
  _FakeNotifier(super.state);
  String? lastSelectId;
  bool confirmCalled = false;
  @override
  void selectAssignment(String id) => lastSelectId = id;
  @override
  Future<void> confirmDownload() async => confirmCalled = true;
}

const _brgy = DriveAssignment(
  assignmentId: 'brgy-001',
  inputZipFileId: 'f1',
  inputZipModifiedTime: '2026-04-28T10:00:00Z',
  driveFolderId: 'fd',
);

void main() {
  testWidgets('DiscoveringAssignments → spinner shown', (tester) async {
    await tester.pumpWidget(_wrap(const DiscoveringAssignments()));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PickingAssignment → assignment name shown', (tester) async {
    final state = PickingAssignment(assignments: [_brgy], selectedId: 'brgy-001');
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    expect(find.text('brgy-001'), findsOneWidget);
  });

  testWidgets('PickingAssignment → Download Selected button enabled', (tester) async {
    final state = PickingAssignment(assignments: [_brgy], selectedId: 'brgy-001');
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('InsufficientStorage → Download Selected button disabled', (tester) async {
    final state = InsufficientStorage(requiredBytes: 100, availableBytes: 10);
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('DownloadingShapefiles → progress bar and cancel shown', (tester) async {
    final state = DownloadingShapefiles(downloaded: 500, total: 1000);
    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('ImportingShapefiles → indeterminate progress shown', (tester) async {
    await tester.pumpWidget(_wrap(const ImportingShapefiles()));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/features/assignment/get_maps_screen_us17_test.dart`
Expected: FAIL — new states not handled in screen switch.

- [ ] **Step 3: Rewrite get_maps_screen.dart**

```dart
// lib/features/assignment/presentation/get_maps_screen.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GetMapsScreen extends ConsumerWidget {
  const GetMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(getMapsNotifierProvider);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l.getMapsTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (state) {
          Idle() => _IdleView(
              onStart: () => ref.read(getMapsNotifierProvider.notifier).start(),
            ),
          DiscoveringAssignments() => const _DiscoveringView(),
          PickingAssignment() => _PickingAssignmentView(state: state),
          InsufficientStorage() => _InsufficientStorageView(state: state),
          DownloadingShapefiles() => _DownloadingShapefilesView(state: state),
          ImportingShapefiles() => const _ImportingShapefilesView(),
          DownloadingTiles() => _ProgressView(state: state),
          Ready() => _ReadyView(state: state),
          Cancelled() => _IdleView(
              onStart: () => ref.read(getMapsNotifierProvider.notifier).start(),
            ),
          GetMapsError(:final failure) => _ErrorView(
              failure: failure,
              onRetry: () {
                ref.read(getMapsNotifierProvider.notifier).reset();
                ref.read(getMapsNotifierProvider.notifier).start();
              },
            ),
        },
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(l.getMapsExplainer('~100 MB', 10),
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: onStart, child: Text(l.startDownload)),
      ],
    );
  }
}

class _DiscoveringView extends StatelessWidget {
  const _DiscoveringView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(l.discoveringAssignments, textAlign: TextAlign.center),
      ],
    );
  }
}

class _PickingAssignmentView extends ConsumerWidget {
  const _PickingAssignmentView({required this.state});
  final PickingAssignment state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.pickAssignmentTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: state.assignments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = state.assignments[i];
              final selected = a.assignmentId == state.selectedId;
              return InkWell(
                onTap: () => ref
                    .read(getMapsNotifierProvider.notifier)
                    .selectAssignment(a.assignmentId),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.assignmentId,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              a.alreadyDownloaded
                                  ? l.alreadyDownloadedBadge
                                  : l.notDownloadedBadge,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () =>
              ref.read(getMapsNotifierProvider.notifier).confirmDownload(),
          child: Text(l.downloadSelected),
        ),
      ],
    );
  }
}

class _InsufficientStorageView extends StatelessWidget {
  const _InsufficientStorageView({required this.state});
  final InsufficientStorage state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final needed = (state.requiredBytes / 1048576).ceil();
    final available = (state.availableBytes / 1048576).floor();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.warning_amber_rounded,
            size: 48, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 12),
        Text(l.insufficientStorageTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l.insufficientStorageBody(needed, available),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: null,
          child: Text(l.downloadSelected),
        ),
        const SizedBox(height: 8),
        Text(l.freeSpaceHint,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DownloadingShapefilesView extends ConsumerWidget {
  const _DownloadingShapefilesView({required this.state});
  final DownloadingShapefiles state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final progress = state.overallProgress;
    final dl = (state.downloaded / 1048576).toStringAsFixed(1);
    final tot = (state.total / 1048576).toStringAsFixed(1);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.downloadingShapefiles, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text('$dl / $tot MB',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () =>
              ref.read(getMapsNotifierProvider.notifier).cancel(),
          child: Text(l.cancelLabel),
        ),
      ],
    );
  }
}

class _ImportingShapefilesView extends StatelessWidget {
  const _ImportingShapefilesView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LinearProgressIndicator(value: null),
        const SizedBox(height: 16),
        Text(l.importingShapefiles, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ProgressView extends ConsumerWidget {
  const _ProgressView({required this.state});
  final GetMapsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final progress = state.overallProgress;
    final (downloaded, total) = switch (state) {
      DownloadingTiles(:final downloadedBytes, :final totalBytes) =>
        (downloadedBytes, totalBytes),
      _ => (0, 0),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.downloadingTiles, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(
          '${(downloaded / 1048576).toStringAsFixed(1)} / '
          '${(total / 1048576).toStringAsFixed(1)} MB',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () =>
              ref.read(getMapsNotifierProvider.notifier).cancel(),
          child: Text(l.cancelLabel),
        ),
      ],
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.state});
  final Ready state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(l.readyLabel, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/map'),
          child: Text(l.openMap),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.go('/'),
          child: Text(l.backToHome),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, required this.onRetry});
  final Failure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(failure.message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: onRetry, child: Text(l.tryAgain)),
      ],
    );
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `flutter test test/features/assignment/get_maps_screen_us17_test.dart`
Expected: PASS.

- [ ] **Step 5: Run full suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/assignment/presentation/get_maps_screen.dart \
        test/features/assignment/get_maps_screen_us17_test.dart
git commit -m "feat(get-maps): GetMapsScreen new views — picking, storage, download, import (US-17 T21)"
```

---

### Task 22: Wire providers in main.dart + smoke test

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add real provider overrides in main.dart**

In `lib/main.dart`, import the new components and add provider overrides in `ProviderScope`. Locate the existing `overrides:` list (used for `offlinePackAdapterProvider`).

Add these imports at the top:
```dart
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/google_drive_api.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/auth/data/google_sign_in_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
```

In the `ProviderScope` overrides, add:
```dart
  overrides: [
    // ... existing offlinePackAdapterProvider override ...
    googleAuthRepositoryProvider.overrideWithProvider(
      Provider((ref) => GoogleSignInAuthRepository(
        googleSignIn: GoogleSignIn(
          scopes: ['https://www.googleapis.com/auth/drive.readonly'],
        ),
        secureStorage: const FlutterSecureStorage(),
      )),
    ),
    driveApiProvider.overrideWithProvider(
      Provider((ref) => GoogleDriveApi(
        googleSignIn: GoogleSignIn(
          scopes: ['https://www.googleapis.com/auth/drive.readonly'],
        ),
      )),
    ),
    shapefileImporterProvider.overrideWithProvider(
      Provider((ref) => ShapefileImporter(
        db: ref.watch(appDatabaseProvider),
        validator: const ShapefileValidator(),
        dbfParser: const DbfParser(),
        reprojector: Reprojector(),
      )),
    ),
    storageCheckerProvider.overrideWithValue(const DeviceStorageChecker()),
  ],
```

Note: `GoogleSignIn` instances should ideally be singletons. If the codebase already has a pattern for sharing them (e.g., a `googleSignInProvider`), follow that pattern instead of constructing two separate instances.

- [ ] **Step 2: Build to confirm compilation**

Run: `flutter build apk --debug 2>&1 | tail -20`
Expected: BUILD SUCCESSFUL with no undefined-method errors.

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat(main): wire GoogleDriveApi, ShapefileImporter, StorageChecker providers (US-17 T22)"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Google OAuth in scope (google_sign_in + FlutterSecureStorage) | T1, T6, T7, T19 |
| Drive replaces Supabase for assignment input | T9 (remove fetchAndUpsertCurrent), T17 (notifier rewrite) |
| /sign-in screen router-gated on /get-maps | T19, T20 |
| Always show assignment picker | T16 (PickingAssignment state), T21 (screen) |
| Hard blocker on insufficient storage | T16 (InsufficientStorage state), T17 (confirmDownload), T21 |
| DriveApi abstract + FakeDriveApi + GoogleDriveApi | T4, T15 |
| ShapefileImporter: unzip → validate → reproject → Drift | T10–T14 |
| New states: DiscoveringAssignments, PickingAssignment, DownloadingShapefiles, ImportingShapefiles, InsufficientStorage | T16 |
| FetchingFeatures removed | T16, T17, T18, T21 |
| Drift migration v7: drive_modified_time + drive_folder_id | T8 |
| Delta check: modifiedTime cross-reference | T9 (getDriveModifiedTime), T17 (start()) |
| Progress model per spec | T16 (overallProgress formulas) |
| Error handling: NoAssignmentsFailure, ShapefileValidationFailure | T2, T17 |
| All existing tile-pack logic preserved | T17 (_startTileDownload) |

**Placeholder scan:** No TBDs, no "implement later" entries found.

**Type consistency check:**
- `DriveAssignment.assignmentId` — used consistently in T3, T4, T17
- `ShapefileImporter.importInputZip(zipBytes, assignmentId, driveModifiedTime, driveFolderId, enumeratorId)` — defined in T14, called in T17
- `GetMapsNotifier.selectAssignment(String id)` / `confirmDownload()` — defined in T17, called in T21
- `GoogleAuthState.loading/signedIn/signedOut` — defined in T7, used in T20
- `AssignmentsCompanion.driveModifiedTime` / `driveFolderId` — available after T8 codegen, used in T14

---

**Plan complete.** Saved to `docs/superpowers/plans/2026-04-30-get-maps-shapefile-fetch.md`.

Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration via `superpowers:subagent-driven-development`

**2. Inline Execution** — execute tasks in this session using `superpowers:executing-plans`

Which approach?
