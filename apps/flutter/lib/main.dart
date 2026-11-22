import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://fjmryqhdwxsocdzswnkq.supabase.co',
  );
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_vRWbeJO5I_KJwJjqVDSZLA_pEHABsPk',
  );

  final hasSupabaseConfig =
      supabaseUrl.startsWith('https://') && supabasePublishableKey.isNotEmpty;

  if (hasSupabaseConfig) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
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
      home: isSupabaseConfigured
          ? const _AuthenticationGate()
          : const LoginScreen(isSupabaseConfigured: false),
    );
  }
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate();

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? client.auth.currentSession;
        if (session == null) {
          return const LoginScreen(isSupabaseConfigured: true);
        }
        return const HomeScreen();
      },
    );
  }
}
