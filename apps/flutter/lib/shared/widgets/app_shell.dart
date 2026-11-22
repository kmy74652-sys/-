import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  int get selectedIndex {
    if (location.startsWith('/tasks')) return 1;
    if (location.startsWith('/reports')) return 2;
    if (location.startsWith('/more')) return 3;
    return 0;
  }

  String get title {
    switch (selectedIndex) {
      case 1:
        return 'المهام';
      case 2:
        return 'التقارير';
      case 3:
        return 'المزيد';
      default:
        return 'الرئيسية';
    }
  }

  @override
  Widget build(BuildContext context) {
    const destinations = <String>['/', '/tasks', '/reports', '/more'];
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'التنبيهات',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('سيتم ربط التنبيهات ببيانات Supabase قريبًا.'),
              ),
            ),
            icon: const Icon(Icons.notifications_none_outlined),
          ),
        ],
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(destinations[index]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            label: 'المهام',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            label: 'التقارير',
          ),
          NavigationDestination(icon: Icon(Icons.menu), label: 'المزيد'),
        ],
      ),
    );
  }
}
