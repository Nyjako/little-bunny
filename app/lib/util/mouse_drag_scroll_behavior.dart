import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Flutter's default [ScrollBehavior] excludes [PointerDeviceKind.mouse] from
/// [dragDevices], so plain click-and-drag doesn't scroll/swipe a `PageView`
/// on desktop out of the box. Wrap just the swipeable widget (not a whole
/// screen) in `ScrollConfiguration(behavior: const MouseDragScrollBehavior(),
/// child: ...)` to opt that one widget in without changing scroll behavior
/// anywhere else in the app.
class MouseDragScrollBehavior extends MaterialScrollBehavior {
  const MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse};
}
