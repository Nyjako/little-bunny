import 'package:flutter_test/flutter_test.dart';

import 'package:little_bunny/main.dart';

void main() {
  testWidgets('app boots and shows the placeholder home page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LittleBunnyApp());

    expect(find.text('LittleBunny'), findsOneWidget);
    expect(find.text('App shell (M6) -- no screens yet.'), findsOneWidget);
  });
}
