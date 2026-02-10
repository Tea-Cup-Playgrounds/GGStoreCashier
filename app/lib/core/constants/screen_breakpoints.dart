enum ScreenType {
  phone,      // < 600
  tablet,     // >= 600
}

enum OrientationType {
  portrait,
  landscape,
}

class Breakpoints {
  static const double phone = 600.0;
  static const double tablet = 600.0;
  
  // Responsive padding
  static double getHorizontalPadding(ScreenType type, OrientationType orientation) {
    if (type == ScreenType.tablet) {
      return orientation == OrientationType.landscape ? 48.0 : 32.0;
    }
    return 16.0;
  }
  
  // Responsive grid columns
  static int getGridColumns(ScreenType type, OrientationType orientation) {
    if (type == ScreenType.tablet) {
      return orientation == OrientationType.landscape ? 4 : 3;
    }
    return 2;
  }
  
  // Max content width for tablets
  static const double maxContentWidth = 1200.0;
}
