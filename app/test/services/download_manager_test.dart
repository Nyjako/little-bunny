import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/services/download_manager.dart';

import '../fakes/fake_bunny_repository.dart';

BunnyPost _post({String? artist, String? fileUrl = 'https://static1.e621.net/data/1.png', String? fileExt = 'png', String? fileMd5}) => BunnyPost(
  id: 1,
  site: BunnySite.e621,
  externalId: 42,
  artist: artist,
  score: 0,
  favCount: 0,
  commentCount: 0,
  fileUrl: fileUrl,
  fileExt: fileExt,
  fileMd5: fileMd5,
  width: 100,
  height: 100,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('download_manager_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('returns noFileUrl without touching the network or filesystem when fileUrl is null', () async {
    final manager = DownloadManager(client: MockClient((_) async => fail('should not be called')));
    final repository = FakeBunnyRepository();

    final result = await manager.downloadPost(_post(fileUrl: null), repository, tempDir.path);

    expect(result.outcome, DownloadOutcome.noFileUrl);
    expect(repository.recordDownloadCalls, isEmpty);
  });

  test('downloads and verifies a matching checksum, sanitizing the artist folder', () async {
    final bytes = [1, 2, 3, 4];
    final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes(bytes, 200)));
    final repository = FakeBunnyRepository();
    final expectedMd5 = md5.convert(bytes).toString();

    final result = await manager.downloadPost(_post(artist: 'some/bad:artist', fileMd5: expectedMd5), repository, tempDir.path);

    expect(result.outcome, DownloadOutcome.verified);
    expect(result.filePath, '${tempDir.path}/some_bad_artist/42.png');
    expect(await File(result.filePath!).readAsBytes(), bytes);
    expect(repository.recordDownloadCalls, hasLength(1));
    expect(repository.recordDownloadCalls.single.$4, isTrue); // verified
  });

  test('falls back to "unknown" for a null artist', () async {
    final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1], 200)));
    final repository = FakeBunnyRepository();

    final result = await manager.downloadPost(_post(artist: null), repository, tempDir.path);

    expect(result.filePath, '${tempDir.path}/unknown/42.png');
  });

  test('reports checksumMismatch when fileMd5 does not match the downloaded bytes', () async {
    final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    final repository = FakeBunnyRepository();

    final result = await manager.downloadPost(_post(fileMd5: 'not-the-real-checksum'), repository, tempDir.path);

    expect(result.outcome, DownloadOutcome.checksumMismatch);
    expect(repository.recordDownloadCalls.single.$4, isFalse); // verified
  });

  test('treats a post with no published checksum as verified', () async {
    final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    final repository = FakeBunnyRepository();

    final result = await manager.downloadPost(_post(fileMd5: null), repository, tempDir.path);

    expect(result.outcome, DownloadOutcome.verified);
  });

  test('reports failed on a non-200 response', () async {
    final manager = DownloadManager(client: MockClient((_) async => http.Response('', 404)));
    final repository = FakeBunnyRepository();

    final result = await manager.downloadPost(_post(), repository, tempDir.path);

    expect(result.outcome, DownloadOutcome.failed);
    expect(repository.recordDownloadCalls, isEmpty);
  });

  test('creates the destination directory recursively when it does not already exist', () async {
    final nestedDir = Directory('${tempDir.path}/does/not/exist/yet');
    final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1], 200)));
    final repository = FakeBunnyRepository();

    await manager.downloadPost(_post(artist: 'wolf'), repository, nestedDir.path);

    expect(await File('${nestedDir.path}/wolf/42.png').exists(), isTrue);
  });
}
