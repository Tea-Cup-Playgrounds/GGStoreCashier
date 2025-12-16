import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/constants/screen_breakpoints.dart';

ScreenType getScreenType(BuildContext context) {
  final width = MediaQuery.of(context).size.width;

  if (width < Breakpoints.compactStandart) {
    return ScreenType.extraCompact;
  } else if (width < Breakpoints.medium) {
    return ScreenType.compactStandart;
  } else {
    return ScreenType.medium;
  }
}

