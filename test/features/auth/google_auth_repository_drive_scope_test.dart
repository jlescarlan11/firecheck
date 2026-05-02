// test/features/auth/google_auth_repository_drive_scope_test.dart
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:firecheck/features/auth/data/google_sign_in_auth_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:google_sign_in/google_sign_in.dart';

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test('requestDriveUploadScope calls requestScopes with drive.file scope',
      () async {
    final mockSignIn = _MockGoogleSignIn();
    final mockStorage = _MockFlutterSecureStorage();
    when(() => mockSignIn.requestScopes(any())).thenAnswer((_) async => true);

    final repo = GoogleSignInAuthRepository(
      googleSignIn: mockSignIn,
      secureStorage: mockStorage,
    );
    final result = await repo.requestDriveUploadScope();

    expect(result, isTrue);
    verify(() => mockSignIn.requestScopes(
          [GoogleAuthRepository.driveFileScope],
        )).called(1);
  });
}
