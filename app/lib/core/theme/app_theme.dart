import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Dark mode palette ──────────────────────────────────────────────────────
  static const Color background      = Color(0xFF0A0A0A);
  static const Color foreground      = Color(0xFFFAFAFA);
  static const Color card            = Color(0xFF141414);
  static const Color cardForeground  = Color(0xFFFAFAFA);
  static const Color surface         = Color(0xFF141414);
  static const Color surfaceElevated = Color(0xFF1F1F1F);
  static const Color secondary       = Color(0xFF242424);
  static const Color secondaryForeground = Color(0xFFFAFAFA);
  static const Color muted           = Color(0xFF1F1F1F);
  static const Color mutedForeground = Color(0xFF999999);
  static const Color border          = Color(0xFF292929);
  static const Color input           = Color(0xFF292929);

  // ── Gold accent (shared both modes) ───────────────────────────────────────
  static const Color gold      = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFE6C547);
  static const Color goldDark  = Color(0xFFC19B26);

  // ── Semantic colors (shared both modes) ───────────────────────────────────
  static const Color destructive           = Color(0xFFDC2626);
  static const Color destructiveForeground = Color(0xFFFAFAFA);
  static const Color success               = Color(0xFF16A34A);
  static const Color warning               = Color(0xFFF59E0B);

  // ── Light mode palette ────────────────────────────────────────────────────
  // Warm off-white base — easier on the eyes than pure white
  static const Color lightBackground      = Color(0xFFFAFAF8);
  static const Color lightSurface         = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF5F4F0);
  static const Color lightCard            = Color(0xFFFFFFFF);
  static const Color lightSecondary       = Color(0xFFF0EDE6);
  static const Color lightBorder          = Color(0xFFE2DDD5);
  static const Color lightInput           = Color(0xFFFFFFFF);
  static const Color lightForeground      = Color(0xFF1A1A1A);
  static const Color lightMutedForeground = Color(0xFF6B6560);
  static const Color lightMuted           = Color(0xFFF0EDE6);

  // ── Shared dark text theme ─────────────────────────────────────────────────
  static TextTheme get textTheme => TextTheme(
        displayLarge:  GoogleFonts.playfairDisplay(fontSize: 32, fontWeight: FontWeight.bold,    color: foreground),
        displayMedium: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.bold,    color: foreground),
        displaySmall:  GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w600,    color: foreground),
        headlineLarge: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w600,    color: foreground),
        headlineMedium:GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w600,    color: foreground),
        headlineSmall: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w600,    color: foreground),
        titleLarge:    GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600,  color: foreground),
        titleMedium:   GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500,  color: foreground),
        titleSmall:    GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500,  color: foreground),
        bodyLarge:     GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.normal, color: foreground),
        bodyMedium:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.normal, color: foreground),
        bodySmall:     GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.normal, color: mutedForeground),
        labelLarge:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500,  color: foreground),
        labelMedium:   GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500,  color: foreground),
        labelSmall:    GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500,  color: mutedForeground),
      );

  // ── Light text theme (proper warm-neutral colors) ─────────────────────────
  static TextTheme get _lightTextTheme => TextTheme(
        displayLarge:  GoogleFonts.playfairDisplay(fontSize: 32, fontWeight: FontWeight.bold,    color: lightForeground),
        displayMedium: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.bold,    color: lightForeground),
        displaySmall:  GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w600,    color: lightForeground),
        headlineLarge: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w600,    color: lightForeground),
        headlineMedium:GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w600,    color: lightForeground),
        headlineSmall: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w600,    color: lightForeground),
        titleLarge:    GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600,  color: lightForeground),
        titleMedium:   GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500,  color: lightForeground),
        titleSmall:    GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500,  color: lightForeground),
        bodyLarge:     GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.normal, color: lightForeground),
        bodyMedium:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.normal, color: lightForeground),
        bodySmall:     GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.normal, color: lightMutedForeground),
        labelLarge:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500,  color: lightForeground),
        labelMedium:   GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500,  color: lightForeground),
        labelSmall:    GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500,  color: lightMutedForeground),
      );

  // ── Dark theme ─────────────────────────────────────────────────────────────
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
          surfaceContainerHighest: surfaceElevated,
          error: destructive,
          onError: destructiveForeground,
          outline: surface,
          outlineVariant: Color(0xFF565656),
        ),
        scaffoldBackgroundColor: background,
        textTheme: textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 20, fontWeight: FontWeight.w600, color: foreground,
          ),
        ),
        cardTheme: const CardThemeData(color: card, elevation: 0, margin: EdgeInsets.zero),
        dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: gold, foregroundColor: background, elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: const BorderSide(color: border),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: gold,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: input,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: gold, width: 2)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: destructive)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: destructive, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: GoogleFonts.inter(color: mutedForeground, fontSize: 14),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: card,
          selectedItemColor: gold,
          unselectedItemColor: mutedForeground,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surfaceElevated,
          labelStyle: GoogleFonts.inter(fontSize: 12, color: foreground),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceElevated,
          contentTextStyle: GoogleFonts.inter(color: foreground, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: card,
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titleTextStyle: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w600, color: foreground),
          contentTextStyle: GoogleFonts.inter(fontSize: 14, color: mutedForeground),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: gold,
          unselectedLabelColor: mutedForeground,
          indicatorColor: gold,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
          dividerColor: border,
        ),
      );

  // ── Light theme ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: gold,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFFDF3C8),
          onPrimaryContainer: Color(0xFF5C4A00),
          secondary: lightSecondary,
          onSecondary: lightForeground,
          secondaryContainer: Color(0xFFEDE9E0),
          onSecondaryContainer: lightForeground,
          surface: lightSurface,
          onSurface: lightForeground,
          surfaceContainerLowest:  Color(0xFFFFFFFF),
          surfaceContainerLow:     lightBackground,
          surfaceContainer:        lightSurfaceElevated,
          surfaceContainerHigh:    Color(0xFFECEAE3),
          surfaceContainerHighest: Color(0xFFE5E2D9),
          onSurfaceVariant: lightMutedForeground,
          error: destructive,
          onError: Colors.white,
          errorContainer: Color(0xFFFFDAD6),
          onErrorContainer: Color(0xFF93000A),
          outline: lightBorder,
          outlineVariant: Color(0xFFD4CFC7),
          inverseSurface: Color(0xFF1A1A1A),
          onInverseSurface: Color(0xFFF5F3EE),
          inversePrimary: goldLight,
          shadow: Color(0x1A000000),
          scrim: Color(0x33000000),
        ),
        scaffoldBackgroundColor: lightBackground,
        textTheme: _lightTextTheme,

        appBarTheme: AppBarTheme(
          backgroundColor: lightSurface,
          foregroundColor: lightForeground,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x0D000000),
          scrolledUnderElevation: 1,
          titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 20, fontWeight: FontWeight.w600, color: lightForeground,
          ),
          iconTheme: const IconThemeData(color: lightForeground),
        ),

        cardTheme: CardThemeData(
          color: lightCard,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: lightBorder),
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: lightBorder, thickness: 1, space: 1,
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: gold,
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: lightForeground,
            side: const BorderSide(color: lightBorder),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: goldDark,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: lightInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: gold, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: destructive),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: destructive, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: GoogleFonts.inter(color: lightMutedForeground, fontSize: 14),
          labelStyle: GoogleFonts.inter(color: lightMutedForeground, fontSize: 14),
          floatingLabelStyle: GoogleFonts.inter(color: gold, fontSize: 12),
        ),

        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: lightSurface,
          selectedItemColor: gold,
          unselectedItemColor: lightMutedForeground,
          type: BottomNavigationBarType.fixed,
          elevation: 4,
          selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 12),
        ),

        chipTheme: ChipThemeData(
          backgroundColor: lightSurfaceElevated,
          labelStyle: GoogleFonts.inter(fontSize: 12, color: lightForeground),
          side: const BorderSide(color: lightBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),

        listTileTheme: const ListTileThemeData(
          tileColor: lightSurface,
          iconColor: lightMutedForeground,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),

        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return gold;
            return const Color(0xFFB0A99E);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFFDF3C8);
            }
            return const Color(0xFFE2DDD5);
          }),
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        ),

        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return gold;
            return Colors.transparent;
          }),
          checkColor: WidgetStateProperty.all(Colors.white),
          side: const BorderSide(color: lightBorder, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: lightForeground,
          contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          behavior: SnackBarBehavior.floating,
          elevation: 4,
        ),

        dialogTheme: DialogThemeData(
          backgroundColor: lightSurface,
          elevation: 8,
          shadowColor: const Color(0x1A000000),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 18, fontWeight: FontWeight.w600, color: lightForeground,
          ),
          contentTextStyle: GoogleFonts.inter(
            fontSize: 14, color: lightMutedForeground,
          ),
        ),

        popupMenuTheme: PopupMenuThemeData(
          color: lightSurface,
          elevation: 4,
          shadowColor: const Color(0x1A000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: lightBorder),
          ),
          textStyle: GoogleFonts.inter(fontSize: 14, color: lightForeground),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: gold,
          linearTrackColor: Color(0xFFF0EDE6),
        ),

        tabBarTheme: TabBarThemeData(
          labelColor: gold,
          unselectedLabelColor: lightMutedForeground,
          indicatorColor: gold,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
          dividerColor: lightBorder,
        ),
      );
}
