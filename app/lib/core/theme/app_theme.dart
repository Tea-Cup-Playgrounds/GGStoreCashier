import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors - Luxury Black-White-Gold Palette
  static const Color background = Color(0xFF0A0A0A); // --background: 0 0% 4%
  static const Color foreground = Color(0xFFFAFAFA); // --foreground: 0 0% 98%

  static const Color card = Color(0xFF141414); // --card: 0 0% 8%
  static const Color cardForeground = Color(0xFFFAFAFA);

  static const Color surface = Color(0xFF141414); // --surface: 0 0% 8%
  static const Color surfaceElevated =
      Color(0xFF1F1F1F); // --surface-elevated: 0 0% 12%

  // Gold Primary
  static const Color gold = Color(0xFFD4AF37); // --gold: 43 76% 52%
  static const Color goldLight = Color(0xFFE6C547); // --gold-light: 43 76% 62%
  static const Color goldDark = Color(0xFFC19B26); // --gold-dark: 43 76% 42%

  static const Color secondary = Color(0xFF242424); // --secondary: 0 0% 14%
  static const Color secondaryForeground = Color(0xFFFAFAFA);

  static const Color muted = Color(0xFF1F1F1F); // --muted: 0 0% 12%
  static const Color mutedForeground =
      Color(0xFF999999); // --muted-foreground: 0 0% 60%

  static const Color border = Color(0xFF292929); // --border: 0 0% 16%
  static const Color input = Color(0xFF292929);

  static const Color destructive = Color(0xFFDC2626);
  static const Color destructiveForeground = Color(0xFFFAFAFA);

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);

// ===== Light Mode - Settings =====
  static const Color lightBackground = Color(0xFFF8F8F8);
  static const Color lightSurface = Color(0xFFFFFFFF);

  static const Color lightSettingsTile = Color(0xFFFDFDFD);
  static const Color lightSettingsTileBorder = Color(0xFFE5E5E5);
  static const Color lightMutedForeground = Color(0xFF737373);

  // Text Styles
  static TextTheme get textTheme => TextTheme(
        displayLarge: GoogleFonts.playfairDisplay(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        displayMedium: GoogleFonts.playfairDisplay(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        displaySmall: GoogleFonts.playfairDisplay(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        headlineLarge: GoogleFonts.playfairDisplay(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        headlineMedium: GoogleFonts.playfairDisplay(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        headlineSmall: GoogleFonts.playfairDisplay(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: foreground,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: foreground,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: mutedForeground,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: mutedForeground,
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
            brightness: Brightness.dark,
            primary: gold,
            onPrimary: background,
            secondary: secondary,
            onSecondary: secondaryForeground,
            surface: background,
            onSurface: foreground,
            error: destructive,
            onError: destructiveForeground,
            outline: surface,
            outlineVariant: Color.fromARGB(255, 86, 86, 86)),
        scaffoldBackgroundColor: background,
        textTheme: textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
        cardTheme: const CardTheme(
          color: card,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: gold,
            foregroundColor: background,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: const BorderSide(color: border),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: gold,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: input,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: gold, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: destructive),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: GoogleFonts.inter(
            color: mutedForeground,
            fontSize: 14,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: card,
          selectedItemColor: gold,
          unselectedItemColor: mutedForeground,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
      );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.light(
            primary: gold,
            onPrimary: Colors.white,
            secondary: Colors.grey.shade100,
            onSecondary: Colors.black,
            surface: Colors.white,
            onSurface: Colors.black,
            error: destructive,
            outline: Colors.grey.shade200,
            outlineVariant: Colors.grey.shade500,
            onError: Colors.white,
            surfaceContainer: Colors.grey.shade200),
        scaffoldBackgroundColor: Colors.white,
        textTheme: textTheme.apply(
          bodyColor: Colors.black87,
          displayColor: Colors.black,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        cardTheme: CardTheme(
          color: Colors.grey.shade200,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: lightSettingsTileBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: lightSettingsTileBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: gold, width: 2),
          ),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: foreground,
          selectedItemColor: gold,
          unselectedItemColor: Colors.grey.shade700,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
      );
}
