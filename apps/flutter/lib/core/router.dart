import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/unified_task_table_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/tasks/task_detail_screen.dart';
import '../features/admin/report_designer_screen.dart';
import '../features/admin/task_management_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/admin/performance_analytics_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/reports/independent_reports_screen.dart';
import '../features/hr/hr_screen.dart';
import '../features/settings/settings_screen.dart';
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

class _PermissionGate extends StatefulWidget {
  const _PermissionGate({required this.permissions, required this.child});

  final Set<String> permissions;
  final Widget child;

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> {
  bool _loading = true;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await Supabase.instance.client.rpc('mobile_my_profile');
      final employee = raw is Map ? raw['employee'] : null;
      final rawPermissions = employee is Map ? employee['permissions'] : null;
      final permissions = rawPermissions is List
          ? rawPermissions.map((value) => value.toString()).toSet()
          : <String>{};
      if (!mounted) return;
      setState(() {
        _allowed = permissions.intersection(widget.permissions).isNotEmpty;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _allowed = false; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_allowed) return widget.child;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الوصول غير مسموح')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 12),
                const Text('لا تملك الصلاحية اللازمة لفتح هذه الشاشة.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('العودة إلى الرئيسية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
      GoRoute(
        path: '/tasks',
        builder: (context, state) => TasksScreen(
          initialStatus: state.uri.queryParameters['status'],
        ),
      ),
      GoRoute(
        path: '/admin/unified-tasks',
        builder: (context, state) => _PermissionGate(
          permissions: {'tasks.manage'},
          child: UnifiedTaskTableScreen(
            employeeUserId: state.uri.queryParameters['employee'],
          ),
        ),
      ),
      GoRoute(
        path: '/tasks/:taskId',
        builder: (context, state) =>
            TaskDetailScreen(taskId: state.pathParameters['taskId']!),
      ),
      GoRoute(
        path: '/admin',
        redirect: (context, state) {
          final section = state.uri.queryParameters['section'];
          // لا توجد شاشة عامة مستقلة للوحة الإدارة؛ افتح الأقسام الفعلية
          // فقط، وأعد أي رابط قديم للوحة العامة إلى الرئيسية.
          return section == null || section.isEmpty || section == 'overview'
              ? '/'
              : null;
        },
        builder: (context, state) => AdminScreen(
          initialSection: state.uri.queryParameters['section'],
        ),
      ),
      GoRoute(
        path: '/admin/tasks',
        builder: (context, state) => _PermissionGate(
          permissions: {'tasks.manage'},
          child: TaskManagementScreen(
            unifiedOnly: true,
            initialTaskFilter: state.uri.queryParameters['status'],
          ),
        ),
      ),
      GoRoute(
        path: '/admin/unified-task-management',
        builder: (context, state) => const _PermissionGate(
          permissions: {'tasks.manage'},
          child: TaskManagementScreen(unifiedOnly: true),
        ),
      ),
      GoRoute(
        path: '/admin/report-designer',
        builder: (context, state) => const _PermissionGate(
          permissions: {'tasks.manage'},
          child: ReportDesignerScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/performance',
        builder: (context, state) => const _PermissionGate(
          permissions: {'tasks.review', 'reports.read_all'},
          child: PerformanceAnalyticsScreen(),
        ),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => _PermissionGate(
          permissions: {
            'reports.read_all',
            'tasks.review',
            'tasks.manage',
            'report_submissions.review',
            'report_submissions.approve',
          },
          child: ReportsScreen(
            initialFilter: state.uri.queryParameters['status'],
          ),
        ),
      ),
      GoRoute(
        path: '/reports/daily',
        redirect: (context, state) => '/reports/independent',
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
