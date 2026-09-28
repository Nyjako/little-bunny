import 'package:flutter/material.dart';

import 'repository/bunny_repository.dart';
import 'repository/bunny_repository_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Standalone/:memory: until M7 adds a settings UI to let the user choose a
  // mode and a real db path / server config.
  final repository = await createBunnyRepository(const StandaloneConfig(dbPath: ':memory:', userAgent: 'little_bunny/1.0.0'));
  runApp(LittleBunnyApp(repository: repository));
}

/// Makes the active [BunnyRepository] available to the widget tree without
/// each screen needing to know which implementation is active -- the "one
/// repository interface" wiring the M6 roadmap entry describes.
class BunnyRepositoryScope extends InheritedWidget {
  final BunnyRepository repository;

  const BunnyRepositoryScope({super.key, required this.repository, required super.child});

  static BunnyRepository of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BunnyRepositoryScope>()!.repository;

  @override
  bool updateShouldNotify(BunnyRepositoryScope oldWidget) => repository != oldWidget.repository;
}

/// App shell (M6). No real screens yet -- login/app-lock is M7, browse/search
/// is M8. This just proves the app boots on top of the repository interface
/// implemented by M6.2 (FFI) and M6.3 (HTTP).
class LittleBunnyApp extends StatelessWidget {
  final BunnyRepository repository;

  const LittleBunnyApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return BunnyRepositoryScope(
      repository: repository,
      child: MaterialApp(
        title: 'LittleBunny',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const _PlaceholderHomePage(),
      ),
    );
  }
}

class _PlaceholderHomePage extends StatelessWidget {
  const _PlaceholderHomePage();

  @override
  Widget build(BuildContext context) {
    final repository = BunnyRepositoryScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('LittleBunny')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('App shell (M6) -- no screens yet.'),
            Text('Active repository: ${repository.runtimeType}'),
          ],
        ),
      ),
    );
  }
}
