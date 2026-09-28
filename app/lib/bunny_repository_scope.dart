import 'package:flutter/widgets.dart';

import 'repository/bunny_repository.dart';

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
