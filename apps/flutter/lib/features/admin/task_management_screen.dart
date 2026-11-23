import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_shell.dart';
import '../../shared/form_widgets.dart';

class TaskManagementScreen extends StatefulWidget {
  const TaskManagementScreen({super.key});
  @override
  State<TaskManagementScreen> createState() => _TaskManagementScreenState();
}

class _TaskManagementScreenState extends State<TaskManagementScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true, _busy = false;
  String? _error;
  String? _orgId;
  List<Map<String, dynamic>> _tasks = [],
      _branches = [],
      _employees = [],
      _templates = [],
      _reportTemplates = [],
      _requests = [];
  Map<String, Map<String, dynamic>> _reportByTask = {};
  Map<String, Map<String, dynamic>> _draftByTask = {};
  String _taskFilter = 'all', _reportFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : <Map<String, dynamic>>[];
  String _s(dynamic v, [String fallback = '']) =>
      v == null ? fallback : v.toString();

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final profile = await _db.rpc('mobile_my_profile');
      final employee = profile is Map ? profile['employee'] : null;
      final org = employee is Map
          ? _s(
              employee['institutionId'] ??
                  employee['institution_id'] ??
                  employee['organization_id'],
            )
          : '';
      if (org.isEmpty) throw Exception('تعذر تحديد المؤسسة الحالية.');
      final results = await Future.wait<dynamic>([
        _db
            .from('tasks')
            .select(
              'id,title,description,branch_id,assigned_to,due_at,priority,status,report_required,report_flow,deleted_at',
            )
            .eq('organization_id', org)
            .isFilter('deleted_at', null)
            .order('due_at')
            .limit(300),
        _db
            .from('branches')
            .select('id,name,code')
            .eq('organization_id', org)
            .eq('is_active', true)
            .order('name')
            .limit(200),
        _db
            .from('organization_memberships')
            .select('id,user_id,display_name,employee_no')
            .eq('organization_id', org)
            .eq('is_active', true)
            .order('display_name')
            .limit(300),
        _db
            .from('task_templates')
            .select('id,title,role_code,is_active,version')
            .eq('organization_id', org)
            .eq('is_active', true)
            .order('title')
            .limit(300),
        _db
            .from('report_form_templates')
            .select('id,title,role_code,is_active')
            .eq('organization_id', org)
            .eq('is_active', true)
            .order('title')
            .limit(200),
        _db
            .from('report_form_versions')
            .select('id,template_id,version_no,status,approved_by,approved_at')
            .eq('status', 'published')
            .filter('approved_by', 'not.is', 'null')
            .filter('approved_at', 'not.is', 'null')
            .order('version_no', ascending: false)
            .limit(500),
        _db
            .from('task_publication_requests')
            .select(
              'id,template_id,template_version,role_code,branch_id,due_at,status,requested_at,review_note,published_count',
            )
            .eq('organization_id', org)
            .eq('status', 'pending_approval')
            .order('requested_at')
            .limit(100),
      ]);
      if (!mounted) return;
      final taskRows = _rows(results[0]);
      final taskIds = taskRows.map((task) => _s(task['id'])).where((id) => id.isNotEmpty).toList();
      final reportRows = taskIds.isEmpty
          ? <Map<String, dynamic>>[]
          : _rows(await _db
                .from('task_reports')
                .select('task_id,status,submitted_at,review_note,updated_at')
                .inFilter('task_id', taskIds)
                .order('updated_at', ascending: false)
                .limit(500));
      final draftRows = taskIds.isEmpty
          ? <Map<String, dynamic>>[]
          : _rows(await _db
                .from('task_report_drafts')
                .select('task_id,updated_at')
                .inFilter('task_id', taskIds)
                .order('updated_at', ascending: false)
                .limit(500));
      final reports = <String, Map<String, dynamic>>{};
      for (final report in reportRows) {
        final taskId = _s(report['task_id']);
        if (taskId.isNotEmpty && !reports.containsKey(taskId)) reports[taskId] = report;
      }
      final drafts = <String, Map<String, dynamic>>{};
      for (final draft in draftRows) {
        final taskId = _s(draft['task_id']);
        if (taskId.isNotEmpty && !drafts.containsKey(taskId)) drafts[taskId] = draft;
      }
      setState(() {
        _orgId = org;
        _tasks = taskRows;
        _reportByTask = reports;
        _draftByTask = drafts;
        _branches = _rows(results[1]);
        _employees = _rows(results[2]);
        _templates = _rows(results[3]);
        final versions = _rows(results[5]);
        _reportTemplates = _rows(results[4]).map((template) {
          final version = versions.firstWhere(
            (v) => _s(v['template_id']) == _s(template['id']),
            orElse: () => <String, dynamic>{},
          );
          return {
            ...template,
            'version_id': version['id'],
            'version_no': version['version_no'],
          };
        }).where((template) => _s(template['version_id']).isNotEmpty).toList();
        _requests = _rows(results[6]);
      });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _employeeName(String? userId) {
    final row = _employees.cast<Map<String, dynamic>?>().firstWhere(
      (e) => _s(e?['user_id']) == userId,
      orElse: () => null,
    );
    return row == null
        ? 'غير محدد'
        : _s(row['display_name'], _s(row['employee_no'], 'موظف'));
  }

  String _branchName(String? id) {
    final row = _branches.cast<Map<String, dynamic>?>().firstWhere(
      (e) => _s(e?['id']) == id,
      orElse: () => null,
    );
    return row == null ? 'كل الفروع' : _s(row['name'], _s(row['code']));
  }

  String _status(String v) =>
      const {
        'new': 'جديدة',
        'pending': 'جديدة',
        'received': 'مستلمة',
        'in_progress': 'قيد التنفيذ',
        'submitted': 'بانتظار المراجعة',
        'report_submitted': 'بانتظار المراجعة',
        'approved': 'معتمدة',
        'completed_approved': 'معتمدة',
        'rejected': 'معادة',
        'needs_revision': 'تحتاج تصحيحًا',
        'cancelled': 'ملغاة',
        'late': 'متأخرة',
      }[v] ??
      v;

  String _reportStatus(Map<String, dynamic> task) {
    final report = _reportByTask[_s(task['id'])];
    final reportStatus = _s(report?['status']);
    if (reportStatus == 'approved') return 'معتمد';
    if (reportStatus == 'submitted') return 'مرسل للمراجعة';
    if (reportStatus == 'returned' || _s(task['status']) == 'needs_revision') return 'يحتاج تعديل';
    if (_draftByTask.containsKey(_s(task['id']))) return 'مسودة';
    if (task['report_required'] == true || task['report_flow'] == 'multi_form') return 'لم يبدأ';
    return 'بدون تقرير';
  }

  Color _reportStatusColor(String value) => const {
    'معتمد': Colors.green,
    'مرسل للمراجعة': Colors.orange,
    'مسودة': Colors.indigo,
    'يحتاج تعديل': Colors.red,
    'لم يبدأ': Colors.blueGrey,
    'بدون تقرير': Colors.grey,
  }[value] ?? Colors.grey;

  Map<String, int> get _reportSummary {
    final summary = <String, int>{};
    for (final task in _tasks) {
      final status = _reportStatus(task);
      summary[status] = (summary[status] ?? 0) + 1;
    }
    return summary;
  }

  List<Map<String, dynamic>> get _visibleTasks => _tasks.where((task) {
    final rawTaskStatus = _s(task['status']);
    final taskMatches = _taskFilter == 'all' ||
        (_taskFilter == 'pending' && ['pending', 'new'].contains(rawTaskStatus)) ||
        (_taskFilter == 'submitted' && ['submitted', 'report_submitted'].contains(rawTaskStatus)) ||
        rawTaskStatus == _taskFilter;
    final reportMatches = _reportFilter == 'all' || _reportStatus(task) == _reportFilter;
    return taskMatches && reportMatches;
  }).toList();

  Widget _filterChip({required String value, required String label, required String group, required VoidCallback onSelected}) =>
      ChoiceChip(
        label: Text(label),
        selected: (group == 'task' ? _taskFilter : _reportFilter) == value,
        onSelected: (_) => setState(onSelected),
      );

  Future<void> _saveTask({Map<String, dynamic>? existing}) async {
    final title = TextEditingController(text: _s(existing?['title']));
    final description = TextEditingController(text: _s(existing?['description']));
    final descriptionCards = <TextEditingController>[description];
    final parsedDue = DateTime.tryParse(_s(existing?['due_at']));
    DateTime dueDate = parsedDue?.toLocal() ?? defaultDueDate();
    String priority = _s(existing?['priority'], 'normal');
    String? branchId = _s(existing?['branch_id']).isEmpty ? null : _s(existing?['branch_id']);
    String? role = 'admin_followup';
    String? assignee = _s(existing?['assigned_to']).isEmpty ? null : _s(existing?['assigned_to']);
    String? templateId;
    String? reportTemplateId;
    String? reportVersionId;
    bool reportRequired = false;
    var validationError = '';

    final ok = await showFormSheet(
      context,
      title: existing == null ? 'إنشاء مهمة جديدة' : 'تعديل بيانات المهمة',
      confirmLabel: existing == null ? 'إنشاء المهمة' : 'حفظ التعديلات',
      builder: (ctx, set) => [
        FormSection(
          title: 'بيانات المهمة',
          icon: Icons.assignment_outlined,
          note: 'اكتب عنوانًا واضحًا يصف النتيجة المطلوبة من الموظف.',
          children: [
            TextField(controller: title, textDirection: TextDirection.rtl, textInputAction: TextInputAction.next, decoration: formDecoration('عنوان المهمة *', hint: 'مثال: مراجعة مخزون الفرع الرئيسي')),
            for (var i = 0; i < descriptionCards.length; i++)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'وصف المهمة ${i + 1}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (descriptionCards.length > 1)
                            IconButton(
                              tooltip: 'حذف حقل الوصف',
                              onPressed: () => set(() {
                                descriptionCards.removeAt(i).dispose();
                              }),
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            ),
                        ],
                      ),
                      TextField(
                        controller: descriptionCards[i],
                        textDirection: TextDirection.rtl,
                        minLines: 2,
                        maxLines: 5,
                        decoration: formDecoration(
                          'محتوى البطاقة',
                          hint: i == 0 ? 'ما المطلوب تنفيذه؟' : 'أضف تفصيلًا أو نتيجة متوقعة أخرى',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => set(() => descriptionCards.add(TextEditingController())),
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('إضافة حقل جديد'),
              ),
            ),
          ],
        ),
        FormSection(
          title: 'الموعد والأولوية',
          icon: Icons.event_available_outlined,
          note: 'يتم حفظ الموعد تلقائيًا بالنظام، ويظهر لك هنا بصيغة عربية سهلة.',
          children: [
            DueDateField(value: dueDate, onChanged: (v) => set(() => dueDate = v)),
            ChoiceChipsField<String>(
              label: 'درجة الأولوية', value: priority,
              options: const [('low', 'منخفضة'), ('normal', 'عادية'), ('high', 'عالية'), ('urgent', 'عاجلة')],
              onChanged: (v) => set(() => priority = v),
            ),
          ],
        ),
        if (existing == null)
          FormSection(
            title: 'التكليف والتنفيذ',
            icon: Icons.person_add_alt_1_outlined,
            note: 'حدد نطاق العمل والدور والموظف المسؤول قبل الإرسال.',
            children: [
              DropdownButtonFormField<String>(
                value: branchId, isExpanded: true,
                decoration: formDecoration('نطاق الفرع', hint: 'كل الفروع أو فرع محدد'),
                items: [const DropdownMenuItem<String>(value: null, child: Text('كل الفروع')), ..._branches.map((b) => DropdownMenuItem(value: _s(b['id']), child: Text(_s(b['name'], _s(b['code'])))))],
                onChanged: (v) => set(() => branchId = v),
              ),
              DropdownButtonFormField<String>(
                value: templateId, isExpanded: true,
                decoration: formDecoration('قالب المهمة', hint: 'اختياري — إنشاء مباشر إذا لم تحدد قالبًا'),
                items: [const DropdownMenuItem<String>(value: null, child: Text('إنشاء مباشر')), ..._templates.map((t) => DropdownMenuItem(value: _s(t['id']), child: Text('${_s(t['title'])} · ${_s(t['role_code'])}')))],
                onChanged: (v) => set(() {
                  templateId = v;
                  reportTemplateId = null;
                  reportVersionId = null;
                  reportRequired = false;
                }),
              ),
              DropdownButtonFormField<String>(
                value: role, isExpanded: true, decoration: formDecoration('الدور الوظيفي'),
                items: const [DropdownMenuItem(value: 'owner', child: Text('صاحب المؤسسة')), DropdownMenuItem(value: 'admin_followup', child: Text('المدير التنفيذي')), DropdownMenuItem(value: 'accountant', child: Text('المحاسب')), DropdownMenuItem(value: 'warehouse_keeper', child: Text('أمين المخازن')), DropdownMenuItem(value: 'warehouse_worker', child: Text('عمال التحميل'))],
                onChanged: (v) => set(() {
                  role = v;
                  if (reportTemplateId != null &&
                      !_reportTemplates.any(
                        (r) => _s(r['id']) == reportTemplateId && _s(r['role_code']) == v,
                      )) {
                    reportTemplateId = null;
                    reportVersionId = null;
                    reportRequired = false;
                  }
                }),
              ),
              DropdownButtonFormField<String>(
                value: assignee, isExpanded: true, decoration: formDecoration('الموظف المسؤول *', hint: 'اختر الموظف المكلف'),
                items: [const DropdownMenuItem<String>(value: null, child: Text('اختر موظفًا')), ..._employees.map((e) => DropdownMenuItem(value: _s(e['user_id']), child: Text(_s(e['display_name'], _s(e['employee_no'])))))],
                onChanged: (v) => set(() => assignee = v),
              ),
              DropdownButtonFormField<String>(
                value: reportTemplateId,
                isExpanded: true,
                decoration: formDecoration(
                  'قالب التقرير',
                  hint: templateId == null
                      ? 'اختياري — يعبئه الموظف بعد تنفيذ المهمة'
                      : 'التقرير يأتي من قالب المهمة المحدد',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('بدون تقرير'),
                  ),
                  ..._reportTemplates
                      .where((r) => _s(r['role_code']) == role)
                      .map(
                        (r) => DropdownMenuItem(
                          value: _s(r['id']),
                          child: Text(
                            '${_s(r['title'])} · الإصدار ${_s(r['version_no'])}',
                          ),
                        ),
                      ),
                ],
                onChanged: templateId != null
                    ? null
                    : (v) => set(() {
                  reportTemplateId = v;
                  final selected = _reportTemplates.cast<Map<String, dynamic>?>().firstWhere(
                    (r) => _s(r?['id']) == v,
                    orElse: () => null,
                  );
                  reportVersionId = selected == null ? null : _s(selected['version_id']);
                  reportRequired = v != null;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إرفاق تقرير عند الإنجاز'),
                subtitle: Text(
                  reportTemplateId == null
                      ? 'اختر قالب تقرير معتمد ليظهر للموظف بعد التنفيذ.'
                      : 'يطلب من الموظف تعبئة التقرير قبل التسليم',
                ),
                value: reportRequired,
                onChanged: reportTemplateId == null
                    ? null
                    : (v) => set(() {
                        reportRequired = v;
                        validationError = '';
                      }),
              ),
            ],
          ),
        if (validationError.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(validationError, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
      ],
      onConfirm: (set) {
        if (title.text.trim().length < 2) { set(() => validationError = 'اكتب عنوان المهمة أولاً.'); return false; }
        if (existing == null && (assignee == null || role == null)) { set(() => validationError = 'اختر الدور والموظف المسؤول قبل إنشاء المهمة.'); return false; }
        if (existing == null && reportRequired && (reportTemplateId == null || reportVersionId == null)) { set(() => validationError = 'اختر قالب تقرير معتمدًا قبل إرسال المهمة.'); return false; }
        return true;
      },
    );
    if (ok != true) {
      title.dispose();
      description.dispose();
      return;
    }

    setState(() => _busy = true);
    try {
      final dueIso = dueToIso(dueDate);
      final descriptionText = descriptionCards
          .asMap()
          .entries
          .where((entry) => entry.value.text.trim().isNotEmpty)
          .map((entry) => 'وصف المهمة ${entry.key + 1}:\n${entry.value.text.trim()}')
          .join('\n\n');
      if (existing != null) {
        await _db.rpc('admin_update_task', params: {'p_organization_id': _orgId, 'p_task_id': existing['id'], 'p_title': title.text.trim(), 'p_description': descriptionText.isEmpty ? null : descriptionText, 'p_due_at': dueIso});
      } else if (templateId != null) {
        await _db.rpc('assign_task_from_template', params: {'p_organization_id': _orgId, 'p_template_id': templateId, 'p_assigned_to': assignee, 'p_branch_id': branchId, 'p_starts_at': DateTime.now().toUtc().toIso8601String(), 'p_due_at': dueIso, 'p_priority': priority, 'p_instructions': descriptionText.isEmpty ? null : descriptionText, 'p_report_overrides': <dynamic>[], 'p_idempotency_key': 'flutter-template:$templateId:$assignee:$dueIso'});
      } else {
        await _db.rpc('create_task_with_report_form', params: {'p_organization_id': _orgId, 'p_title': title.text.trim(), 'p_description': descriptionText.isEmpty ? null : descriptionText, 'p_due_at': dueIso, 'p_priority': priority, 'p_branch_id': branchId, 'p_role_code': role, 'p_template_id': null, 'p_assigned_to': assignee, 'p_report_template_id': reportTemplateId, 'p_report_version_id': reportVersionId, 'p_report_required': reportRequired});
      }
      _message(existing == null ? 'تم إنشاء المهمة وإرسالها للموظف.' : 'تم حفظ تعديلات المهمة.');
      await _load();
    } catch (e) {
      _message('تعذر الحفظ: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      title.dispose();
      for (final card in descriptionCards) {
        card.dispose();
      }
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _publicationRequest() async {
    if (_templates.isEmpty) {
      _message('لا توجد قوالب نشطة للنشر.');
      return;
    }
    String? template = _s(_templates.first['id']);
    String? branch;
    DateTime dueDate = defaultDueDate();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('طلب نشر مهمة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: template,
                isExpanded: true,
                items: _templates
                    .map(
                      (t) => DropdownMenuItem(
                        value: _s(t['id']),
                        child: Text(
                          '${_s(t['title'])} · ${_s(t['role_code'])}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => set(() => template = v),
              ),
              DropdownButtonFormField<String>(
                value: branch,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الفرع (اختياري)'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('كل الفروع'),
                  ),
                  ..._branches.map(
                    (b) => DropdownMenuItem(
                      value: _s(b['id']),
                      child: Text(_s(b['name'])),
                    ),
                  ),
                ],
                onChanged: (v) => set(() => branch = v),
              ),
              DueDateField(
                value: dueDate,
                onChanged: (value) => set(() => dueDate = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إرسال للموافقة'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || template == null) return;
    try {
      await _db.rpc(
        'submit_task_publication_request',
        params: {
          'p_organization_id': _orgId,
          'p_template_id': template,
          'p_branch_id': branch,
          'p_due_at': dueToIso(dueDate),
          'p_idempotency_key':
              'flutter-publication:${template}:${branch ?? 'all'}:${dueToIso(dueDate)}',
        },
      );
      _message('تم إرسال طلب النشر للموافقة.');
      await _load();
    } catch (e) {
      _message('تعذر إرسال طلب النشر: $e');
    }
  }

  Future<void> _review(Map<String, dynamic> row, bool approve) async {
    try {
      final count = await _db.rpc(
        'review_and_publish_task_request',
        params: {
          'p_organization_id': _orgId,
          'p_request_id': row['id'],
          'p_approve': approve,
          'p_review_note': null,
        },
      );
      _message(
        approve ? 'تم اعتماد النشر وإنشاء $count مهمة.' : 'تم رفض طلب النشر.',
      );
      await _load();
    } catch (e) {
      _message('تعذر مراجعة الطلب: $e');
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text, textAlign: TextAlign.right)));
  }

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'إدارة المهام',
    subtitle: 'الإنشاء والتعديل والمتابعة وطلبات النشر',
    child: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (_error != null) Text(_error!, textAlign: TextAlign.right),
                if (_busy) const LinearProgressIndicator(),
                SectionCard(
                  title: 'إجراءات الإدارة',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _saveTask(),
                        icon: const Icon(Icons.add),
                        label: const Text('إنشاء مهمة'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _publicationRequest,
                        icon: const Icon(Icons.publish),
                        label: const Text('طلب نشر قالب'),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'تصفية المتابعة',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('حالة المهمة', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _filterChip(value: 'all', label: 'الكل', group: 'task', onSelected: () => _taskFilter = 'all'),
                          _filterChip(value: 'pending', label: 'جديدة', group: 'task', onSelected: () => _taskFilter = 'pending'),
                          _filterChip(value: 'received', label: 'مستلمة', group: 'task', onSelected: () => _taskFilter = 'received'),
                          _filterChip(value: 'in_progress', label: 'قيد التنفيذ', group: 'task', onSelected: () => _taskFilter = 'in_progress'),
                          _filterChip(value: 'submitted', label: 'للمراجعة', group: 'task', onSelected: () => _taskFilter = 'submitted'),
                          _filterChip(value: 'needs_revision', label: 'تحتاج تصحيحًا', group: 'task', onSelected: () => _taskFilter = 'needs_revision'),
                          _filterChip(value: 'completed_approved', label: 'معتمدة', group: 'task', onSelected: () => _taskFilter = 'completed_approved'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('حالة التقرير', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _filterChip(value: 'all', label: 'الكل', group: 'report', onSelected: () => _reportFilter = 'all'),
                          _filterChip(value: 'لم يبدأ', label: 'لم يبدأ', group: 'report', onSelected: () => _reportFilter = 'لم يبدأ'),
                          _filterChip(value: 'مرسل للمراجعة', label: 'مرسل للمراجعة', group: 'report', onSelected: () => _reportFilter = 'مرسل للمراجعة'),
                          _filterChip(value: 'مسودة', label: 'مسودة', group: 'report', onSelected: () => _reportFilter = 'مسودة'),
                          _filterChip(value: 'يحتاج تعديل', label: 'يحتاج تعديل', group: 'report', onSelected: () => _reportFilter = 'يحتاج تعديل'),
                          _filterChip(value: 'معتمد', label: 'معتمد', group: 'report', onSelected: () => _reportFilter = 'معتمد'),
                          _filterChip(value: 'بدون تقرير', label: 'بدون تقرير', group: 'report', onSelected: () => _reportFilter = 'بدون تقرير'),
                        ],
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'المهام (${_visibleTasks.length} من ${_tasks.length})',
                  child: _visibleTasks.isEmpty
                      ? const Text('لا توجد مهام مطابقة للفلاتر المحددة.', textAlign: TextAlign.right)
                      : Column(
                          children: _visibleTasks
                              .map(
                                (t) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    _s(t['title'], 'مهمة'),
                                    textAlign: TextAlign.right,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${_status(_s(t['status']))} · ${_branchName(_s(t['branch_id']).isEmpty ? null : _s(t['branch_id']))} · ${_employeeName(_s(t['assigned_to']))}',
                                        textAlign: TextAlign.right,
                                      ),
                                      Text(
                                        'التقرير: ${_reportStatus(t)}',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: _reportStatusColor(_reportStatus(t)),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: _reportStatusColor(_reportStatus(t)).withAlpha(31),
                                    child: Icon(
                                      Icons.description_outlined,
                                      color: _reportStatusColor(_reportStatus(t)),
                                    ),
                                  ),
                                  isThreeLine: true,
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (_) => _saveTask(existing: t),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('تعديل'),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _message(
                                    'حالة التقرير: ${_reportStatus(t)}',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
                if (_tasks.isNotEmpty)
                  SectionCard(
                    title: 'متابعة التقارير مباشرة',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: _reportSummary.entries
                          .map(
                            (entry) => Chip(
                              avatar: Icon(
                                entry.key == 'معتمد'
                                    ? Icons.verified_outlined
                                    : entry.key == 'مرسل للمراجعة'
                                    ? Icons.schedule_outlined
                                    : Icons.description_outlined,
                                size: 18,
                                color: _reportStatusColor(entry.key),
                              ),
                              label: Text('${entry.key}: ${entry.value}'),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                if (_requests.isNotEmpty)
                  SectionCard(
                    title: 'طلبات النشر بانتظار موافقة المالك',
                    child: Column(
                      children: _requests
                          .map(
                            (r) => ListTile(
                              title: Text(
                                'قالب ${_s(r['template_id'])}',
                                textAlign: TextAlign.right,
                              ),
                              subtitle: Text(
                                '${_s(r['role_code'])} · ${_branchName(_s(r['branch_id']).isEmpty ? null : _s(r['branch_id']))} · ${_s(r['due_at'])}',
                                textAlign: TextAlign.right,
                              ),
                              trailing: Wrap(
                                children: [
                                  IconButton(
                                    tooltip: 'اعتماد',
                                    onPressed: () => _review(r, true),
                                    icon: const Icon(
                                      Icons.check,
                                      color: Colors.green,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'رفض',
                                    onPressed: () => _review(r, false),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
  );
}
