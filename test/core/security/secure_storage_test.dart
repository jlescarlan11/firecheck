import 'package:firecheck/core/security/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemorySecureStorage', () {
    late InMemorySecureStorage storage;

    setUp(() {
      storage = InMemorySecureStorage();
    });

    test('write then read returns value', () async {
      await storage.write('refresh_token', 'abc.def');
      expect(await storage.read('refresh_token'), 'abc.def');
    });

    test('read of missing key returns null', () async {
      expect(await storage.read('nope'), isNull);
    });

    test('delete removes the key', () async {
      await storage.write('refresh_token', 'abc.def');
      await storage.delete('refresh_token');
      expect(await storage.read('refresh_token'), isNull);
    });

    test('clear wipes all keys', () async {
      await storage.write('a', '1');
      await storage.write('b', '2');
      await storage.clear();
      expect(await storage.read('a'), isNull);
      expect(await storage.read('b'), isNull);
    });
  });
}
