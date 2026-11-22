import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  final hasSupabaseConfig =
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;

  if (hasSupabaseConfig) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  runApp(AlshaeriApp(isSupabaseConfigured: hasSupabaseConfig));
}

class AlshaeriApp extends StatelessWidget {
  const AlshaeriApp({super.key, required this.isSupabaseConfigured});

  final bool isSupabaseConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الشاعري الإداري',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: LoginScreen(isSupabaseConfigured: isSupabaseConfigured),
    );
  }
}
