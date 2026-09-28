import 'package:flutter/material.dart';

void main() {
  runApp(const LittleBunnyApp());
}

/// App shell (M6). No real screens yet -- login/app-lock is M7, browse/search
/// is M8. This just proves the app boots on top of the repository interface
/// that M6.2/M6.3 will implement.
class LittleBunnyApp extends StatelessWidget {
  const LittleBunnyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LittleBunny',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const _PlaceholderHomePage(),
    );
  }
}

class _PlaceholderHomePage extends StatelessWidget {
  const _PlaceholderHomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LittleBunny')),
      body: const Center(child: Text('App shell (M6) -- no screens yet.')),
    );
  }
}
