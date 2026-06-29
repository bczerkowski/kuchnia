import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ciepła, „kuchenna" paleta — krem, terakota, oliwka, miód.
class AppColors {
  static const cream = Color(0xFFFBF3E8); // tło, jak rozsypana mąka
  static const card = Color(0xFFFFFCF7); // jasny papier przepisu
  static const terracotta = Color(0xFFD0674A); // paprykowy akcent
  static const terracottaDark = Color(0xFFB9543A);
  static const olive = Color(0xFF7C8C5A); // zioła / sałata
  static const honey = Color(0xFFE2A23C); // miód, słońce
  static const brown = Color(0xFF3A2C26); // tekst, czekolada
  static const muted = Color(0xFF927F72); // tekst drugorzędny
  static const line = Color(0xFFEADFD0); // delikatne linie
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
    );

    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.brown,
      displayColor: AppColors.brown,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.cream,
      colorScheme: const ColorScheme.light(
        primary: AppColors.terracotta,
        onPrimary: Colors.white,
        secondary: AppColors.olive,
        surface: AppColors.card,
        onSurface: AppColors.brown,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cream,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.brown,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: AppColors.brown,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.line),
        labelStyle: GoogleFonts.nunito(
          color: AppColors.brown,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.terracotta, width: 2),
        ),
      ),
    );
  }

  /// Nagłówek w cieplejszym, serifowym kroju.
  static TextStyle heading(double size, {FontWeight weight = FontWeight.w600, Color? color}) {
    return GoogleFonts.fraunces(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.brown,
      height: 1.1,
    );
  }
}
