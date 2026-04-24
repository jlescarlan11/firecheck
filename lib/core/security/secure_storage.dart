import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureStorage {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<void> clear();
}

class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter([FlutterSecureStorage? inner])
      : _inner = inner ?? const FlutterSecureStorage();

  final FlutterSecureStorage _inner;

  static const _options = AndroidOptions(encryptedSharedPreferences: true);

  @override
  Future<void> write(String key, String value) =>
      _inner.write(key: key, value: value, aOptions: _options);

  @override
  Future<String?> read(String key) =>
      _inner.read(key: key, aOptions: _options);

  @override
  Future<void> delete(String key) =>
      _inner.delete(key: key, aOptions: _options);

  @override
  Future<void> clear() => _inner.deleteAll(aOptions: _options);
}

class InMemorySecureStorage implements SecureStorage {
  final _store = <String, String>{};

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<void> clear() async => _store.clear();
}
