import 'package:material_ui/material_ui.dart';

abstract final class AppTheme {
  static ThemeData get light {
    const primary = Color(0xFF17324D);
    const secondary = Color(0xFFB9823B);
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      secondary: secondary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7F9FA),
      fontFamily: 'sans',
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
