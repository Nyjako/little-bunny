import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/tag_browse_screen.dart';
import 'package:little_bunny/screens/wiki_page_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

DownloadQueueService _downloadQueueService() => DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

BunnyPost _post({int id = 2, int externalId = 55, String title = 'A post'}) => BunnyPost(
  id: id,
  site: BunnySite.e621,
  externalId: externalId,
  artist: 'someartist',
  title: title,
  rating: 'safe',
  score: 0,
  favCount: 0,
  commentCount: 0,
  fileUrl: 'https://example.invalid/file.jpg',
  fileExt: 'jpg',
  width: 640,
  height: 480,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

Widget _wrap(FakeBunnyRepository repository, {String title = 'wolf'}) => wrapWithLocalization(
  WikiPageScreen(
    title: title,
    repository: repository,
    displaySettingsStore: const DisplaySettingsStore(),
    downloadSettingsStore: const DownloadSettingsStore(),
    downloadQueueService: _downloadQueueService(),
  ),
);

/// [RichMarkupText] renders its links as [TapGestureRecognizer]s inside a
/// single [Text.rich]'s [TextSpan] tree, so `find.text`/`tester.tap` can't
/// locate or hit them (the widget's plain-text content is the whole body,
/// not the individual span) -- this walks the span tree to find the
/// matching segment and invokes its recognizer directly instead.
void _tapLinkText(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    GestureRecognizer? recognizer;
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) {
        recognizer = span.recognizer;
        return false;
      }
      return true;
    });
    if (recognizer is TapGestureRecognizer) {
      (recognizer as TapGestureRecognizer).onTap?.call();
      return;
    }
  }
  fail('No tappable span found for "$text"');
}

void main() {
  testWidgets('shows the page title in the app bar', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.wikiPageByTitle['wolf'] = const BunnyWikiPage(id: 1, title: 'wolf', body: 'A canine.', isLocked: false);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'wolf'), findsOneWidget);
  });

  testWidgets('shows a not-found message when the tag has no wiki page', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('No wiki page for this tag.'), findsOneWidget);
  });

  testWidgets('renders the body and lists other names', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.wikiPageByTitle['wolf'] = const BunnyWikiPage(id: 1, title: 'wolf', body: 'A large canine.', otherNames: ['wolves', 'wolfkin'], isLocked: false);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('A large canine.'), findsOneWidget);
    expect(find.text('Also known as: wolves, wolfkin'), findsOneWidget);
  });

  testWidgets('tapping an author reference opens that artist\'s posts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.wikiPageByTitle['wolf'] = const BunnyWikiPage(id: 1, title: 'wolf', body: 'Drawn by {{someartist}}.', isLocked: false);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    _tapLinkText(tester, '{{someartist}}');
    await tester.pumpAndSettle();

    expect(find.byType(TagBrowseScreen), findsOneWidget);
  });

  testWidgets('tapping a wiki reference opens another wiki page', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.wikiPageByTitle['wolf'] = const BunnyWikiPage(id: 1, title: 'wolf', body: 'See [[canine]] for more.', isLocked: false);
    repository.wikiPageByTitle['canine'] = const BunnyWikiPage(id: 2, title: 'canine', body: 'A broader family.', isLocked: false);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    _tapLinkText(tester, '[[canine]]');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'canine'), findsOneWidget);
    expect(find.textContaining('A broader family.'), findsOneWidget);
  });

  testWidgets('tapping a thumb reference opens the referenced post', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.wikiPageByTitle['wolf'] = const BunnyWikiPage(id: 1, title: 'wolf', body: 'Example: thumb #55 above.', isLocked: false);
    repository.fetchPostResults['e621:55'] = 2;
    repository.postsById[2] = _post(title: 'Example post');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    _tapLinkText(tester, 'thumb #55');
    await tester.pumpAndSettle();

    expect(find.text('Example post'), findsOneWidget);
  });
}
