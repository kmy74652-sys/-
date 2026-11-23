import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import 'unified_task_table_editor.dart';

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
  String? _organizationId;
  String? _defaultBranchId;
  List<UnifiedEmployeeOption> _unifiedEmployees = const [];
  List<String> _unifiedBranches = const [];
  List<UnifiedReportOption> _unifiedReports = const [];
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
          'التقرير اليومي',
          'إرسال تقرير دورك للإدارة',
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
    (
      'الموظفون والفروع',
      [
        _Module(
          'employees',
          'إدارة الموظفين',
          'بيانات الموظفين والحسابات',
          Icons.people_outline,
          '/settings',
        ),
        _Module(
          'branches',
          'إدارة الفروع',
          'إضافة وتعديل الفروع',
          Icons.account_tree_outlined,
          '/admin',
        ),
      ],
    ),
    (
      'أدوات الإعداد',
      [
        _Module(
          'task-designer',
          'مصمم المهام',
          'تصميم مهام دورية ومخصصة',
          Icons.design_services_outlined,
          '/admin/task-designer',
        ),
        _Module(
          'report-designer',
          'مصمم التقارير',
          'إنشاء تقارير ديناميكية',
          Icons.edit_note,
          '/admin/report-designer',
        ),
      ],
    ),
    (
      'الموارد والإعدادات',
      [
        _Module(
          'agreements',
          'اتفاقية العمل والموارد البشرية',
          'الاتفاقيات والعقود والدوام والرواتب',
          Icons.description_outlined,
          '/agreement',
        ),
        _Module(
          'permissions',
          'الصلاحيات',
          'إدارة صلاحيات المستخدمين',
          Icons.admin_panel_settings_outlined,
          '/settings',
        ),
        _Module(
          'settings',
          'الإعدادات',
          'إعدادات الحساب',
          Icons.settings_outlined,
          '/settings',
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
      case 'task-designer':
        return _manageTasks && _permissions.contains('task_library.manage');
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
        _organizationId = organization;
        _defaultBranchId = branch;
      });

      if (organization != null) await _loadUnifiedOptions(organization);
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

  Future<void> _loadUnifiedOptions(String organizationId) async {
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        client.from('organization_memberships').select('user_id,display_name').eq('organization_id', organizationId).eq('is_active', true).order('display_name').limit(500),
        client.from('branches').select('name').eq('organization_id', organizationId).eq('is_active', true).order('name').limit(200),
        client.from('report_form_templates').select('id,title,role_code').eq('organization_id', organizationId).eq('is_active', true).order('title').limit(200),
        client.from('report_form_versions').select('id,template_id,status,approved_by,approved_at,report_required').eq('status', 'published').limit(500),
      ]);
      if (!mounted) return;
      final employees = (results[0] as List).whereType<Map>().map((row) => UnifiedEmployeeOption(name: (row['display_name'] ?? '').toString(), userId: (row['user_id'] ?? '').toString())).where((item) => item.name.isNotEmpty && item.userId.isNotEmpty).toList();
      setState(() {
        _unifiedEmployees = [const UnifiedEmployeeOption(name: 'مهام مشتركة', userId: ''), ...employees];
        _unifiedBranches = (results[1] as List).whereType<Map>().map((row) => (row['name'] ?? '').toString()).where((name) => name.isNotEmpty).toList();
        final templates = (results[2] as List).whereType<Map>().toList();
        final versions = (results[3] as List).whereType<Map>().where((row) => row['approved_by'] != null && row['approved_at'] != null).toList();
        _unifiedReports = versions.map((version) {
          final matches = templates.where((row) => row['id']?.toString() == version['template_id']?.toString()).toList();
          final template = matches.isEmpty ? null : matches.first;
          return template == null ? null : UnifiedReportOption(templateId: template['id'].toString(), versionId: version['id'].toString(), title: '${template['title']} · إصدار معتمد');
        }).whereType<UnifiedReportOption>().toList();
      });
    } catch (_) {
      // Manual entry remains available when optional lists are unavailable.
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
    final manager = _allowed('tasks') && _manageTasks;
    if (manager) {
      return UnifiedTaskTableEditor(onSend: _sendUnifiedTable, employees: _unifiedEmployees, branches: _unifiedBranches, reports: _unifiedReports);
    }
    return SectionCard(
      title: 'الجدول الموحد لإنشاء المهام',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              const Icon(Icons.table_chart_outlined, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  manager
                      ? 'أنشئ المهام وفق جدول رسمي منظم، ثم أرسلها للموظف مع التقرير المطلوب.'
                      : 'جدولك اليومي ومخرجات المهام والتقرير المطلوب تظهر هنا بنفس الترتيب الرسمي.',
                  textAlign: TextAlign.right,
                  style: const TextStyle(height: 1.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _officialTablePreview(),
          const SizedBox(height: 12),
          if (manager) ...[
            const Text('قوالب سريعة', textAlign: TextAlign.right, style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Wrap(
              textDirection: TextDirection.rtl,
              spacing: 7,
              runSpacing: 7,
              children: [
                _tableAction('محاسب', Icons.calculate_outlined, '/admin/task-designer'),
                _tableAction('أمين مخزن', Icons.inventory_2_outlined, '/admin/task-designer'),
                _tableAction('تحميل وترتيب', Icons.local_shipping_outlined, '/admin/task-designer'),
                _tableAction('مهام مشتركة', Icons.groups_outlined, '/tasks'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(child: FilledButton.icon(onPressed: () => context.go('/tasks'), icon: const Icon(Icons.add_task), label: const Text('إنشاء مهمة وإرسالها'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: () => context.go('/admin/task-designer'), icon: const Icon(Icons.view_list_outlined), label: const Text('إدارة القوالب'))),
              ],
            ),
          ] else
            FilledButton.icon(
              onPressed: _allowed('tasks') ? () => context.go('/tasks') : null,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('فتح جدول مهامي والتقرير اليومي'),
            ),
        ],
      ),
    );
  }

  Widget _tableAction(String label, IconData icon, String route) => ActionChip(
    avatar: Icon(icon, size: 18, color: AppColors.green),
    label: Text(label),
    onPressed: () => context.go(route),
  );

  Future<void> _sendUnifiedTable(UnifiedTaskTableDraft draft) async {
    final organizationId = _organizationId;
    if (organizationId == null || organizationId.isEmpty) {
      throw Exception('تعذر تحديد المؤسسة المرتبطة بالحساب.');
    }
    final client = Supabase.instance.client;
    final members = (await client
            .from('organization_memberships')
            .select('user_id,display_name,is_active')
            .eq('organization_id', organizationId)
            .eq('is_active', true)
            .limit(500) as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final requested = draft.employee.trim();
    final selected = requested == 'مهام مشتركة'
        ? members
        : members.where((row) => (row['display_name'] ?? '').toString().trim() == requested).toList();
    if (selected.isEmpty) throw Exception('لم يتم العثور على موظف مطابق. اكتب الاسم كما يظهر في النظام أو اختر «مهام مشتركة».');
    final roleMap = <String, String>{
      'صاحب المؤسسة': 'owner',
      'المدير التنفيذي': 'admin_followup',
      'المحاسب': 'accountant',
      'أمين المخزن': 'warehouse_keeper',
      'أمين مخزن': 'warehouse_keeper',
      'عمال التحميل': 'warehouse_worker',
      'عامل تحميل': 'warehouse_worker',
    };
    final roleCode = roleMap[draft.role.trim()] ?? draft.role.trim();
    const validRoles = {'owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'};
    if (!validRoles.contains(roleCode)) throw Exception('المسمى الوظيفي غير معروف. استخدم المسمى العربي المعتمد.');
    var branchId = _defaultBranchId;
    if (draft.branch.trim().isNotEmpty) {
      final branches = (await client.from('branches').select('id,name').eq('organization_id', organizationId).eq('is_active', true).limit(200) as List).whereType<Map>();
      for (final row in branches) {
        if ((row['name'] ?? '').toString().trim() == draft.branch.trim()) branchId = row['id']?.toString();
      }
    }
    final due = DateTime.tryParse(draft.startDate)?.toUtc() ?? DateTime.now().toUtc().add(const Duration(days: 1));
    for (final member in selected) {
      final userId = member['user_id']?.toString();
      if (userId == null || userId.isEmpty) continue;
      for (final row in draft.rows) {
        final description = [
          if (draft.purpose.isNotEmpty) 'الهدف من الوظيفة: ${draft.purpose}',
          'الوقت المحدد: ${row.time.isEmpty ? 'غير محدد' : row.time}',
          if (row.output.isNotEmpty) 'المخرج المطلوب: ${row.output}',
          if (draft.dailyReport.isNotEmpty) 'التقرير اليومي المطلوب: ${draft.dailyReport}',
          if (draft.responsibilities.isNotEmpty) 'المسؤوليات: ${draft.responsibilities.join('، ')}',
          if (draft.authorities.isNotEmpty) 'الصلاحيات: ${draft.authorities.join('، ')}',
          if (draft.instructions.isNotEmpty) 'التعليمات: ${draft.instructions.join('، ')}',
        ].join('\n');
        await client.rpc('create_task_with_report_form', params: {
          'p_organization_id': organizationId,
          'p_title': row.task,
          'p_description': description,
          'p_due_at': due.toIso8601String(),
          'p_priority': 'normal',
          'p_branch_id': branchId,
          'p_role_code': roleCode,
          'p_template_id': null,
          'p_assigned_to': userId,
          'p_report_template_id': draft.reportTemplateId,
          'p_report_version_id': draft.reportVersionId,
          'p_report_required': draft.reportTemplateId != null && draft.reportVersionId != null,
        });
      }
    }
    await _load();
  }

  Widget _officialTablePreview() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF8FBFA),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFD8E4E0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          color: const Color(0xFFEAF4F0),
          child: const Text('مؤسسة الشاعري للتجارة العامة · جدول تنفيذ المهام', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: const WidgetStatePropertyAll(Color(0xFFF0F5F3)),
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('الوقت')),
              DataColumn(label: Text('المهمة والمسؤولية')),
              DataColumn(label: Text('المخرج المطلوب')),
              DataColumn(label: Text('الحالة')),
            ],
            rows: const [
              DataRow(cells: [DataCell(Text('08:00')), DataCell(Text('يُحدد من قالب الموظف')), DataCell(Text('نتيجة قابلة للمراجعة')), DataCell(Text('جديدة'))]),
              DataRow(cells: [DataCell(Text('—')), DataCell(Text('أضف بندًا من شاشة إنشاء المهمة')), DataCell(Text('تقرير يومي')), DataCell(Text('بانتظار الإرسال'))]),
            ],
          ),
        ),
      ],
    ),
  );

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
      onTap: () => context.go(item.route),
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
                      item.title,
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
