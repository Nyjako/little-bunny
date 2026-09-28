import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A minimal key-value secret store, abstracted so tests can inject an
/// in-memory fake instead of going through platform channels -- there's no
/// real secure-storage backend under `flutter test`.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Real implementation backed by the OS-native secure storage mechanism
/// (Android Keystore, Linux libsecret via a running secret-service daemon --
/// see docs/architecture.md).
class FlutterSecureStorageSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;

  const FlutterSecureStorageSecretStore([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
