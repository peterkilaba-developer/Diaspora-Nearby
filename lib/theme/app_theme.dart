import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // BRAND ACCENT - Muted Sage Green (more desaturated)
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  static const Color accent = Color(0xFF6B9B7A); // Muted sage green (desaturated)
  static const Color accentLight = Color(0xFF8BB099); // Lighter variant
  static const Color accentDark = Color(0xFF557A63); // Darker variant

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // LIGHT MODE - Clean Flat Palette
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  static const Color _lightBackground = Color(0xFFFAFAFA); // Off-White
  static const Color _lightForeground = Color(0xFF151515); // Off-Black
  static const Color _lightSurface = Color(0xFFF4F4F4); // Subtle card bg (halved contrast)
  
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // DARK MODE - Clean Flat Palette
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  static const Color _darkBackground = Color(0xFF0A0A0A); // Deep Black
  static const Color _darkForeground = Color(0xFFF5F5F5); // Off-White
  static const Color _darkSurface = Color(0xFF141414); // Subtle card bg (halved contrast)

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // SEMANTIC COLORS
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  static const Color success = Color(0xFF22C55E); // Green
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color error = Color(0xFFEF4444); // Red
  static const Color info = Color(0xFF3B82F6); // Blue

  // â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• 
  // LAYOUT CONSTANTS
  // â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• â• 
  static const double pagePadding = 8.0;
  static const double cardPadding = 20.0;
  static const EdgeInsets pagePaddingEdgeInsets = EdgeInsets.all(pagePadding);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: accent, // Explicit for legacy widgets
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBackground,
      canvasColor: _lightBackground,
      cardColor: _lightSurface, // Glass surface tint
      dialogBackgroundColor: _lightSurface,
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
        surfaceContainerHighest: _lightSurface, // For elevated surfaces
        surfaceVariant: Color(0xFFE8E8E8), // Visible bg for incoming message bubbles
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
        titleTextStyle: TextStyle(color: _lightForeground, fontSize: 20, fontWeight: FontWeight.w600),
      ),
      
      cardTheme: const CardThemeData(
        color: _lightSurface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurface, // Glass tint for inputs
        labelStyle: TextStyle(color: _lightForeground.withAlpha(178)),
        hintStyle: TextStyle(color: _lightForeground.withAlpha(102)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none, 
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      
      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurface,
        selectedColor: accent.withAlpha(38),
        labelStyle: const TextStyle(color: _lightForeground),
        secondaryLabelStyle: const TextStyle(color: accent),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
        ),
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
            return const TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600);
          }
          return TextStyle(color: _lightForeground.withAlpha(128), fontSize: 12);
        }),
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
      cardColor: _darkSurface, // Glass surface tint
      dialogBackgroundColor: _darkSurface,
      disabledColor: _darkForeground.withAlpha(76),
      hintColor: _darkForeground.withAlpha(128),
      shadowColor: Colors.transparent, // No shadows

      colorScheme: const ColorScheme.dark(
        primary: accent, // Brand green for interactive elements
        onPrimary: Colors.white,
        primaryContainer: _darkSurface,
        onPrimaryContainer: _darkForeground,
        secondary: accentLight, // Lighter accent variant
        onSecondary: _darkBackground,
        secondaryContainer: _darkSurface,
        onSecondaryContainer: _darkForeground,
        tertiary: accentDark, // Darker accent variant
        onTertiary: Colors.white,
        surface: _darkBackground,
        onSurface: _darkForeground,
        surfaceContainerHighest: _darkSurface, // For elevated surfaces
        surfaceVariant: Color(0xFF2A2A2A), // Visible bg for incoming message bubbles
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
        titleTextStyle: TextStyle(color: _darkForeground, fontSize: 20, fontWeight: FontWeight.w600),
      ),
      
      cardTheme: const CardThemeData(
        color: _darkSurface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurface, // Glass tint for inputs
        labelStyle: TextStyle(color: _darkForeground.withAlpha(178)),
        hintStyle: TextStyle(color: _darkForeground.withAlpha(102)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      
      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurface,
        selectedColor: accent.withAlpha(51),
        labelStyle: const TextStyle(color: _darkForeground),
        secondaryLabelStyle: const TextStyle(color: accent),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
        ),
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
            return const TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600);
          }
          return TextStyle(color: _darkForeground.withAlpha(128), fontSize: 12);
        }),
      ),
    );
  }
}
