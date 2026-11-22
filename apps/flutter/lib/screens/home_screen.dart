import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, dynamic>?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>?> _loadProfile() async {
    final result = await Supabase.instance.client.rpc('mobile_my_profile');
    if (result is! Map) return null;
    final employee = result['employee'];
    if (employee is! Map) return null;
    return Map<String, dynamic>.from(employee);
  }

  String _roleLabel(dynamic roles) {
    if (roles is! List) return 'موظف';
    final codes = roles.whereType<Map>().map((role) => role['code']).whereType<String>().toSet();
    if (codes.contains('owner')) return 'صاحب المؤسسة';
    if (codes.contains('admin_followup')) return 'مسؤول المتابعة الإدارية والتنفيذية';
    if (codes.contains('accountant')) return 'محاسب';
    if (codes.contains('warehouse_keeper')) return 'أمين مخزن';
    if (codes.contains('warehouse_worker')) return 'عامل تحميل';
    return 'موظف';
  }

  Future<void> _signOut() async => Supabase.instance.client.auth.signOut();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الشاعري الإداري', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(tooltip: 'تسجيل الخروج', onPressed: _signOut, icon: const Icon(Icons.logout)),
          ],
        ),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person_off_outlined, size: 44),
                    const SizedBox(height: 12),
                    const Text('تعذر تحميل ملف الموظف', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('تحقق من صلاحيات الحساب واتصال الشبكة.', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => setState(() => _profileFuture = _loadProfile()),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ]),
                ),
              );
            }

            final profile = snapshot.data!;
            final name = profile['fullName'] as String? ?? 'الموظف';
            final employeeNo = profile['employeeNo']?.toString() ?? '—';
            final role = _roleLabel(profile['roles']);
            final roleCodes = (profile['roles'] as List? ?? [])
                .whereType<Map>()
                .map((entry) => entry['code'])
                .whereType<String>()
                .toSet();
            final permissions = (profile['permissions'] as List? ?? []).map((e) => e.toString()).toSet();
            final canDesignTasks = permissions.contains('task_library.manage') &&
                (permissions.contains('tasks.manage') || permissions.contains('tasks.read_all'));
            final canApproveTaskPublication = roleCodes.contains('owner');

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppTheme.navy,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('مرحباً بك', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text('رقم الموظف: $employeeNo', style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 5),
                    Text(role, style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
                const SizedBox(height: 20),
                const Text('مساحة العمل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _ModuleAction(
                  icon: Icons.assignment_outlined,
                  title: 'المهام والتقارير',
                  description: 'عرض المهام المسندة إليك وفتح نماذج التقرير والجداول كما صممتها الإدارة.',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TasksScreen(profile: profile),
                  )),
                ),
                if (canDesignTasks) ...[
                  const SizedBox(height: 10),
                  _ModuleAction(
                    icon: Icons.dashboard_customize_outlined,
                    title: 'مصمم المهام',
                    description: 'إنشاء نموذج تقرير ديناميكي وإرساله كمسودة لاعتماد صاحب المؤسسة.',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TaskDesignerScreen(profile: profile),
                    )),
                  ),
                ],
                if (canApproveTaskPublication) ...[
                  const SizedBox(height: 10),
                  _ModuleAction(
                    icon: Icons.fact_check_outlined,
                    title: 'اعتماد ونشر المهام',
                    description: 'مراجعة نماذج التقارير واعتمادها قبل ربطها بالمهام.',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TaskPublicationReviewScreen(profile: profile),
                    )),
                  ),
                ],
                const SizedBox(height: 10),
                const _ModuleNotice(
                  icon: Icons.account_tree_outlined,
                  title: 'صلاحيات المؤسسة',
                  description: 'تُقرأ الصلاحيات من ملف الموظف في Supabase، وتُفرض أيضاً من قاعدة البيانات.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ModuleAction extends StatelessWidget {
  const _ModuleAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: CircleAvatar(
        backgroundColor: AppTheme.teal.withValues(alpha: 0.12),
        child: Icon(icon, color: AppTheme.teal),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(description)),
      trailing: const Icon(Icons.chevron_left),
      onTap: onTap,
    ),
  );
}

class _ModuleNotice extends StatelessWidget {
  const _ModuleNotice({required this.icon, required this.title, required this.description});
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: CircleAvatar(
        backgroundColor: AppTheme.teal.withValues(alpha: 0.12),
        child: Icon(icon, color: AppTheme.teal),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(description)),
    ),
  );
}
