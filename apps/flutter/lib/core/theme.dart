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
          secondary: AppColors.green),
      appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.canvas,
          foregroundColor: AppColors.navy,
          centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
      ),
      cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border))),
    );
