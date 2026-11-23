import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_shell.dart';
import '../../shared/app_customizer.dart';
import 'unified_task_table_editor.dart';

class UnifiedTaskTableScreen extends StatefulWidget {
  const UnifiedTaskTableScreen({super.key});

  @override
  State<UnifiedTaskTableScreen> createState() => _UnifiedTaskTableScreenState();
}

class _UnifiedTaskTableScreenState extends State<UnifiedTaskTableScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  String? _organizationId;
  String? _defaultBranchId;
  List<UnifiedEmployeeOption> _employees = const [];
  List<UnifiedBranchOption> _branches = const [];
  List<UnifiedReportOption> _reports = const [];
  List<Map<String, dynamic>> _sentTasks = const [];
  bool _sentLoading = false;
  bool _sentMutationBusy = false;
  final Set<String> _successfulDispatches = <String>{};

  @override
  void initState() {
    super.initState();
    AppCustomizer.instance.load();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _db.rpc('mobile_my_profile');
      final employee = raw is Map ? raw['employee'] : null;
      if (employee is! Map) throw Exception('تعذر تحديد الحساب الحالي.');
      final profile = Map<String, dynamic>.from(employee);
      final organization = (profile['institutionId'] ??
              profile['institution_id'] ??
              profile['organization_id'])
          ?.toString();
      if (organization == null || organization.isEmpty) {
        throw Exception('تعذر تحديد المؤسسة المرتبطة بالحساب.');
      }
      final permissions = profile['permissions'];
      final allowed = permissions is List && permissions.map((e) => e.toString()).any(
            (permission) => permission == 'tasks.manage' || permission == 'tasks.review',
          );
      if (!allowed) throw Exception('هذا القسم متاح لصلاحيات إدارة المهام فقط.');
      _organizationId = organization;
      _defaultBranchId = _defaultBranch(profile);
      final results = await Future.wait<dynamic>([
        _db
            .from('organization_memberships')
            .select('user_id,display_name')
            .eq('organization_id', organization)
            .eq('is_active', true)
            .order('display_name')
            .limit(500),
        _db
            .from('branches')
            .select('id,name')
            .eq('organization_id', organization)
            .eq('is_active', true)
            .order('name')
            .limit(200),
        _db
            .from('report_form_templates')
            .select('id,title,role_code')
            .eq('organization_id', organization)
            .eq('is_active', true)
            .order('title')
            .limit(200),
        _db
            .from('report_form_versions')
            .select('id,template_id,status,version_no,approved_by,approved_at')
            .eq('status', 'published')
            .limit(500),
        _db
            .from('report_form_version_fields')
            .select('version_id,is_required')
            .limit(2000),
      ]);
      final employees = (results[0] as List)
          .whereType<Map>()
          .map((row) => UnifiedEmployeeOption(
                name: (row['display_name'] ?? '').toString(),
                userId: (row['user_id'] ?? '').toString(),
              ))
          .where((item) => item.name.isNotEmpty && item.userId.isNotEmpty)
          .toList();
      final templates = (results[2] as List).whereType<Map>().toList();
      final versions = (results[3] as List)
          .whereType<Map>()
          .where((row) => row['approved_by'] != null && row['approved_at'] != null)
          .toList();
      final fieldsByVersion = <String, List<Map<String, dynamic>>>{};
      for (final row in (results[4] as List).whereType<Map>()) {
        final id = row['version_id']?.toString();
        if (id == null || id.isEmpty) continue;
        fieldsByVersion
            .putIfAbsent(id, () => <Map<String, dynamic>>[])
            .add(Map<String, dynamic>.from(row));
      }
      final latestByTemplate = <String, Map<String, dynamic>>{};
      for (final version in versions) {
        final templateId = version['template_id']?.toString();
        if (templateId == null) continue;
        final current = latestByTemplate[templateId];
        final number = int.tryParse('${version['version_no'] ?? 0}') ?? 0;
        final currentNumber = int.tryParse('${current?['version_no'] ?? 0}') ?? 0;
        if (current == null || number > currentNumber) {
          latestByTemplate[templateId] = Map<String, dynamic>.from(version);
        }
      }
      final reports = latestByTemplate.values.map((version) {
        final matches = templates
            .where((row) => row['id']?.toString() == version['template_id']?.toString())
            .toList();
        if (matches.isEmpty) return null;
        final template = matches.first;
        final fields = fieldsByVersion[version['id']?.toString()] ?? const [];
        return UnifiedReportOption(
          templateId: template['id'].toString(),
          versionId: version['id'].toString(),
          title: template['title'].toString(),
          roleCode: (template['role_code'] ?? '').toString(),
          versionNumber: '${version['version_no'] ?? '—'}',
          fieldCount: fields.length,
          requiredFieldCount:
              fields.where((field) => field['is_required'] == true).length,
        );
      }).whereType<UnifiedReportOption>().toList();
      if (!mounted) return;
      setState(() {
        _employees = [
          const UnifiedEmployeeOption(name: 'مهام مشتركة', userId: ''),
          ...employees,
        ];
        _branches = (results[1] as List)
            .whereType<Map>()
            .map((row) => UnifiedBranchOption(
                  id: (row['id'] ?? '').toString(),
                  name: (row['name'] ?? '').toString(),
                ))
            .where((branch) => branch.id.isNotEmpty && branch.name.isNotEmpty)
            .toList();
        _reports = reports;
        _loading = false;
      });
      await _loadSentTasks();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadSentTasks() async {
    final organization = _organizationId;
    if (organization == null || organization.isEmpty) return;
    if (mounted) setState(() => _sentLoading = true);
    try {
      final rows = await _db
          .from('tasks')
          .select('id,title,description,due_at,status,assigned_to,branch_id')
          .eq('organization_id', organization)
          .isFilter('deleted_at', null)
          .order('due_at')
          .limit(1000);
      final sent = (rows as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => '${row['description'] ?? ''}'.contains('الوقت المحدد:'))
          .toList();
      if (mounted) setState(() => _sentTasks = sent);
    } finally {
      if (mounted) setState(() => _sentLoading = false);
    }
  }

  Future<void> _editSentTask(Map<String, dynamic> task) async {
    if (_sentMutationBusy) return;
    final title = TextEditingController(text: '${task['title'] ?? ''}');
    final description = TextEditingController(text: '${task['description'] ?? ''}');
    final due = TextEditingController(text: '${task['due_at'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل صف الجدول الموحد', textAlign: TextAlign.right),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: 'المهمة')),
            TextField(controller: description, textAlign: TextAlign.right, maxLines: 6, decoration: const InputDecoration(labelText: 'بيانات الصف والمخرج والملاحظات')),
            TextField(controller: due, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: 'الموعد بصيغة ISO')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _sentMutationBusy = true);
      try {
        await _db.rpc('admin_update_task', params: {
          'p_organization_id': _organizationId,
          'p_task_id': task['id'],
          'p_title': title.text.trim(),
          'p_description': description.text.trim(),
          'p_due_at': due.text.trim().isEmpty ? null : due.text.trim(),
        });
        await _loadSentTasks();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تعديل الجدول الموحد.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
      } finally {
        if (mounted) setState(() => _sentMutationBusy = false);
      }
    }
    title.dispose();
    description.dispose();
    due.dispose();
  }

  Future<void> _deleteSentTask(Map<String, dynamic> task) async {
    if (_sentMutationBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف صف الجدول الموحد؟', textAlign: TextAlign.right),
        content: Text('سيتم حذف «${task['title'] ?? 'المهمة'}» من الجدول الموحد.', textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sentMutationBusy = true);
    try {
      await _db.rpc('admin_delete_task', params: {'p_organization_id': _organizationId, 'p_task_id': task['id']});
      await _loadSentTasks();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحذف: $e')));
    } finally {
      if (mounted) setState(() => _sentMutationBusy = false);
    }
  }

  List<Map<String, dynamic>> _tableRowsForTask(Map<String, dynamic> task) {
    final description = '${task['description'] ?? ''}';
    final rows = <Map<String, dynamic>>[];
    final pattern = RegExp(r'(?m)^صف الجدول:\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*$');
    for (final match in pattern.allMatches(description)) {
      rows.add({
        'task': task,
        'time': match.group(1)?.trim() ?? 'غير محدد',
        'title': match.group(2)?.trim() ?? '—',
        'output': match.group(3)?.trim() ?? '—',
      });
    }
    if (rows.isEmpty) {
      final time = RegExp(r'الوقت المحدد:\s*(.*)').firstMatch(description)?.group(1);
      final output = RegExp(r'المخرج المطلوب:\s*(.*)').firstMatch(description)?.group(1);
      rows.add({
        'task': task,
        'time': time?.trim().isNotEmpty == true ? time!.trim() : 'غير محدد',
        'title': '${task['title'] ?? 'مهمة'}',
        'output': output?.trim().isNotEmpty == true ? output!.trim() : '—',
      });
    }
    return rows;
  }

  Widget _sentTasksSection() {
    final customizer = AppCustomizer.instance;
    if (customizer.postSendVisibility == 'employee') return const SizedBox.shrink();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final task in _sentTasks) {
      final key = '${task['assigned_to'] ?? ''}|${task['due_at'] ?? ''}';
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(task);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${customizer.unifiedLabel('sent')} (${groups.length})',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 8),
            if (_sentLoading)
              const Center(child: CircularProgressIndicator())
            else if (_sentTasks.isEmpty)
              const Text('لا توجد جداول موحدة مرسلة.', textAlign: TextAlign.right)
            else
              for (final group in groups.values) ...[
                if (group.first != groups.values.first) const Divider(height: 24),
                Text(
                  'جدول موحد · ${group.expand(_tableRowsForTask).length} صف',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${group.first['status'] ?? 'جديدة'} · ${group.first['due_at'] ?? 'غير محدد'}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      ..._sentColumnOrder.map((key) => DataColumn(label: Text(customizer.unifiedLabel(key)))),
                      const DataColumn(label: Text('إجراء')),
                    ],
                    rows: group
                        .expand(_tableRowsForTask)
                        .map(
                          (row) => DataRow(cells: [
                            ..._sentColumnOrder.map((key) => DataCell(Text(_sentValue(row, key), textAlign: _sentTextAlign(key)))),
                            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                              if (customizer.postSendShowActions) ...[
                                IconButton(
                                  onPressed: _sentMutationBusy ? null : () => _editSentTask(row['task'] as Map<String, dynamic>),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  onPressed: _sentMutationBusy ? null : () => _deleteSentTask(row['task'] as Map<String, dynamic>),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                ),
                              ],
                            ])),
                          ]),
                        )
                        .toList(),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  List<String> get _sentColumnOrder {
    final keys = ['time', 'task', 'output'];
    keys.sort((a, b) {
      final la = AppCustomizer.instance.unifiedFieldLayout(a);
      final lb = AppCustomizer.instance.unifiedFieldLayout(b);
      final row = ((la['row'] as num?)?.toInt() ?? 0).compareTo((lb['row'] as num?)?.toInt() ?? 0);
      return row != 0 ? row : ((la['column'] as num?)?.toInt() ?? 0).compareTo((lb['column'] as num?)?.toInt() ?? 0);
    });
    return keys.where(AppCustomizer.instance.isUnifiedFieldVisible).toList();
  }

  String _sentValue(Map<String, dynamic> row, String key) => key == 'time' ? '${row['time']}' : key == 'task' ? '${row['title']}' : '${row['output']}';
  TextAlign _sentTextAlign(String key) {
    final align = '${AppCustomizer.instance.unifiedFieldLayout(key)['align'] ?? 'right'}';
    return align == 'left' ? TextAlign.left : align == 'center' ? TextAlign.center : TextAlign.right;
  }

  String? _defaultBranch(Map<String, dynamic> profile) {
    final branches = profile['branches'];
    if (branches is! List) return null;
    for (final item in branches.whereType<Map>()) {
      if (item['isDefault'] == true || item['is_default'] == true) {
        final id = item['id'];
        if (id != null && id.toString().isNotEmpty) return id.toString();
      }
    }
    return null;
  }

  Future<void> _send(UnifiedTaskTableDraft draft) async {
    final organizationId = _organizationId;
    if (organizationId == null || organizationId.isEmpty) {
      throw Exception('تعذر تحديد المؤسسة المرتبطة بالحساب.');
    }
    final members = (await _db
            .from('organization_memberships')
            .select('user_id,display_name')
            .eq('organization_id', organizationId)
            .eq('is_active', true)
            .limit(500) as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final selected = draft.employeeUserId.isEmpty
        ? members
        : members.where((row) => row['user_id']?.toString() == draft.employeeUserId).toList();
    if (selected.isEmpty) throw Exception('لم يتم العثور على الموظف المحدد.');
    const roleMap = <String, String>{
      'صاحب المؤسسة': 'owner',
      'المدير التنفيذي': 'admin_followup',
      'المحاسب': 'accountant',
      'أمين المخزن': 'warehouse_keeper',
      'أمين مخزن': 'warehouse_keeper',
      'عمال التحميل': 'warehouse_worker',
      'عامل تحميل': 'warehouse_worker',
    };
    final roleCode = roleMap[draft.role.trim()] ?? draft.role.trim();
    const validRoles = {
      'owner',
      'admin_followup',
      'accountant',
      'warehouse_keeper',
      'warehouse_worker',
    };
    if (!validRoles.contains(roleCode)) {
      throw Exception('المسمى الوظيفي غير معروف.');
    }
    final branchId = draft.branchId ?? _defaultBranchId;
    final due = DateTime.tryParse(draft.startDate)?.toUtc() ??
        DateTime.now().toUtc().add(const Duration(days: 1));
    for (final member in selected) {
      final userId = member['user_id']?.toString();
      if (userId == null || userId.isEmpty) continue;
      final dispatchKey = '${userId}:${draft.role}:${draft.rows.map((row) => '${row.time}|${row.task}|${row.output}').join('§')}';
      if (_successfulDispatches.contains(dispatchKey)) continue;
      final description = [
        'الجدول الموحد: ${draft.role}',
        'المسمى الوظيفي: ${draft.role}',
        if (draft.branch.isNotEmpty) 'الفرع: ${draft.branch}',
        if (draft.startDate.isNotEmpty)
          'تاريخ بدء التطبيق: ${draft.startDate}',
        'ساعات الدوام: ${draft.workType} · ${draft.workDays} · الفترة الأولى: ${draft.firstPeriod.isEmpty ? '—' : draft.firstPeriod} · الاستراحة: ${draft.breakPeriod.isEmpty ? '—' : draft.breakPeriod} · الفترة الثانية: ${draft.secondPeriod.isEmpty ? '—' : draft.secondPeriod} · الاستثناء الأسبوعي: ${draft.weeklyException}',
        if (draft.purpose.isNotEmpty) 'الهدف من الوظيفة: ${draft.purpose}',
        'الوقت المحدد: ${draft.rows.first.time.isEmpty ? 'غير محدد' : draft.rows.first.time}',
        for (final row in draft.rows)
          'صف الجدول: ${row.time.isEmpty ? 'غير محدد' : row.time} | ${row.task} | ${row.output.isEmpty ? '—' : row.output}',
        if (draft.reportNotes.isNotEmpty)
          'ملاحظات وتعليمات إضافية: ${draft.reportNotes}',
        if (draft.responsibilities.isNotEmpty)
          'المسؤوليات: ${draft.responsibilities.join('، ')}',
        if (draft.authorities.isNotEmpty)
          'الصلاحيات: ${draft.authorities.join('، ')}',
        if (draft.instructions.isNotEmpty)
          'التعليمات: ${draft.instructions.join('، ')}',
        if (draft.kpis.isNotEmpty)
          'مؤشرات الأداء: ${draft.kpis.join('؛ ')}',
      ].join('\n');
      await _db.rpc('create_task_with_report_form', params: {
        'p_organization_id': organizationId,
        'p_title': 'الجدول الموحد - ${draft.role}',
        'p_description': description,
        'p_due_at': due.toIso8601String(),
        'p_priority': 'normal',
        'p_branch_id': branchId,
        'p_role_code': roleCode,
        'p_template_id': null,
        'p_assigned_to': userId,
        'p_report_template_id': draft.reportTemplateId,
        'p_report_version_id': draft.reportVersionId,
        'p_report_required':
            draft.reportTemplateId != null && draft.reportVersionId != null,
      });
      _successfulDispatches.add(dispatchKey);
    }
  }

  @override
  Widget build(BuildContext context) => AppShell(
        title: 'الجدول الموحد لإنشاء المهام',
        subtitle: 'إنشاء منظم وإرسال مباشر للموظف',
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.right),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _loadOptions,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (AppCustomizer.instance.postSendPlacement == 'top') _sentTasksSection(),
                      if (AppCustomizer.instance.postSendPlacement == 'top') const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('العودة إلى الرئيسية'),
                        ),
                      ),
                      UnifiedTaskTableEditor(
                        onSend: _send,
                        employees: _employees,
                        branches: _branches,
                        reports: _reports,
                      ),
                      if (AppCustomizer.instance.postSendPlacement == 'bottom') const SizedBox(height: 12),
                      if (AppCustomizer.instance.postSendPlacement == 'bottom') _sentTasksSection(),
                    ],
                  ),
      );
}
