import 'package:flutter_test/flutter_test.dart';

import 'package:little_bunny/main.dart';
import 'package:little_bunny/repository/http_bunny_repository.dart';

void main() {
  testWidgets('app boots and shows the placeholder home page', (
    WidgetTester tester,
  ) async {
    // HttpBunnyRepository is used here purely because constructing it does
    // no I/O (unlike FfiBunnyRepository.open, which needs the native
    // library) -- this widget never calls any repository method.
    final repository = HttpBunnyRepository(baseUrl: Uri.parse('https://localhost:9443'), bearerToken: 'test-token', certificateSha256Fingerprint: '00' * 32);

    await tester.pumpWidget(LittleBunnyApp(repository: repository));

    expect(find.text('LittleBunny'), findsOneWidget);
    expect(find.text('App shell (M6) -- no screens yet.'), findsOneWidget);
    expect(find.text('Active repository: HttpBunnyRepository'), findsOneWidget);

    repository.close();
  });
}
