import 'package:flutter/widgets.dart';

/// Below this width the app is assumed to be running on a phone-sized
/// viewport, where the default `AppBar` chrome already fits comfortably --
/// above it (desktop/tablet-width windows, M9.6.6) the toolbar wastes a
/// disproportionate amount of vertical space, so screens shrink it. Also
/// reused by M9.6.5's responsive post-detail layout (wide: tags/details/
/// sources side by side; narrow: stacked).
const double wideScreenBreakpoint = 720;

/// Compact `AppBar.toolbarHeight` used on wide windows, vs. the Material
/// default of `kToolbarHeight` (56) left in place on phone-width windows.
const double compactToolbarHeight = 44;

bool isWideScreen(BuildContext context) => MediaQuery.sizeOf(context).width >= wideScreenBreakpoint;
