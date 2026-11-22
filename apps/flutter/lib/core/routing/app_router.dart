import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/home/home_page.dart';
import '../../features/more/more_page.dart';
import '../../features/reports/reports_page.dart';
import '../../features/tasks/tasks_page.dart';
import '../../shared/widgets/app_shell.dart';

abstract final class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/tasks',
            builder: (context, state) => const TasksPage(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsPage(),
          ),
          GoRoute(path: '/more', builder: (context, state) => const MorePage()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('صفحة غير موجودة')),
      body: Center(child: Text(state.error.toString())),
    ),
  );
}
