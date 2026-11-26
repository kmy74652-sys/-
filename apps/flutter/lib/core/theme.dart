import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF17324D);
  static const green = Color(0xFF2F6654);
  static const canvas = Color(0xFFF4F7F8);
  static const muted = Color(0xFF718394);
  static const border = Color(0xFFE0E8EB);
}

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'AlshaeriArabic',
  scaffoldBackgroundColor: AppColors.canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.navy,
    primary: AppColors.navy,
    secondary: AppColors.green,
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(height: 1.45),
    bodyMedium: TextStyle(height: 1.45),
    bodySmall: TextStyle(height: 1.4),
    titleMedium: TextStyle(height: 1.3, fontWeight: FontWeight.w700),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.canvas,
    foregroundColor: AppColors.navy,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: AppColors.border),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
    ),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.border),
    ),
  ),
);
