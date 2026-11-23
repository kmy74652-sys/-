import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/unified_task_table_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/tasks/task_detail_screen.dart';
import '../features/admin/report_designer_screen.dart';
import '../features/admin/task_management_screen.dart';
import '../features/admin/performance_analytics_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/reports/independent_reports_screen.dart';
import '../features/hr/hr_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/app_customizer_screen.dart';
import '../features/agreements/agreements_screen.dart';

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier() {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

late final GoRouter appRouter;

void initializeRouter() {
  final authRefresh = _AuthRefreshNotifier();
  appRouter = GoRouter(
    refreshListenable: authRefresh,
    initialLocation: '/',
    redirect: (context, state) {
      final signedIn = Supabase.instance.client.auth.currentSession != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn && !atLogin) return '/login';
      if (signedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/tasks', builder: (context, state) => const TasksScreen()),
      GoRoute(
        path: '/admin/unified-tasks',
        builder: (context, state) => const UnifiedTaskTableScreen(),
      ),
      GoRoute(
        path: '/tasks/:taskId',
        builder: (context, state) =>
            TaskDetailScreen(taskId: state.pathParameters['taskId']!),
      ),
      // لوحة الإدارة الكاملة أصبحت داخل الرئيسية للمدير؛ يمنع هذا المسار
      // إنشاء نسخة ثانية من نفس اللوحة عند فتح رابط قديم.
      GoRoute(path: '/admin', redirect: (context, state) => '/'),
      GoRoute(
        path: '/admin/tasks',
        builder: (context, state) => const TaskManagementScreen(),
      ),
      GoRoute(
        path: '/admin/report-designer',
        builder: (context, state) => const ReportDesignerScreen(),
      ),
      GoRoute(
        path: '/admin/performance',
        builder: (context, state) => const PerformanceAnalyticsScreen(),
      ),
      GoRoute(
        path: '/admin/customizer',
        builder: (context, state) => const AppCustomizerScreen(),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/reports/daily',
        builder: (context, state) => const IndependentReportsScreen(),
      ),
      GoRoute(
        path: '/reports/independent',
        builder: (context, state) => const IndependentReportsScreen(),
      ),
      GoRoute(path: '/hr', builder: (context, state) => const HrScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/agreement',
        builder: (context, state) => const AgreementsScreen(),
      ),
    ],
  );
}
