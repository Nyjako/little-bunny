import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/services/preview_cache_service.dart';

import '../fakes/fake_bunny_repository.dart';

BunnyPost _post(int id) => BunnyPost(
  id: id,
  site: BunnySite.e621,
  externalId: id,
  artist: 'someartist',
  score: 0,
  favCount: 0,
  commentCount: 0,
  fileExt: 'png',
  width: 100,
  height: 100,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

void main() {
  late FakeBunnyRepository repository;

  setUp(() {
    repository = FakeBunnyRepository();
  });

  group('PreviewCacheService', () {
    test('a miss fetches from the repository and caches the result', () async {
      repository.previewSearchResults['e621:wolf:1'] = [_post(1)];
      final cache = PreviewCacheService();

      final posts = await cache.getOrFetch(repository, BunnySite.e621, 'wolf');

      expect(posts.map((p) => p.id), [1]);
      expect(repository.previewSearchCalls, hasLength(1));
    });

    test('a hit within the TTL does not call the repository again', () async {
      repository.previewSearchResults['e621:wolf:1'] = [_post(1)];
      final cache = PreviewCacheService();

      await cache.getOrFetch(repository, BunnySite.e621, 'wolf');
      await cache.getOrFetch(repository, BunnySite.e621, 'wolf');

      expect(repository.previewSearchCalls, hasLength(1));
    });

    test('an expired entry is re-fetched', () async {
      repository.previewSearchResults['e621:wolf:1'] = [_post(1)];
      final cache = PreviewCacheService(ttl: const Duration(milliseconds: 1));

      await cache.getOrFetch(repository, BunnySite.e621, 'wolf');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cache.getOrFetch(repository, BunnySite.e621, 'wolf');

      expect(repository.previewSearchCalls, hasLength(2));
    });

    test('different site/query/page are cached independently', () async {
      repository.previewSearchResults['e621:wolf:1'] = [_post(1)];
      repository.previewSearchResults['inkbunny:wolf:1'] = [_post(2)];
      repository.previewSearchResults['e621:fox:1'] = [_post(3)];
      repository.previewSearchResults['e621:wolf:2'] = [_post(4)];
      final cache = PreviewCacheService();

      await cache.getOrFetch(repository, BunnySite.e621, 'wolf');
      await cache.getOrFetch(repository, BunnySite.inkbunny, 'wolf');
      await cache.getOrFetch(repository, BunnySite.e621, 'fox');
      await cache.getOrFetch(repository, BunnySite.e621, 'wolf', page: 2);

      expect(repository.previewSearchCalls, hasLength(4));
    });

    test('evicts the least recently used entry once over capacity', () async {
      final cache = PreviewCacheService(maxEntries: 2);
      repository.previewSearchResults['e621:a:1'] = [_post(1)];
      repository.previewSearchResults['e621:b:1'] = [_post(2)];
      repository.previewSearchResults['e621:c:1'] = [_post(3)];

      await cache.getOrFetch(repository, BunnySite.e621, 'a');
      await cache.getOrFetch(repository, BunnySite.e621, 'b');
      await cache.getOrFetch(repository, BunnySite.e621, 'c'); // evicts 'a', the least recently used

      repository.previewSearchCalls.clear();
      await cache.getOrFetch(repository, BunnySite.e621, 'a');
      expect(repository.previewSearchCalls, hasLength(1)); // 'a' had to be re-fetched

      repository.previewSearchCalls.clear();
      await cache.getOrFetch(repository, BunnySite.e621, 'c');
      expect(repository.previewSearchCalls, isEmpty); // 'c' was still cached
    });

    test('prefetch warms the cache without the caller needing to await it', () async {
      repository.previewSearchResults['e621:wolf:1'] = [_post(1)];
      final cache = PreviewCacheService();

      cache.prefetch(repository, BunnySite.e621, 'wolf');
      await Future<void>.delayed(Duration.zero); // let the fire-and-forget fetch complete

      final posts = await cache.getOrFetch(repository, BunnySite.e621, 'wolf');
      expect(posts.map((p) => p.id), [1]);
      expect(repository.previewSearchCalls, hasLength(1)); // the later getOrFetch hit the warmed cache
    });

    test('prefetch swallows a failure rather than throwing', () async {
      final cache = PreviewCacheService();
      expect(() => cache.prefetch(FakeThrowingRepository(), BunnySite.e621, 'wolf'), returnsNormally);
    });
  });
}

/// A minimal [FakeBunnyRepository] subclass whose [previewSearch] always
/// throws, for [PreviewCacheService.prefetch]'s best-effort error handling.
class FakeThrowingRepository extends FakeBunnyRepository {
  @override
  Future<List<BunnyPost>> previewSearch(
    BunnySite site,
    String query, {
    int page = 1,
    int inkbunnySearchInMask = 0,
    int inkbunnyFieldJoinType = 0,
    int inkbunnyStringJoinType = 0,
    String? inkbunnyUsername,
    int inkbunnySubmissionTypeMask = 0,
    int inkbunnyDaysLimit = 0,
    String? inkbunnyOrderBy,
    bool inkbunnyRandom = false,
    int inkbunnyScraps = 0,
  }) => Future.error(Exception('boom'));
}
