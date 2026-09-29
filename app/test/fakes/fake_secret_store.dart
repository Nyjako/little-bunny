import 'package:little_bunny/settings/secret_store.dart';

/// In-memory fake for tests -- there's no real secure-storage backend under
/// `flutter test`.
class FakeSecretStore implements SecretStore {
  final Map<String, String> values;

  FakeSecretStore([Map<String, String>? initial]) : values = initial ?? {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
