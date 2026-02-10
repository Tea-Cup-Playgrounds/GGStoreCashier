import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/constants/screen_breakpoints.dart';

ScreenType getScreenType(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  return width >= Breakpoints.tablet ? ScreenType.tablet : ScreenType.phone;
}

OrientationType getOrientation(BuildContext context) {
  final orientation = MediaQuery.of(context).orientation;
  return orientation == Orientation.landscape 
      ? OrientationType.landscape 
      : OrientationType.portrait;
}

class ResponsiveLayout extends StatelessWidget {
  final Widget phone;
  final Widget? tablet;
  final Widget? tabletLandscape;

  const ResponsiveLayout({
    super.key,
    required this.phone,
    this.tablet,
    this.tabletLandscape,
  });

  @override
  Widget build(BuildContext context) {
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);

    if (screenType == ScreenType.tablet) {
      if (orientation == OrientationType.landscape && tabletLandscape != null) {
        return tabletLandscape!;
      }
      return tablet ?? phone;
    }
    return phone;
  }
}

