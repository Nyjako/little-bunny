import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/services/update_apply_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../fakes/fake_path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = FakePathProviderPlatform();

  // Only the checksum-verification *failure* paths are exercised here --
  // a successful downloadAndApply() falls through to a real platform apply
  // method (UpdateApplyService._applyLinux on this test runner), which
  // calls exit(0) and would kill the test process outright. Verification
  // failures throw before ever reaching that code, so they're safe to test.

  const archiveUrl = 'https://example.invalid/little-bunny-app-linux-x64.tar.gz';
  const sumsUrl = 'https://example.invalid/SHA256SUMS.txt';
  final archiveBytes = utf8.encode('not a real archive, just some bytes to hash');
  final realHex = sha256.convert(archiveBytes).toString();

  http.Client mockClient(String sumsBody) => MockClient((request) async {
    if (request.url.toString() == sumsUrl) {
      return http.Response(sumsBody, 200);
    }
    return http.Response.bytes(archiveBytes, 200);
  });

  test('throws when SHA256SUMS.txt has no entry for the downloaded file', () async {
    final service = UpdateApplyService(client: mockClient('$realHex  some-other-file.tar.gz\n'));

    expect(() => service.downloadAndApply(archiveUrl, sha256SumsUrl: sumsUrl), throwsA(isA<Exception>()));
  });

  test('throws when the computed checksum does not match', () async {
    final wrongHex = '0' * 64;
    final service = UpdateApplyService(client: mockClient('$wrongHex  little-bunny-app-linux-x64.tar.gz\n'));

    expect(() => service.downloadAndApply(archiveUrl, sha256SumsUrl: sumsUrl), throwsA(isA<Exception>()));
  });

  test('throws when SHA256SUMS.txt itself fails to download', () async {
    final service = UpdateApplyService(
      client: MockClient((request) async {
        if (request.url.toString() == sumsUrl) {
          return http.Response('', 404);
        }
        return http.Response.bytes(archiveBytes, 200);
      }),
    );

    expect(() => service.downloadAndApply(archiveUrl, sha256SumsUrl: sumsUrl), throwsA(isA<Exception>()));
  });

  test('matches a binary-mode ("*filename") SHA256SUMS.txt entry', () async {
    // Verifying this parses correctly is safe up to the point of actually
    // matching -- the exception from the *next* step (the download URL's
    // filename isn't a real archive) still proves the sums line itself was
    // parsed and matched, without needing to reach the dangerous apply path.
    final service = UpdateApplyService(client: mockClient('$realHex *little-bunny-app-linux-x64.tar.gz\n'));

    // Should get past checksum verification (no mismatch/missing-entry
    // exception) and only fail later trying to extract non-archive bytes.
    await expectLater(
      service.downloadAndApply(archiveUrl, sha256SumsUrl: sumsUrl),
      throwsA(isNot(predicate((e) => e.toString().contains('checksum') || e.toString().contains('no entry')))),
    );
  });
}
