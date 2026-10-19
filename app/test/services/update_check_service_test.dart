import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/services/update_check_service.dart';

void main() {
  final assetSuffix = UpdateCheckService.assetSuffixForPlatform();

  // Everything here runs on whatever host OS `flutter test` happens to be
  // on -- Linux in this project's CI/dev environment -- so
  // assetSuffixForPlatform() is never null in practice, but skip cleanly
  // rather than fail outright if that ever changes (e.g. a web test runner).
  if (assetSuffix == null) {
    test('skipped: no supported asset suffix on this test platform', () {});
    return;
  }

  String releaseJson({required String tag, List<Map<String, String>> assets = const [], String? body}) => jsonEncode({
    'tag_name': tag,
    'body': body,
    'assets': assets.map((a) => {'name': a['name'], 'browser_download_url': a['url']}).toList(),
  });

  test('reports an update when the latest build number is higher, with the matching asset URL', () async {
    final service = UpdateCheckService(
      currentBuildNumber: 10,
      client: MockClient(
        (_) async => http.Response(
          releaseJson(
            tag: 'build-999999',
            assets: [
              {'name': 'little-bunny-$assetSuffix', 'url': 'https://example.invalid/asset'},
              {'name': 'SHA256SUMS.txt', 'url': 'https://example.invalid/SHA256SUMS.txt'},
            ],
            body: 'Notes here',
          ),
          200,
        ),
      ),
    );

    final result = await service.check();

    expect(result.updateAvailable, isTrue);
    expect(result.latestBuildNumber, 999999);
    expect(result.tagName, 'build-999999');
    expect(result.downloadUrl, 'https://example.invalid/asset');
    expect(result.sha256SumsUrl, 'https://example.invalid/SHA256SUMS.txt');
    expect(result.releaseNotes, 'Notes here');
  });

  test('leaves sha256SumsUrl null when the release has no SHA256SUMS.txt asset', () async {
    final service = UpdateCheckService(
      currentBuildNumber: 10,
      client: MockClient((_) async => http.Response(releaseJson(tag: 'build-999999', assets: [{'name': 'little-bunny-$assetSuffix', 'url': 'https://example.invalid/asset'}]), 200)),
    );

    final result = await service.check();

    expect(result.sha256SumsUrl, isNull);
  });

  test('reports no update when the latest build is not newer than this one', () async {
    final service = UpdateCheckService(currentBuildNumber: 10, client: MockClient((_) async => http.Response(releaseJson(tag: 'build-10'), 200)));

    final result = await service.check();

    expect(result.updateAvailable, isFalse);
  });

  test('reports no update for a local/dev build (currentBuildNumber 0) no matter how high the latest release is', () async {
    // appBuildNumber defaults to 0 in a test run (no --dart-define) -- a
    // local/dev build is never treated as "outdated" relative to any real
    // release, see app_version.dart.
    final service = UpdateCheckService(client: MockClient((_) async => http.Response(releaseJson(tag: 'build-999999'), 200)));

    final result = await service.check();

    expect(result.updateAvailable, isFalse);
  });

  test('reports no update when the release has no matching asset', () async {
    final service = UpdateCheckService(
      client: MockClient((_) async => http.Response(releaseJson(tag: 'build-5', assets: [{'name': 'something-unrelated.zip', 'url': 'https://example.invalid/asset'}]), 200)),
    );

    final result = await service.check();

    expect(result.updateAvailable, isFalse);
    expect(result.downloadUrl, isNull);
  });

  test('reports no update on a non-200 response', () async {
    final service = UpdateCheckService(client: MockClient((_) async => http.Response('', 404)));
    final result = await service.check();
    expect(result.updateAvailable, isFalse);
  });

  test('reports no update on malformed JSON', () async {
    final service = UpdateCheckService(client: MockClient((_) async => http.Response('not json', 200)));
    final result = await service.check();
    expect(result.updateAvailable, isFalse);
  });

  test('reports no update for a tag not matching this project\'s own scheme', () async {
    final service = UpdateCheckService(client: MockClient((_) async => http.Response(releaseJson(tag: 'v1.2.3'), 200)));
    final result = await service.check();
    expect(result.updateAvailable, isFalse);
  });

  test('reports no update on a network error', () async {
    final service = UpdateCheckService(client: MockClient((_) async => throw Exception('network down')));
    final result = await service.check();
    expect(result.updateAvailable, isFalse);
  });

  test('sends a User-Agent header (GitHub\'s API rejects requests without one)', () async {
    http.Request? captured;
    final service = UpdateCheckService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(releaseJson(tag: 'build-0'), 200);
      }),
    );

    await service.check();

    expect(captured, isNotNull);
    expect(captured!.headers['User-Agent'], isNotNull);
    expect(captured!.url.toString(), 'https://api.github.com/repos/Nyjako/little-bunny/releases/latest');
  });
}
