import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/unified_task_table_editor.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/form_widgets.dart';

class TaskManagementScreen extends StatefulWidget {
  const TaskManagementScreen({
    super.key,
    this.unifiedOnly = false,
    this.initialTaskFilter,
  });
  final bool unifiedOnly;
  final String? initialTaskFilter;
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
      _reportTemplates = [];
  Map<String, Map<String, dynamic>> _reportByTask = {};
  Map<String, Map<String, dynamic>> _draftByTask = {};
  final Set<String> _expandedUnifiedTasks = <String>{};
  String _taskFilter = 'all', _reportFilter = 'all';
  String _employeeFilter = 'all';
  bool _filtersExpanded = false;
  bool _canManageActions = false;

  @override
  void initState() {
    super.initState();
    const supportedFilters = {
      'all',
      'pending',
      'received',
      'in_progress',
      'submitted',
      'needs_revision',
      'completed_approved',
      'late',
    };
    if (supportedFilters.contains(widget.initialTaskFilter)) {
      _taskFilter = widget.initialTaskFilter!;
    }
    _load();
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : <Map<String, dynamic>>[];
  String _s(dynamic v, [String fallback = '']) =>
      v == null ? fallback : v.toString();

  bool _isUnifiedTask(Map<String, dynamic> task) =>
      _s(task['title']).startsWith('الجدول الموحد -') ||
      _s(task['description']).contains('الجدول الموحد:') ||
      _s(task['description']).contains('الوقت المحدد:');

  String _lineValue(String text, String label) {
    for (final line in text.split('\n')) {
      if (line.trimLeft().startsWith(label)) {
        return line.substring(line.indexOf(':') + 1).trim();
      }
    }
    return '';
  }

  String _replaceLine(String text, String label, String value) {
    final lines = text.split('\n');
    final index = lines.indexWhere((line) => line.trimLeft().startsWith(label));
    final next = '$label ${value.trim().isEmpty ? 'غير محدد' : value.trim()}';
    if (index == -1) return '$text\n$next'.trim();
    lines[index] = next;
    return lines.join('\n').trim();
  }

  String _localDateTime(dynamic value) {
    final parsed = DateTime.tryParse(_s(value));
    if (parsed == null) return 'غير محدد';
    return DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  String _descriptionValue(String text, String label) => _lineValue(text, '$label:');

  UnifiedTaskTableDraft _unifiedDraftFromTask(Map<String, dynamic> task) {
    final description = _s(task['description']);
    final rowMatch = RegExp(r'^صف الجدول:\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*$', multiLine: true).firstMatch(description);
    final row = UnifiedTaskRowData(
      time: rowMatch?.group(1)?.trim() ?? _descriptionValue(description, 'الوقت المحدد'),
      task: rowMatch?.group(2)?.trim() ?? _s(task['title']).replaceFirst(RegExp(r'^الجدول الموحد - '), '').trim(),
      output: rowMatch?.group(3)?.trim() ?? _descriptionValue(description, 'المخرج المطلوب'),
    );
    final hours = _descriptionValue(description, 'ساعات الدوام');
    String hoursValue(String label) {
      final match = label.isEmpty
          ? RegExp(r'^([^·]+)').firstMatch(hours)
          : RegExp('$label\\s*:\\s*([^·]+)').firstMatch(hours);
      return match?.group(1)?.trim() ?? '';
    }
    return UnifiedTaskTableDraft(
      employee: _employeeName(_s(task['assigned_to'])),
      employeeUserId: _s(task['assigned_to']),
      role: _descriptionValue(description, 'المسمى الوظيفي'),
      branch: _branchName(_s(task['branch_id']).isEmpty ? null : _s(task['branch_id'])),
      branchId: _s(task['branch_id']).isEmpty ? null : _s(task['branch_id']),
      startDate: _descriptionValue(description, 'تاريخ بدء التطبيق'),
      purpose: _descriptionValue(description, 'الهدف من الوظيفة'),
      reportNotes: _descriptionValue(description, 'ملاحظات وتعليمات إضافية'),
      rows: [row],
      responsibilities: _descriptionValue(description, 'المسؤوليات').split('،').where((v) => v.trim().isNotEmpty).map((v) => v.trim()).toList(),
      authorities: _descriptionValue(description, 'الصلاحيات').split('،').where((v) => v.trim().isNotEmpty).map((v) => v.trim()).toList(),
      instructions: _descriptionValue(description, 'التعليمات').split('،').where((v) => v.trim().isNotEmpty).map((v) => v.trim()).toList(),
      workType: hoursValue(''),
      workDays: '',
      weeklyException: _descriptionValue(description, 'الاستثناء الأسبوعي'),
      firstPeriod: hoursValue('الفترة الأولى'),
      breakPeriod: hoursValue('الاستراحة'),
      secondPeriod: hoursValue('الفترة الثانية'),
      kpis: _descriptionValue(description, 'مؤشرات الأداء').split('؛').where((v) => v.trim().isNotEmpty).map((v) => v.trim()).toList(),
    );
  }

  String _unifiedDescription(UnifiedTaskTableDraft draft) {
    final row = draft.rows.isEmpty ? const UnifiedTaskRowData(time: '', task: 'مهمة', output: '') : draft.rows.first;
    return [
      'الجدول الموحد الرسمي: ${draft.role}',
      'صف الجدول: ${row.time.isEmpty ? 'غير محدد' : row.time} | ${row.task} | ${row.output.isEmpty ? '—' : row.output}',
      'المسمى الوظيفي: ${draft.role}',
      if (draft.branch.isNotEmpty) 'الفرع: ${draft.branch}',
      if (draft.startDate.isNotEmpty) 'تاريخ بدء التطبيق: ${draft.startDate}',
      'ساعات الدوام: ${draft.workType} · ${draft.workDays} · الفترة الأولى: ${draft.firstPeriod.isEmpty ? '—' : draft.firstPeriod} · الاستراحة: ${draft.breakPeriod.isEmpty ? '—' : draft.breakPeriod} · الفترة الثانية: ${draft.secondPeriod.isEmpty ? '—' : draft.secondPeriod} · الاستثناء الأسبوعي: ${draft.weeklyException}',
      if (draft.purpose.isNotEmpty) 'الهدف من الوظيفة: ${draft.purpose}',
      if (draft.reportNotes.isNotEmpty) 'ملاحظات وتعليمات إضافية: ${draft.reportNotes}',
      if (draft.responsibilities.isNotEmpty) 'المسؤوليات: ${draft.responsibilities.join('، ')}',
      if (draft.authorities.isNotEmpty) 'الصلاحيات: ${draft.authorities.join('، ')}',
      if (draft.instructions.isNotEmpty) 'التعليمات: ${draft.instructions.join('، ')}',
      if (draft.kpis.isNotEmpty) 'مؤشرات الأداء: ${draft.kpis.join('؛ ')}',
    ].join('\n');
  }

  List<Map<String, String>> _descriptionRows(String text) {
    final rows = <Map<String, String>>[];
    final extras = <String>[];
    final fields = <String, String>{};
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf(':');
      if (separator <= 0) {
        extras.add(line);
        continue;
      }
      final label = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (label == 'وصف المهمة 1' || label == 'وصف المهمة') continue;
      if (label == 'صف الجدول') {
        final parts = value.split('|').map((part) => part.trim()).toList();
        if (parts.isNotEmpty && parts[0].isNotEmpty) fields['الوقت / الفترة'] = parts[0];
        if (parts.length > 1 && parts[1].isNotEmpty) fields['المهمة / المسؤولية'] = parts[1];
        if (parts.length > 2 && parts[2].isNotEmpty) fields['المخرج المطلوب'] = parts.sublist(2).join(' | ');
      } else {
        final normalizedLabel = label == 'الجدول الموحد' ? 'الجدول الموحد الرسمي' : label;
        fields[normalizedLabel] = value.isEmpty ? 'غير محدد' : value;
      }
    }
    const preferredOrder = [
      'الجدول الموحد الرسمي',
      'المسمى الوظيفي',
      'الفرع',
      'الوقت المحدد',
      'الوقت / الفترة',
      'المهمة / المسؤولية',
      'المخرج المطلوب',
    ];
    for (final label in preferredOrder) {
      final value = fields.remove(label);
      if (value != null && value.isNotEmpty) {
        rows.add({'label': label, 'value': value});
      }
    }
    fields.forEach((label, value) {
      rows.add({'label': label, 'value': value.isEmpty ? 'غير محدد' : value});
    });
    if (extras.isNotEmpty) rows.add({'label': 'تفاصيل إضافية', 'value': extras.join('\n')});
    if (rows.isEmpty) rows.add({'label': 'الوصف', 'value': 'لا توجد تفاصيل وصف محفوظة.'});
    return rows;
  }

  Widget _descriptionTable(String text) {
    final rows = _descriptionRows(text);
    return Directionality(
      textDirection: Directionality.of(context),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          columnWidths: const {0: FlexColumnWidth(1.05), 1: FlexColumnWidth(2)},
          border: TableBorder.symmetric(
            inside: BorderSide(color: Colors.grey, width: 0.35),
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant),
              children: const [
                Padding(padding: EdgeInsets.all(9), child: Text('العنصر', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(9), child: Text('البيانات', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...rows.map(
              (row) => TableRow(
                children: [
                  Padding(padding: const EdgeInsets.all(9), child: Text(row['label']!, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Padding(padding: const EdgeInsets.all(9), child: Text(row['value']!, textAlign: TextAlign.right)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
      final permissions = employee is Map ? employee['permissions'] : null;
      final allowed = permissions is List && permissions.map((e) => e.toString()).any(
            (permission) => permission == 'tasks.manage' || permission == 'tasks.review',
          );
      _canManageActions = permissions is List &&
          permissions.map((e) => e.toString()).contains('tasks.manage');
      if (!allowed) {
        if (mounted) {
          setState(() {
            _orgId = org;
            _tasks = [];
            _error = 'هذا القسم متاح لصلاحيات إدارة المهام فقط.';
            _loading = false;
          });
        }
        return;
      }
      final results = await Future.wait<dynamic>([
        _db
            .from('tasks')
            .select(
              'id,title,description,branch_id,assigned_to,due_at,priority,status,report_required,report_flow,report_form_snapshot_id,updated_at,deleted_at',
            )
            .eq('organization_id', org)
            .isFilter('deleted_at', null)
            .order('due_at')
            .limit(1000),
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
        final versions = _rows(results[4]);
        _reportTemplates = _rows(results[3]).map((template) {
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
    for (final task in _managedTasks) {
      final status = _reportStatus(task);
      summary[status] = (summary[status] ?? 0) + 1;
    }
    return summary;
  }

  List<Map<String, dynamic>> get _visibleTasks => _tasks.where((task) {
    if (_isUnifiedTask(task) != widget.unifiedOnly) return false;
    final rawTaskStatus = _s(task['status']);
    final dueAt = DateTime.tryParse(_s(task['due_at']));
    final taskMatches = _taskFilter == 'all' ||
        (_taskFilter == 'pending' && ['pending', 'new'].contains(rawTaskStatus)) ||
        (_taskFilter == 'submitted' && ['submitted', 'report_submitted'].contains(rawTaskStatus)) ||
        (_taskFilter == 'late' &&
            (rawTaskStatus == 'late' ||
                (dueAt != null && dueAt.isBefore(DateTime.now()))) &&
            !['approved', 'completed', 'completed_approved'].contains(rawTaskStatus)) ||
        rawTaskStatus == _taskFilter;
    final reportMatches = _reportFilter == 'all' || _reportStatus(task) == _reportFilter;
    final employeeMatches = _employeeFilter == 'all' ||
        _s(task['assigned_to']) == _employeeFilter;
    return taskMatches && reportMatches && employeeMatches;
  }).toList();

  List<Map<String, dynamic>> get _managedTasks =>
      _tasks.where((task) => _isUnifiedTask(task) == widget.unifiedOnly).toList();

  int get _activeFilterCount =>
      (_taskFilter == 'all' ? 0 : 1) +
      (_reportFilter == 'all' ? 0 : 1) +
      (_employeeFilter == 'all' ? 0 : 1);

  String get _filterSummary {
    final values = <String>[];
    if (_taskFilter != 'all') {
      values.add(const {
        'pending': 'جديدة',
        'received': 'مستلمة',
        'in_progress': 'قيد التنفيذ',
        'submitted': 'للمراجعة',
        'needs_revision': 'تحتاج تصحيحًا',
        'completed_approved': 'معتمدة',
        'late': 'متأخرة',
      }[_taskFilter] ?? _taskFilter);
    }
    if (_reportFilter != 'all') values.add(_reportFilter);
    if (_employeeFilter != 'all') {
      values.add(_employeeName(_employeeFilter));
    }
    return values.join(' · ');
  }

  Widget _filterChip({required String value, required String label, required String group, required VoidCallback onSelected}) =>
      ChoiceChip(
        label: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, textAlign: TextAlign.center, softWrap: false),
        ),
        labelPadding: EdgeInsets.zero,
        selected: (group == 'task' ? _taskFilter : _reportFilter) == value,
        onSelected: (_) => setState(onSelected),
      );

  Widget _filterRow(List<Widget> chips) {
    return Wrap(
      textDirection: Directionality.of(context),
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  void _resetFilters() => setState(() {
        _taskFilter = 'all';
        _reportFilter = 'all';
        _employeeFilter = 'all';
      });

  Future<void> _openUnifiedEditor(Map<String, dynamic> task) async {
    if (_orgId == null || _busy) return;
    final initial = _unifiedDraftFromTask(task);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: UnifiedTaskTableEditor(
            initialDraft: initial,
            onSend: (_) async {},
            onSave: (draft) async {
              setState(() => _busy = true);
              try {
                await _db.rpc('admin_update_unified_task', params: {
                  'p_organization_id': _orgId,
                  'p_task_id': task['id'],
                  'p_title': 'الجدول الموحد - ${draft.role} · ${draft.rows.isEmpty ? task['title'] : draft.rows.first.task}',
                  'p_description': _unifiedDescription(draft),
                  'p_due_at': task['due_at'],
                  'p_assigned_to': draft.employeeUserId,
                  'p_branch_id': draft.branchId,
                  'p_role_code': _roleCode(draft.role),
                });
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                _message('تم حفظ الجدول الموحد وتحديث المهمة لدى الموظف.');
                await _load();
              } catch (e) {
                _message('تعذر حفظ الجدول الموحد: ${e.toString().replaceFirst('Exception: ', '')}');
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
            employees: _employees.map((e) => UnifiedEmployeeOption(name: _s(e['display_name'], _s(e['employee_no'])), userId: _s(e['user_id']))).toList(),
            branches: _branches.map((b) => UnifiedBranchOption(id: _s(b['id']), name: _s(b['name'], _s(b['code'])))).toList(),
          ),
        ),
      ),
    );
  }

  String _roleCode(String role) => const {
        'صاحب المؤسسة': 'owner',
        'المدير التنفيذي': 'admin_followup',
        'المحاسب': 'accountant',
        'أمين المخزن': 'warehouse_keeper',
        'أمين مخزن': 'warehouse_keeper',
        'عمال التحميل': 'warehouse_worker',
        'عامل تحميل': 'warehouse_worker',
      }[role.trim()] ?? role.trim();

  Future<void> _saveTask({Map<String, dynamic>? existing}) async {
    final title = TextEditingController(text: _s(existing?['title']));
    final description = TextEditingController(text: _s(existing?['description']));
    final descriptionCards = <TextEditingController>[description];
    final time = TextEditingController(
      text: existing == null
          ? ''
          : _lineValue(_s(existing['description']), 'الوقت المحدد:'),
    );
    final output = TextEditingController(
      text: existing == null
          ? ''
          : _lineValue(_s(existing['description']), 'المخرج المطلوب:'),
    );
    final parsedDue = DateTime.tryParse(_s(existing?['due_at']));
    DateTime dueDate = parsedDue?.toLocal() ?? defaultDueDate();
    String priority = _s(existing?['priority'], 'normal');
    String? branchId = _s(existing?['branch_id']).isEmpty ? null : _s(existing?['branch_id']);
    String? role = 'admin_followup';
    String? assignee = _s(existing?['assigned_to']).isEmpty ? null : _s(existing?['assigned_to']);
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
            TextField(controller: title, textDirection: Directionality.of(ctx), textInputAction: TextInputAction.next, decoration: formDecoration('عنوان المهمة *', hint: 'مثال: مراجعة مخزون الفرع الرئيسي')),
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
                      if (existing != null && _isUnifiedTask(existing) && i == 0) ...[
                        _descriptionTable(descriptionCards[i].text),
                        const SizedBox(height: 8),
                        Text(
                          'يتم تعديل الوقت والمخرج المطلوب من قسم «بيانات صف الجدول الموحد» أدناه، مع الحفاظ على بقية بيانات الصف كاملة.',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ] else
                        TextField(
                          controller: descriptionCards[i],
                          textDirection: Directionality.of(ctx),
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
        if (existing != null && _isUnifiedTask(existing))
          FormSection(
            title: 'بيانات صف الجدول الموحد',
            icon: Icons.table_chart_outlined,
            note: 'تعديل هذه القيم ينعكس مباشرة على المهمة الظاهرة للموظف وكشف المهام.',
            children: [
              TextField(
                controller: time,
                textDirection: Directionality.of(ctx),
                decoration: formDecoration('الوقت / الفترة'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: output,
                textDirection: Directionality.of(ctx),
                minLines: 2,
                maxLines: 4,
                decoration: formDecoration('المخرج المطلوب'),
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
                  hint: 'اختياري — يعبئه الموظف بعد تنفيذ المهمة',
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
                onChanged: (v) => set(() {
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
      time.dispose();
      output.dispose();
      return;
    }

    setState(() => _busy = true);
    try {
      final dueIso = dueToIso(dueDate);
      var descriptionText = descriptionCards
          .asMap()
          .entries
          .where((entry) => entry.value.text.trim().isNotEmpty)
          .map((entry) => 'وصف المهمة ${entry.key + 1}:\n${entry.value.text.trim()}')
          .join('\n\n');
      if (existing != null && _isUnifiedTask(existing)) {
        final original = descriptionCards.first.text.trim();
        descriptionText = _replaceLine(
          _replaceLine(original, 'الوقت المحدد:', time.text),
          'المخرج المطلوب:',
          output.text,
        );
      }
      final safeDescription = descriptionText.trim().isEmpty
          ? 'المهمة: ${title.text.trim()}'
          : descriptionText.trim();
      if (existing != null) {
        await _db.rpc('admin_update_task', params: {'p_organization_id': _orgId, 'p_task_id': existing['id'], 'p_title': title.text.trim(), 'p_description': safeDescription, 'p_due_at': dueIso});
      } else {
        await _db.rpc('create_task_with_report_form', params: {'p_organization_id': _orgId, 'p_title': title.text.trim(), 'p_description': safeDescription, 'p_due_at': dueIso, 'p_priority': priority, 'p_branch_id': branchId, 'p_role_code': role, 'p_template_id': null, 'p_assigned_to': assignee, 'p_report_template_id': reportTemplateId, 'p_report_version_id': reportVersionId, 'p_report_required': reportRequired});
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
      time.dispose();
      output.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final taskId = _s(task['id']);
    if (taskId.isEmpty || _orgId == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المهمة؟', textAlign: TextAlign.right),
        content: Text(
          'سيتم حذف المهمة «${_s(task['title'], 'بدون عنوان')}» من قائمة الإدارة ومن عرض الموظف. لا يمكن التراجع عن هذا الإجراء.',
          textAlign: TextAlign.right,
        ),
        actionsAlignment: MainAxisAlignment.start,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _db.rpc(
        'admin_delete_task',
        params: {'p_organization_id': _orgId, 'p_task_id': taskId},
      );
      _message('تم حذف المهمة من الإدارة ومن حساب الموظف.');
      await _load();
    } catch (e) {
      _message('تعذر حذف المهمة: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    title: widget.unifiedOnly ? 'إدارة الجداول الموحدة' : 'إدارة المهام',
    subtitle: widget.unifiedOnly
        ? 'الجداول المرسلة للموظفين وتقاريرها واعتماد إنجازها'
        : 'الإنشاء المباشر والمتابعة والتقارير',
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
                      if (!widget.unifiedOnly)
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _saveTask(),
                          icon: const Icon(Icons.add),
                          label: const Text('إنشاء مهمة'),
                        ),
                      if (widget.unifiedOnly)
                        const Text(
                          'هذه الشاشة مخصصة للجداول التي أُرسلت من الجدول الموحد فقط. إنشاء جدول جديد يتم من مساره المستقل.',
                          textAlign: TextAlign.right,
                        ),
                    ],
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          textDirection: Directionality.of(context),
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    textDirection: Directionality.of(context),
                                    children: [
                                      AnimatedRotation(
                                        turns: _filtersExpanded ? .5 : 0,
                                        duration: const Duration(milliseconds: 220),
                                        child: const Icon(Icons.expand_more, color: AppColors.navy),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Text(
                                                  _filtersExpanded ? 'إخفاء' : 'إظهار',
                                                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                                ),
                                                const SizedBox(width: 7),
                                                const Text(
                                                  'تصفية المتابعة',
                                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy),
                                                ),
                                              ],
                                            ),
                                            if (!_filtersExpanded && _activeFilterCount > 0)
                                              Text(
                                                'نشط: $_activeFilterCount · $_filterSummary',
                                                textAlign: TextAlign.right,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _resetFilters,
                              icon: const Icon(Icons.restart_alt, size: 18),
                              label: const Text('إعادة تعيين'),
                            ),
                          ],
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: !_filtersExpanded
                              ? const SizedBox.shrink()
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                      if (_employees.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: _employeeFilter,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'عرض حسب الموظف',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('كل الموظفين'),
                            ),
                            ..._employees.map(
                              (employee) => DropdownMenuItem<String>(
                                value: _s(employee['user_id']),
                                child: Text(
                                  _s(employee['display_name'], _s(employee['employee_no'], 'موظف')),
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: Directionality.of(context),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _employeeFilter = value ?? 'all',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'حالة المهمة',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      _filterRow([
                          _filterChip(value: 'all', label: 'الكل', group: 'task', onSelected: () => _taskFilter = 'all'),
                          _filterChip(value: 'pending', label: 'جديدة', group: 'task', onSelected: () => _taskFilter = 'pending'),
                          _filterChip(value: 'received', label: 'مستلمة', group: 'task', onSelected: () => _taskFilter = 'received'),
                      ]),
                      const SizedBox(height: 6),
                      _filterRow([
                        _filterChip(value: 'in_progress', label: 'قيد التنفيذ', group: 'task', onSelected: () => _taskFilter = 'in_progress'),
                        _filterChip(value: 'submitted', label: 'للمراجعة', group: 'task', onSelected: () => _taskFilter = 'submitted'),
                        _filterChip(value: 'needs_revision', label: 'تحتاج تصحيحًا', group: 'task', onSelected: () => _taskFilter = 'needs_revision'),
                      ]),
                      const SizedBox(height: 6),
                      _filterRow([
                        _filterChip(value: 'completed_approved', label: 'معتمدة', group: 'task', onSelected: () => _taskFilter = 'completed_approved'),
                        _filterChip(value: 'late', label: 'متأخرة', group: 'task', onSelected: () => _taskFilter = 'late'),
                      ]),
                      const SizedBox(height: 12),
                      const Text(
                        'حالة التقرير',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      _filterRow([
                          _filterChip(value: 'all', label: 'الكل', group: 'report', onSelected: () => _reportFilter = 'all'),
                          _filterChip(value: 'لم يبدأ', label: 'لم يبدأ', group: 'report', onSelected: () => _reportFilter = 'لم يبدأ'),
                          _filterChip(value: 'مسودة', label: 'مسودة', group: 'report', onSelected: () => _reportFilter = 'مسودة'),
                      ]),
                      const SizedBox(height: 6),
                      _filterRow([
                        _filterChip(value: 'مرسل للمراجعة', label: 'مرسل للمراجعة', group: 'report', onSelected: () => _reportFilter = 'مرسل للمراجعة'),
                        _filterChip(value: 'يحتاج تعديل', label: 'يحتاج تعديل', group: 'report', onSelected: () => _reportFilter = 'يحتاج تعديل'),
                        _filterChip(value: 'معتمد', label: 'معتمد', group: 'report', onSelected: () => _reportFilter = 'معتمد'),
                      ]),
                      const SizedBox(height: 6),
                      _filterRow([
                        _filterChip(value: 'بدون تقرير', label: 'بدون تقرير', group: 'report', onSelected: () => _reportFilter = 'بدون تقرير'),
                      ]),
                    ],
                  ),
                        ),
                      ],
                    ),
                  ),
                ),
                SectionCard(
                    title: widget.unifiedOnly
                        ? 'الجداول الموحدة المرسلة (${_visibleTasks.length} من ${_managedTasks.length})'
                        : 'المهام المرسلة (${_visibleTasks.length} من ${_managedTasks.length})',
                  child: _visibleTasks.isEmpty
                      ? const Text('لا توجد مهام مطابقة للفلاتر المحددة.', textAlign: TextAlign.right)
                      : Column(
                          children: _visibleTasks
                              .map((t) {
                                final taskId = _s(t['id']);
                                final expanded = _expandedUnifiedTasks.contains(taskId);
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
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
                                      if (expanded && widget.unifiedOnly)
                                        Text(
                                          t['report_form_snapshot_id'] != null
                                              ? 'قالب التقرير: مرتبط وثابت لهذه المهمة'
                                              : 'قالب التقرير: غير مرتبط',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: t['report_form_snapshot_id'] != null
                                                ? Colors.green
                                                : Colors.red,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      Text(
                                        'الموعد: ${_localDateTime(t['due_at'])}',
                                        textAlign: TextAlign.right,
                                      ),
                                      if (expanded && _s(t['description']).trim().isNotEmpty)
                                        Text(
                                          _s(t['description']),
                                          textAlign: TextAlign.right,
                                        ),

                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: () => setState(() {
                                              if (expanded) {
                                                _expandedUnifiedTasks.remove(taskId);
                                              } else {
                                                _expandedUnifiedTasks.add(taskId);
                                              }
                                            }),
                                            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18),
                                            label: Text(expanded ? 'إخفاء التفاصيل' : 'إظهار التفاصيل'),
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
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.unifiedOnly && _canManageActions)
                                        IconButton(
                                          tooltip: 'تعديل من الجدول الموحد',
                                          onPressed: _busy ? null : () => _openUnifiedEditor(t),
                                          icon: const Icon(Icons.table_chart_outlined),
                                        ),
                                      if (_canManageActions)
                                        IconButton(
                                          tooltip: 'تعديل المهمة أو صف الجدول',
                                          onPressed: _busy ? null : () => _saveTask(existing: t),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                      if (_canManageActions)
                                        IconButton(
                                          tooltip: 'حذف المهمة',
                                          onPressed: _busy ? null : () => _deleteTask(t),
                                          color: Colors.red,
                                          icon: const Icon(Icons.delete_outline),
                                        ),
                                    ],
                                  ),
                                  onTap: () => _message(
                                    'حالة التقرير: ${_reportStatus(t)}',
                                  ),
                                  ),
                                );
                              })
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

              ],
            ),
          ),
  );
}
