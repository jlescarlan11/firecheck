import 'package:firecheck/core/security/secure_storage.dart';

/// Persists the operator's validation choice across later map imports.
/// Unrestricted is the product default; only an explicit stored false opts
/// into the legacy strict bundle-layout gate.
class MapImportPreferences {
  MapImportPreferences(this._storage);

  final SecureStorage _storage;
  static const _key = 'map_import_unrestricted';

  Future<bool> isUnrestricted() async {
    final value = await _storage.read(_key);
    return value != 'false';
  }

  Future<void> setUnrestricted({required bool value}) {
    return _storage.write(_key, value ? 'true' : 'false');
  }
}
