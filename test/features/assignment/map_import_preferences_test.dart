import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/assignment/data/map_import_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to unrestricted and persists an explicit choice', () async {
    final storage = InMemorySecureStorage();
    final preferences = MapImportPreferences(storage);

    expect(await preferences.isUnrestricted(), isTrue);

    await preferences.setUnrestricted(value: false);
    expect(
      await MapImportPreferences(storage).isUnrestricted(),
      isFalse,
    );

    await preferences.setUnrestricted(value: true);
    expect(await preferences.isUnrestricted(), isTrue);
  });
}
