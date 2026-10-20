import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:saf_stream/saf_stream_platform_interface.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_saf_platform.dart';

BunnyPost _post({BunnySite site = BunnySite.e621, String? artist, String? fileUrl = 'https://static1.e621.net/data/1.png', String? fileExt = 'png', String? fileMd5}) => BunnyPost(
  id: 1,
  site: site,
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

  group('SAF write path (Android content:// destination, M36)', () {
    late FakeSafUtilPlatform fakeSafUtil;
    late FakeSafStreamPlatform fakeSafStream;

    setUp(() {
      fakeSafUtil = FakeSafUtilPlatform();
      fakeSafStream = FakeSafStreamPlatform();
      SafUtilPlatform.instance = fakeSafUtil;
      SafStreamPlatform.instance = fakeSafStream;
    });

    test('a content:// destination creates the artist subfolder and writes via SafStream instead of dart:io', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final repository = FakeBunnyRepository();

      final result = await manager.downloadPost(_post(artist: 'some/bad:artist'), repository, 'content://com.android.externalstorage.documents/tree/primary%3ADownload');

      expect(result.outcome, DownloadOutcome.verified);
      expect(fakeSafUtil.mkdirpCalls, [('content://com.android.externalstorage.documents/tree/primary%3ADownload', 'some_bad_artist')]);
      expect(fakeSafStream.writeFileBytesCalls, [('content://com.android.externalstorage.documents/tree/primary%3ADownload/some_bad_artist', '42.png', 'image/png')]);
      expect(result.filePath, 'content://com.android.externalstorage.documents/tree/primary%3ADownload/some_bad_artist/42.png');
    });
  });

  group('autoFavorite (M10.1)', () {
    test('queues a favorite when a download verifies and autoFavorite is true', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(fileMd5: null), repository, tempDir.path, autoFavorite: true);

      expect(repository.favoriteAddCalls, [1]);
      expect(repository.processQueueCallCount, 0); // downloadPost only queues -- draining is the caller's job
    });

    test('queues a favorite even on a checksum mismatch, since the file was still written', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final repository = FakeBunnyRepository();

      final result = await manager.downloadPost(_post(fileMd5: 'not-the-real-checksum'), repository, tempDir.path, autoFavorite: true);

      expect(result.outcome, DownloadOutcome.checksumMismatch);
      expect(repository.favoriteAddCalls, [1]);
    });

    test('does not queue a favorite when autoFavorite is false (the default)', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(fileMd5: null), repository, tempDir.path);

      expect(repository.favoriteAddCalls, isEmpty);
    });

    test('does not queue a favorite when there is no file to download', () async {
      final manager = DownloadManager(client: MockClient((_) async => fail('should not be called')));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(fileUrl: null), repository, tempDir.path, autoFavorite: true);

      expect(repository.favoriteAddCalls, isEmpty);
    });

    test('does not queue a favorite when the download fails', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response('', 404)));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(), repository, tempDir.path, autoFavorite: true);

      expect(repository.favoriteAddCalls, isEmpty);
    });
  });

  group('autoUpvote (M14.2)', () {
    test('queues an upvote when a download verifies and autoUpvote is true', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(fileMd5: null), repository, tempDir.path, autoUpvote: true);

      expect(repository.voteCalls, [(1, 1)]);
      expect(repository.processQueueCallCount, 0); // downloadPost only queues -- draining is the caller's job
    });

    test('queues an upvote even on a checksum mismatch, since the file was still written', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final repository = FakeBunnyRepository();

      final result = await manager.downloadPost(_post(fileMd5: 'not-the-real-checksum'), repository, tempDir.path, autoUpvote: true);

      expect(result.outcome, DownloadOutcome.checksumMismatch);
      expect(repository.voteCalls, [(1, 1)]);
    });

    test('does not queue an upvote when autoUpvote is false (the default)', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(fileMd5: null), repository, tempDir.path);

      expect(repository.voteCalls, isEmpty);
    });

    test('does not queue an upvote for an Inkbunny post, which has no vote API', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(site: BunnySite.inkbunny, fileMd5: null), repository, tempDir.path, autoUpvote: true);

      expect(repository.voteCalls, isEmpty);
    });

    test('does not queue an upvote when there is no file to download', () async {
      final manager = DownloadManager(client: MockClient((_) async => fail('should not be called')));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(fileUrl: null), repository, tempDir.path, autoUpvote: true);

      expect(repository.voteCalls, isEmpty);
    });

    test('does not queue an upvote when the download fails', () async {
      final manager = DownloadManager(client: MockClient((_) async => http.Response('', 404)));
      final repository = FakeBunnyRepository();

      await manager.downloadPost(_post(), repository, tempDir.path, autoUpvote: true);

      expect(repository.voteCalls, isEmpty);
    });
  });
}
