import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // BRAND ACCENT - Muted Sage Green (more desaturated)
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  static const Color accent = Color(
    0xFF6B9B7A,
  ); // Muted sage green (desaturated)
  static const Color accentLight = Color(0xFF8BB099); // Lighter variant
  static const Color accentDark = Color(0xFF557A63); // Darker variant

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSET COLORS — Use these for DSP / $DIASPORA / Fiat throughout the app
  // ═══════════════════════════════════════════════════════════════════════════
  static const Color dspColor = accent; // DSP = brand sage green
  static const Color tokenColor = Color(0xFFE67E22); // $DIASPORA = warm orange
  static const Color fiatColor = Color(0xFF22C55E); // Fiat = green

  // ═══════════════════════════════════════════════════════════════════════════
  // ELEVATION SURFACE SYSTEM
  // 4 levels (0–3), constant step gap per level.
  // Light: 3-step gap (subtle on bright surfaces)
  // Dark:  8-step gap (perceptually equivalent on dark surfaces)
  // ═══════════════════════════════════════════════════════════════════════════
  // Light mode elevation surfaces (4-step gap)
  static const Color elevationLight0 = Color(0xFFF3F3F3); // 243 — Page bg
  static const Color elevationLight1 = Color(
    0xFFF7F7F7,
  ); // 247 — Cards/Sections
  static const Color elevationLight2 = Color(
    0xFFFBFBFB,
  ); // 251 — Inner containers
  static const Color elevationLight3 = Color(
    0xFFFFFFFF,
  ); // 255 — Dialogs/Modals

  // Dark mode elevation surfaces (8-step gap)
  static const Color elevationDark0 = Color(0xFF0A0A0A); // 10  — Page bg
  static const Color elevationDark1 = Color(0xFF121212); // 18  — Cards/Sections
  static const Color elevationDark2 = Color(
    0xFF1A1A1A,
  ); // 26  — Inner containers
  static const Color elevationDark3 = Color(0xFF222222); // 34  — Dialogs/Modals

  /// Get the surface color for a given elevation level (0–3).
  static Color elevationColor(BuildContext context, int level) {
    assert(level >= 0 && level <= 3, 'Elevation level must be 0–3');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (level) {
      case 0:
        return isDark ? elevationDark0 : elevationLight0;
      case 1:
        return isDark ? elevationDark1 : elevationLight1;
      case 2:
        return isDark ? elevationDark2 : elevationLight2;
      case 3:
        return isDark ? elevationDark3 : elevationLight3;
      default:
        return isDark ? elevationDark0 : elevationLight0;
    }
  }

  // Legacy aliases (mapped to elevation levels)
  static const Color _lightBackground = elevationLight0;
  static const Color _lightForeground = Color(0xFF151515); // Off-Black
  static const Color _lightSurface = elevationLight1;

  static const Color _darkBackground = elevationDark0;
  static const Color _darkForeground = Color(0xFFF5F5F5); // Off-White

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // SEMANTIC COLORS
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  static const Color success = Color(0xFF22C55E); // Green
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color error = Color(0xFFEF4444); // Red
  static const Color info = Color(0xFF3B82F6); // Blue

  // ═══════════════════════════════════════════════════════════════════════════
  // HORIZONTAL SPACING SYSTEM
  // Phone screens have limited width — maximize every pixel.
  //   Page body:    8px padding → slight breathing room at screen edges
  //   Sections:     0px margin → children sit flush inside page padding
  //   Content:      8px padding → breathing room inside containers
  // ═══════════════════════════════════════════════════════════════════════════
  static const double pageHorizontalPadding = 8.0; // Page-level body padding
  static const double sectionHorizontalMargin = 0.0; // Children have 0 margin
  static const double contentHorizontalPadding = 8.0; // Inside-card padding
  static const double elementSpacing = 8.0; // Gap between elements

  // Section internals
  static const double sectionHorizontalPadding = 8.0;
  static const double sectionVerticalPadding = 16.0;

  // Card internals
  static const double cardHorizontalMargin = 0.0;
  static const double cardHorizontalPadding = 8.0;
  static const double cardVerticalPadding = 16.0;
  static const double cardPadding = 20.0; // Legacy - prefer specific padding

  static const double standardBorderRadius = 16.0;

  // EdgeInsets presets
  static const EdgeInsets pagePaddingEdgeInsets = EdgeInsets.symmetric(
    horizontal: pageHorizontalPadding, // 8px — page body padding
  );
  static const EdgeInsets contentPaddingEdgeInsets = EdgeInsets.symmetric(
    horizontal: contentHorizontalPadding, // 8px — inside cards
  );
  static const EdgeInsets sectionPaddingEdgeInsets = EdgeInsets.symmetric(
    horizontal: sectionHorizontalPadding,
    vertical: sectionVerticalPadding,
  );
  static const EdgeInsets cardPaddingEdgeInsets = EdgeInsets.symmetric(
    horizontal: cardHorizontalPadding,
    vertical: cardVerticalPadding,
  );

  // â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â•
  // GLOBAL THEME DESIGN
  // â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â•

  static BoxDecoration cardDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? elevationDark1 : elevationLight1,
      borderRadius: BorderRadius.circular(standardBorderRadius),
    );
  }

  static BoxDecoration innerDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? elevationDark2 : elevationLight2,
      borderRadius: BorderRadius.circular(12),
    );
  }

  static BoxDecoration sectionDecoration(BuildContext context) {
    return cardDecoration(context);
  }

  static BoxDecoration pageDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? _darkBackground : _lightBackground,
      // Optional: Add subtle top gradient for "Rich Aesthetics"
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [const Color(0xFF0F1714), _darkBackground]
            : [const Color(0xFFF0F7F4), _lightBackground],
        stops: const [0.0, 0.3],
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: accent, // Explicit for legacy widgets
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBackground,
      canvasColor: _lightBackground,
      cardColor: _lightSurface, // Level 1 — cards
      dialogTheme: const DialogThemeData(backgroundColor: elevationLight3),
      disabledColor: _lightForeground.withAlpha(76),
      hintColor: _lightForeground.withAlpha(128),
      shadowColor: Colors.transparent, // No shadows

      colorScheme: const ColorScheme.light(
        primary: accent, // Brand green for interactive elements
        onPrimary: Colors.white,
        primaryContainer: _lightSurface,
        onPrimaryContainer: _lightForeground,
        secondary: accentLight, // Lighter accent variant
        onSecondary: _lightForeground,
        secondaryContainer: _lightSurface,
        onSecondaryContainer: _lightForeground,
        tertiary: accentDark, // Darker accent variant
        onTertiary: Colors.white,
        surface: _lightBackground,
        onSurface: _lightForeground,
        surfaceContainerHighest: Color(
          0xFFE8E8E8,
        ), // Elevated surfaces & incoming chat bubbles
        onSurfaceVariant: _lightForeground,
        error: error,
        onError: Colors.white,
        outline: Colors.transparent,
        outlineVariant: Colors.transparent,
      ),
      dividerColor: Colors.transparent,
      dividerTheme: const DividerThemeData(color: Colors.transparent, space: 0),

      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: _lightForeground,
        displayColor: _lightForeground,
        decorationColor: _lightForeground,
      ),
      iconTheme: const IconThemeData(color: _lightForeground),
      primaryIconTheme: const IconThemeData(color: accent),

      appBarTheme: const AppBarTheme(
        backgroundColor: _lightBackground,
        foregroundColor: _lightForeground,
        elevation: 0,
        scrolledUnderElevation: 0, // No shadow on scroll
        centerTitle: true,
        iconTheme: IconThemeData(color: _lightForeground),
        titleTextStyle: TextStyle(
          color: _lightForeground,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: const CardThemeData(
        color: _lightSurface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(standardBorderRadius)),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevationLight2, // Level 2 — inputs sit inside Level 1 cards
        labelStyle: TextStyle(color: _lightForeground.withAlpha(178)),
        hintStyle: TextStyle(color: _lightForeground.withAlpha(102)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(standardBorderRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(standardBorderRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(standardBorderRadius),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurface,
        selectedColor: accent.withAlpha(38),
        labelStyle: const TextStyle(color: _lightForeground),
        secondaryLabelStyle: const TextStyle(color: accent),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(standardBorderRadius),
        ),
        elevation: 0,
        pressElevation: 0,
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(standardBorderRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide.none, // No border
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lightBackground,
        modalBackgroundColor: _lightBackground,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: accent, // Accent green pill when selected
        backgroundColor: _lightBackground,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white); // White on green
          }
          return IconThemeData(color: _lightForeground.withAlpha(128));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: _lightForeground.withAlpha(128),
            fontSize: 12,
          );
        }),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: elevationLight3,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: accent,
        headerForegroundColor: Colors.white,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) {
            return _lightForeground.withAlpha(76);
          }
          return _lightForeground;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.all(accent),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        todayBorder: const BorderSide(color: accent, width: 1.5),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return _lightForeground;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        rangeSelectionBackgroundColor: accent.withAlpha(38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        dayOverlayColor: WidgetStateProperty.all(accent.withAlpha(25)),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: accent, // Explicit for legacy widgets
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkBackground,
      canvasColor: _darkBackground,
      cardColor: elevationDark1, // Level 1 — cards
      dialogTheme: const DialogThemeData(backgroundColor: elevationDark3),
      disabledColor: _darkForeground.withAlpha(76),
      hintColor: _darkForeground.withAlpha(128),
      shadowColor: Colors.transparent, // No shadows

      colorScheme: const ColorScheme.dark(
        primary: accent, // Brand green for interactive elements
        onPrimary: Colors.white,
        primaryContainer: elevationDark1,
        onPrimaryContainer: _darkForeground,
        secondary: accentLight, // Lighter accent variant
        onSecondary: _darkBackground,
        secondaryContainer: elevationDark1,
        onSecondaryContainer: _darkForeground,
        tertiary: accentDark, // Darker accent variant
        onTertiary: Colors.white,
        surface: _darkBackground,
        onSurface: _darkForeground,
        surfaceContainerHighest: Color(
          0xFF2A2A2A,
        ), // Elevated surfaces & incoming chat bubbles
        onSurfaceVariant: _darkForeground,
        error: error,
        onError: Colors.white,
        outline: Colors.transparent,
        outlineVariant: Colors.transparent,
      ),
      dividerColor: Colors.transparent,
      dividerTheme: const DividerThemeData(color: Colors.transparent, space: 0),

      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: _darkForeground,
        displayColor: _darkForeground,
        decorationColor: _darkForeground,
      ),
      iconTheme: const IconThemeData(color: _darkForeground),
      primaryIconTheme: const IconThemeData(color: accent),

      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBackground,
        foregroundColor: _darkForeground,
        elevation: 0,
        scrolledUnderElevation: 0, // No shadow on scroll
        centerTitle: true,
        iconTheme: IconThemeData(color: _darkForeground),
        titleTextStyle: TextStyle(
          color: _darkForeground,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: const CardThemeData(
        color: elevationDark1,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(standardBorderRadius)),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevationDark2, // Level 2 — inputs sit inside Level 1 cards
        labelStyle: TextStyle(color: _darkForeground.withAlpha(178)),
        hintStyle: TextStyle(color: _darkForeground.withAlpha(102)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(standardBorderRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(standardBorderRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(standardBorderRadius),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: elevationDark1,
        selectedColor: accent.withAlpha(51),
        labelStyle: const TextStyle(color: _darkForeground),
        secondaryLabelStyle: const TextStyle(color: accent),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(standardBorderRadius),
        ),
        elevation: 0,
        pressElevation: 0,
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(standardBorderRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide.none, // No border
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _darkBackground,
        modalBackgroundColor: _darkBackground,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: accent, // Accent green pill when selected
        backgroundColor: _darkBackground,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white); // White on green
          }
          return IconThemeData(color: _darkForeground.withAlpha(128));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(color: _darkForeground.withAlpha(128), fontSize: 12);
        }),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: elevationDark3,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: accent,
        headerForegroundColor: Colors.white,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) {
            return _darkForeground.withAlpha(76);
          }
          return _darkForeground;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.all(accent),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        todayBorder: const BorderSide(color: accent, width: 1.5),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return _darkForeground;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        rangeSelectionBackgroundColor: accent.withAlpha(38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        dayOverlayColor: WidgetStateProperty.all(accent.withAlpha(25)),
      ),
    );
  }
}
