import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _name;
  String? _error;
  Map<String, int>? _summary;
  Set<String> _permissions = {};
  Set<String> _roles = {};
  int _request = 0;

  static const _groups = <(String, List<_Module>)>[
    (
      'العمل والمتابعة',
      [
        _Module(
          'tasks',
          'إدارة المهام',
          'إنشاء ومتابعة المهام',
          Icons.task_alt,
          '/tasks',
        ),
        _Module(
          'reports',
          'التقارير',
          'تقارير شاملة ومفصلة',
          Icons.assessment_outlined,
          '/reports',
        ),
        _Module(
          'daily-report',
          'التقارير اليومية المصممة',
          'تعبئة النماذج المعتمدة من الإدارة',
          Icons.assignment_outlined,
          '/reports/daily',
        ),
        _Module(
          'independent-reports',
          'تقارير الموظف',
          'النماذج المستقلة والمسودات',
          Icons.description_outlined,
          '/reports/independent',
        ),
        _Module(
          'performance',
          'إحصائيات ومقارنة الأداء',
          'ترتيب الموظفين ومقارنة الفروع',
          Icons.query_stats,
          '/admin/performance',
        ),
      ],
    ),
  ];
  static const _metrics = <_Metric>[
    _Metric(
      'all',
      'إجمالي المهام',
      Icons.task_alt,
      Color(0xFFE0ECFF),
      Color(0xFF164C80),
    ),
    _Metric(
      'in_progress',
      'قيد التنفيذ',
      Icons.play_circle_outline,
      Color(0xFFE2F3EE),
      Color(0xFF146B50),
    ),
    _Metric(
      'submitted',
      'بانتظار المراجعة',
      Icons.fact_check_outlined,
      Color(0xFFFFF0DC),
      Color(0xFF915511),
    ),
    _Metric(
      'late',
      'مهام متأخرة',
      Icons.schedule,
      Color(0xFFFFE2E7),
      Color(0xFFAB2B37),
    ),
  ];

  bool get _manageTasks => _permissions.contains('tasks.manage');
  bool get _employeeManager =>
      _roles.any((r) => r == 'owner' || r == 'admin_followup') &&
      _permissions.contains('employees.manage');
  bool get _hasDailyReportRole => _roles.any(
    (r) => const {
      'accountant',
      'warehouse_keeper',
      'warehouse_worker',
      'admin_followup',
      'owner',
    }.contains(r),
  );
  bool _allowed(String key) {
    switch (key) {
      case 'tasks':
        return _manageTasks || _permissions.contains('tasks.execute');
      case 'reports':
        return _manageTasks
            ? (_permissions.contains('reports.read_all') ||
                  _permissions.contains('tasks.review'))
            : _permissions.contains('tasks.execute');
      case 'daily-report':
        return _hasDailyReportRole;
      case 'independent-reports':
        return _permissions.contains('tasks.execute') ||
            _permissions.contains('reports.read_all');
      case 'employees':
        return _employeeManager ||
            (_manageTasks && _permissions.contains('employees.read'));
      case 'branches':
        return _manageTasks &&
            (_permissions.contains('branches.manage') ||
                _permissions.contains('branches.read_all'));
      case 'performance':
        return _manageTasks &&
            (_permissions.contains('tasks.review') ||
                _permissions.contains('reports.read_all'));
      case 'report-designer':
        return _manageTasks && _permissions.contains('report_forms.manage');
      case 'agreements':
        return true;
      case 'hr':
        return _employeeManager &&
            _permissions.contains('employee_hr.read_all');
      case 'permissions':
      case 'settings':
        return _employeeManager;
      default:
        return false;
    }
  }

  String _moduleRoute(_Module item) {
    if (item.key == 'tasks') return _manageTasks ? '/admin/tasks' : '/tasks';
    if (item.key == 'reports' && !_manageTasks) return '/reports/independent';
    return item.route;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ticket = ++_request;
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      if (mounted) context.go('/login');
      return;
    }
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final raw = await client.rpc('mobile_my_profile');
      final root = raw is Map ? raw : const <dynamic, dynamic>{};
      final employee = root['employee'];
      if (employee is! Map)
        throw Exception(
          'الحساب غير مرتبط بملف موظف نشط. تواصل مع مسؤول النظام.',
        );
      final profile = Map<String, dynamic>.from(employee);
      final permissions = profile['permissions'] is List
          ? (profile['permissions'] as List).map((v) => v.toString()).toSet()
          : <String>{};
      final roles = profile['roles'] is List
          ? (profile['roles'] as List)
                .whereType<Map>()
                .map((r) => (r['code'] ?? '').toString())
                .toSet()
          : <String>{};
      final organization =
          (profile['institutionId'] ??
                  profile['institution_id'] ??
                  profile['organization_id'])
              ?.toString();
      final branch = _defaultBranch(profile);
      final name = (profile['fullName'] ?? profile['full_name'] ?? '')
          .toString();
      if (ticket != _request || !mounted) return;
      setState(() {
        _name = name;
        _permissions = permissions;
        _roles = roles;
      });

      final summary = await _loadSummary(
        client,
        organization,
        branch,
        permissions.contains('tasks.manage'),
        permissions.contains('tasks.execute'),
      );
      if (ticket != _request || !mounted) return;
      setState(() {
        _summary = summary;
      });
    } catch (e) {
      if (ticket == _request && mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (ticket == _request && mounted) setState(() => _loading = false);
    }
  }

  String? _defaultBranch(Map<String, dynamic> profile) {
    final value = profile['branches'];
    if (value is! List) return null;
    for (final item in value.whereType<Map>()) {
      if (item['isDefault'] == true || item['is_default'] == true) {
        final id = item['id'];
        if (id != null && id.toString().isNotEmpty) return id.toString();
      }
    }
    return null;
  }

  Future<Map<String, int>> _loadSummary(
    SupabaseClient client,
    String? organization,
    String? branch,
    bool manages,
    bool executes,
  ) async {
    if (!manages && !executes)
      return {'all': 0, 'in_progress': 0, 'submitted': 0, 'late': 0};
    final user = client.auth.currentUser;
    if (user == null) throw Exception('انتهت الجلسة. سجّل الدخول مجددًا.');
    if (organization == null || organization.isEmpty)
      throw Exception('تعذر تحديد المؤسسة المرتبطة بالحساب.');
    const pageSize = 500;
    final tasks = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      var query = client
          .from('tasks')
          .select('id,status,due_at')
          .eq('organization_id', organization);
      if (!manages) query = query.eq('assigned_to', user.id);
      if (branch != null) query = query.eq('branch_id', branch);
      final page = await query.order('id').range(offset, offset + pageSize - 1);
      tasks.addAll(
        (page as List).whereType<Map>().map(
          (row) => Map<String, dynamic>.from(row),
        ),
      );
      if ((page as List).length < pageSize) break;
    }
    final reviewIds = <String>{};
    for (var start = 0; start < tasks.length; start += 200) {
      final ids = tasks
          .skip(start)
          .take(200)
          .map((t) => t['id'].toString())
          .toList();
      for (var offset = 0; ; offset += pageSize) {
        final rows = await client
            .from('task_reports')
            .select('id,task_id')
            .inFilter('task_id', ids)
            .eq('status', 'submitted')
            .order('id')
            .range(offset, offset + pageSize - 1);
        for (final row in (rows as List).whereType<Map>()) {
          if (row['task_id'] != null) reviewIds.add(row['task_id'].toString());
        }
        if ((rows as List).length < pageSize) break;
      }
    }
    final now = DateTime.now().toUtc();
    var active = 0, submitted = 0, late = 0;
    for (final task in tasks) {
      final status = _normalizeStatus((task['status'] ?? '').toString());
      if (status == 'in_progress') active++;
      final id = task['id']?.toString();
      if (status == 'submitted' || (id != null && reviewIds.contains(id)))
        submitted++;
      final due = DateTime.tryParse((task['due_at'] ?? '').toString())?.toUtc();
      if (status == 'late' ||
          (!{'approved', 'cancelled'}.contains(status) &&
              due != null &&
              due.isBefore(now)))
        late++;
    }
    return {
      'all': tasks.length,
      'in_progress': active,
      'submitted': submitted,
      'late': late,
    };
  }

  String _normalizeStatus(String status) =>
      const {
        'new': 'pending',
        'received': 'pending',
        'on_hold': 'in_progress',
        'report_submitted': 'submitted',
        'completed_approved': 'approved',
        'needs_revision': 'rejected',
      }[status] ??
      status;

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'الرئيسية',
    subtitle: _name == null || _name!.isEmpty
        ? 'بوابة العمل والتواصل الإداري'
        : 'مرحبًا ${_name!}',
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 22),
        children: [
          if (_error != null)
            SectionCard(
              title: 'تعذر تحديث الرئيسية',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!, textAlign: TextAlign.right),
                  if (_summary != null)
                    const Text(
                      'الأرقام المعروضة من آخر تحديث ناجح.',
                      textAlign: TextAlign.right,
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              ),
            ),
          if (_loading && _summary == null)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(),
              ),
            _metricGrid(),
            const SizedBox(height: 14),
            _unifiedTaskTableSection(),
            const SizedBox(height: 14),
            for (final group in _groups) _moduleGroup(group.$1, group.$2),
          ],
        ],
      ),
    ),
  );

  Widget _unifiedTaskTableSection() {
    return SectionCard(
      title: 'الجدول الموحد لإنشاء المهام',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _manageTasks ? () => context.push('/admin/unified-tasks') : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              const Icon(Icons.table_chart_outlined, color: AppColors.green, size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'افتح الجدول الموحد لإنشاء المهام وإرسالها للموظف',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Row(
        textDirection: TextDirection.rtl,
        children: [
          for (var i = 0; i < _metrics.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(child: _metricCard(_metrics[i], width < 370)),
          ],
        ],
      );
    },
  );

  Widget _metricCard(_Metric item, bool compact) => Material(
    color: item.background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: BorderSide(color: item.foreground.withOpacity(0.15)),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: _allowed('tasks') ? () => context.go('/tasks') : null,
      child: SizedBox(
        height: compact ? 116 : 126,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, color: item.foreground, size: compact ? 25 : 29),
              Text(
                _summary?[item.key]?.toString() ?? '—',
                style: TextStyle(
                  fontSize: compact ? 25 : 29,
                  fontWeight: FontWeight.w900,
                  color: item.foreground,
                ),
              ),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 10 : 12,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: item.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _moduleGroup(String title, List<_Module> modules) {
    final visible = modules.where((item) => _allowed(item.key)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final columns = constraints.maxWidth >= 560 ? 3 : 2;
              final cardWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                textDirection: TextDirection.rtl,
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in visible)
                    SizedBox(width: cardWidth, child: _moduleCard(item)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _moduleCard(_Module item) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.go(_moduleRoute(item)),
      child: SizedBox(
        height: 86,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(item.icon, size: 30, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.key == 'tasks' && _manageTasks
                          ? 'إدارة المهام'
                          : item.title,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF4E596C),
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Module {
  const _Module(this.key, this.title, this.subtitle, this.icon, this.route);
  final String key, title, subtitle, route;
  final IconData icon;
}

class _Metric {
  const _Metric(
    this.key,
    this.title,
    this.icon,
    this.background,
    this.foreground,
  );
  final String key, title;
  final IconData icon;
  final Color background, foreground;
}
