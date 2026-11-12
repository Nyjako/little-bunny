import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/native_dependency_licenses.dart';

void main() {
  tearDown(LicenseRegistry.reset);

  test('registers a license entry naming every native dependency bunny_core_ffi vendors', () async {
    registerNativeDependencyLicenses();

    final packages = await LicenseRegistry.licenses.expand((entry) => entry.packages).toSet();

    expect(
      packages,
      containsAll(<String>['curl', 'cJSON', 'SQLite', 'GOBLIN', 'mbedTLS (Android builds)', 'OpenSSL (desktop builds)', 'zlib']),
    );
  });

  test('every registered entry has non-empty license text', () async {
    registerNativeDependencyLicenses();

    final entries = await LicenseRegistry.licenses.toList();

    expect(entries, isNotEmpty);
    for (final entry in entries) {
      expect(entry.paragraphs.map((p) => p.text).join(), isNotEmpty);
    }
  });
}
