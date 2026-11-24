import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_config.dart';
import 'core/deep_link_controller.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: const Color(0xFFF5F7FD),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'تعذر عرض هذه الصفحة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أغلق الصفحة وافتحها من جديد. إذا استمرت المشكلة أرسل هذه الرسالة للدعم:\n${details.exceptionAsString()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  if (!AppConfig.hasSupabase) {
    runApp(const ProviderScope(child: ConfigurationApp()));
    return;
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  initializeRouter();
  final links = DeepLinkController();
  final initial = await links.initialRoute();
  if (initial != null && Supabase.instance.client.auth.currentSession == null) {
    await links.savePending(initial);
  }
  runApp(
    ProviderScope(
      child: AlshaeriApp(deepLinks: links, initial: initial),
    ),
  );
}

class AlshaeriApp extends StatefulWidget {
  const AlshaeriApp({super.key, required this.deepLinks, this.initial});
  final DeepLinkController deepLinks;
  final String? initial;
  @override
  State<AlshaeriApp> createState() => _AlshaeriAppState();
}

class _AlshaeriAppState extends State<AlshaeriApp> {
  @override
  void initState() {
    super.initState();
    if (widget.initial != null &&
        Supabase.instance.client.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => appRouter.go(widget.initial!),
      );
    }
    widget.deepLinks.listen((route) async {
      if (Supabase.instance.client.auth.currentSession != null) {
        appRouter.go(route);
      } else {
        await widget.deepLinks.savePending(route);
        appRouter.go('/login');
      }
    });
  }

  @override
  void dispose() {
    widget.deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'NEXORA — Smart Business Management',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    routerConfig: appRouter,
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

class ConfigurationApp extends StatelessWidget {
  const ConfigurationApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: const Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'أضف إعدادات Supabase عبر SUPABASE_URL وSUPABASE_ANON_KEY لتشغيل التطبيق.',
            ),
          ),
        ),
      ),
    ),
  );
}
