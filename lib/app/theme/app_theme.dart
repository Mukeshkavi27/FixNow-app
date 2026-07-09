import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // FixNow palette
  static const Color primary = Color(0xFF0B5EEA); // logo blue
  static const Color accent = Color(0xFFFF7A00); // logo orange
  static const Color accentDark = Color(0xFFE86200);
  static const Color background = Color(0xFFF7FAFF);
  static const Color surface = Color(0xFFF4F8FF);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE1E8F5);
  static const Color textPrimary = Color(0xFF15243B);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color starColor = Color(0xFFFBBF24);
  static const Color badgeOrange = Color(0xFFFF6B2B);
  static const Color instantGreen = Color(0xFF31C48D);

  // Dark palette
  static const Color darkBackground = Color(0xFF121826);
  static const Color darkSurface = Color(0xFF1B2333);
  static const Color darkCardBg = Color(0xFF1E2738);
  static const Color darkDivider = Color(0xFF2B3447);
  static const Color darkTextPrimary = Color(0xFFF3F4F6);
  static const Color darkTextSecondary = Color(0xFFA0AEC0);
  static const Color darkTextHint = Color(0xFF6B7686);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: primary,
          secondary: accent,
          surface: background,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: textPrimary,
          surfaceContainerHighest: surface,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          shadowColor: Color(0x18000000),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: cardBg,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: divider),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: divider,
          thickness: 1,
          space: 0,
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: surface,
          selectedColor: primary,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: divider),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: background,
          selectedItemColor: primary,
          unselectedItemColor: textHint,
          elevation: 12,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          secondary: accent,
          surface: darkSurface,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: darkTextPrimary,
          surfaceContainerHighest: darkSurface,
        ),
        scaffoldBackgroundColor: darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkBackground,
          foregroundColor: darkTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          shadowColor: Color(0x40000000),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
          titleTextStyle: TextStyle(
            color: darkTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: darkCardBg,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: darkDivider),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: darkSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: darkDivider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: darkDivider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: darkDivider,
          thickness: 1,
          space: 0,
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: darkSurface,
          selectedColor: accent,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: darkDivider),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: darkBackground,
          selectedItemColor: accent,
          unselectedItemColor: darkTextHint,
          elevation: 12,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}
