import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_shell.dart';
import '../../shared/ui_labels.dart';
import 'unified_task_table_editor.dart';

class UnifiedTaskTableScreen extends StatefulWidget {
  const UnifiedTaskTableScreen({super.key, this.employeeUserId});

  final String? employeeUserId;

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
  List<Map<String, dynamic>> _existingUnifiedTasks = const [];
  List<Map<String, dynamic>> _selectedEmployeeTasks = const [];
  Map<String, dynamic>? _editingTask;
  final Set<String> _successfulDispatches = <String>{};
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
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
      final allowed = permissions is List &&
          permissions.map((e) => e.toString()).contains('tasks.manage');
      if (!allowed)
        throw Exception('هذا القسم متاح لصلاحيات إدارة المهام فقط.');
      _organizationId = organization;
      _defaultBranchId = _defaultBranch(profile);
      final baseResults = await Future.wait<dynamic>([
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
            .from('tasks')
            .select(
                'id,title,description,branch_id,assigned_to,due_at,status,report_required,updated_at,deleted_at,idempotency_key')
            .eq('organization_id', organization)
            .isFilter('deleted_at', null)
            .order('updated_at', ascending: false)
            .limit(500),
      ]).timeout(const Duration(seconds: 20));
      List<dynamic> reportResults = const [];
      try {
        reportResults = await Future.wait<dynamic>([
          _db
              .from('report_form_templates')
              .select('id,title,role_code')
              .eq('organization_id', organization)
              .eq('is_active', true)
              .order('title')
              .limit(200),
          _db
              .from('report_form_versions')
              .select(
                  'id,template_id,status,version_no,approved_by,approved_at')
              .eq('status', 'published')
              .limit(500),
          _db
              .from('report_form_version_fields')
              .select('version_id,is_required')
              .limit(2000),
        ]).timeout(const Duration(seconds: 20));
      } catch (_) {
        // القوالب اختيارية؛ لا تمنع فتح محرر الجدول إذا تعذر تحميلها.
        reportResults = const [];
      }
      final employees = (baseResults[0] as List)
          .whereType<Map>()
          .map((row) => UnifiedEmployeeOption(
                name: (row['display_name'] ?? '').toString(),
                userId: (row['user_id'] ?? '').toString(),
              ))
          .where((item) => item.name.isNotEmpty && item.userId.isNotEmpty)
          .toList();
      final templates = reportResults.length > 0
          ? (reportResults[0] as List).whereType<Map>().toList()
          : <Map>[];
      final versions = reportResults.length > 1
          ? (reportResults[1] as List)
              .whereType<Map>()
              .where((row) =>
                  row['approved_by'] != null && row['approved_at'] != null)
              .toList()
          : <Map>[];
      final fieldsByVersion = <String, List<Map<String, dynamic>>>{};
      for (final row
          in (reportResults.length > 2 ? reportResults[2] as List : const [])
              .whereType<Map>()) {
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
        final currentNumber =
            int.tryParse('${current?['version_no'] ?? 0}') ?? 0;
        if (current == null || number > currentNumber) {
          latestByTemplate[templateId] = Map<String, dynamic>.from(version);
        }
      }
      final reports = latestByTemplate.values
          .map((version) {
            final matches = templates
                .where((row) =>
                    row['id']?.toString() == version['template_id']?.toString())
                .toList();
            if (matches.isEmpty) return null;
            final template = matches.first;
            final fields =
                fieldsByVersion[version['id']?.toString()] ?? const [];
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
          })
          .whereType<UnifiedReportOption>()
          .toList();
      if (!mounted) return;
      setState(() {
        _employees = [
          const UnifiedEmployeeOption(name: 'مهام مشتركة', userId: ''),
          ...employees,
        ];
        _branches = (baseResults[1] as List)
            .whereType<Map>()
            .map((row) => UnifiedBranchOption(
                  id: (row['id'] ?? '').toString(),
                  name: (row['name'] ?? '').toString(),
                ))
            .where((branch) => branch.id.isNotEmpty && branch.name.isNotEmpty)
            .toList();
        _existingUnifiedTasks = (baseResults[2] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where(_isUnifiedTask)
            .toList();
        _selectedEmployeeTasks = widget.employeeUserId == null ||
                widget.employeeUserId!.trim().isEmpty
            ? const []
            : _existingUnifiedTasks
                .where((task) =>
                    _text(task['assigned_to']) == widget.employeeUserId)
                .toList();
        if (_selectedEmployeeTasks.isNotEmpty) {
          _editingTask = _selectedEmployeeTasks.first;
        }
        _reports = reports;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'تعذر تحميل بيانات الجدول الموحد. تحقق من الاتصال والصلاحيات ثم أعد المحاولة.';
        _loading = false;
      });
    }
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

  String _text(dynamic value, [String fallback = '']) =>
      value == null ? fallback : value.toString();

  bool _isUnifiedTask(Map<String, dynamic> task) {
    // المهمة الأصلية المعتمدة سجل تاريخي، أما الإصدار اليومي الناتج
    // عن دورة الاعتماد فيبقى ظاهرًا وقابلًا للتحرير ضمن الجدول الموحد.
    if (_text(task['status']) == 'completed_approved') {
      return false;
    }
    return _text(task['title']).startsWith('الجدول الموحد -') ||
        _text(task['description']).contains('الجدول الموحد الرسمي:');
  }

  String _lineValue(String text, String label) {
    for (final line in text.split('\n')) {
      if (line.trimLeft().startsWith(label)) {
        return line.substring(line.indexOf(':') + 1).trim();
      }
    }
    return '';
  }

  String _employeeName(String userId) {
    final employee = _employees.where((item) => item.userId == userId).toList();
    return employee.isEmpty ? '' : employee.first.name;
  }

  String _branchName(String? branchId) {
    if (branchId == null || branchId.isEmpty) return '';
    final branch = _branches.where((item) => item.id == branchId).toList();
    return branch.isEmpty ? '' : branch.first.name;
  }

  String _roleCode(String role) =>
      const {
        'صاحب المؤسسة': 'owner',
        'المدير التنفيذي': 'admin_followup',
        'المحاسب': 'accountant',
        'أمين المخزن': 'warehouse_keeper',
        'أمين مخزن': 'warehouse_keeper',
        'عامل تحميل': 'warehouse_worker',
        'عمال التحميل': 'warehouse_worker',
      }[role.trim()] ??
      role.trim();

  UnifiedTaskTableDraft _draftFromExistingTask(Map<String, dynamic> task) {
    final description = _text(task['description']);
    final rowMatch = RegExp(
      r'^صف الجدول:\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*$',
      multiLine: true,
    ).firstMatch(description);
    final taskTitle = _text(task['title'])
        .replaceFirst(RegExp(r'^الجدول الموحد\s*-\s*'), '')
        .replaceFirst(RegExp(r'^.*?\s*[·•]\s*'), '')
        .trim();
    final row = UnifiedTaskRowData(
      time: rowMatch?.group(1)?.trim() ?? '',
      task: rowMatch?.group(2)?.trim().isNotEmpty == true
          ? rowMatch!.group(2)!.trim()
          : taskTitle,
      output: rowMatch?.group(3)?.trim() ?? '',
    );
    final hours = _lineValue(description, 'ساعات الدوام');
    String hoursValue(String label) {
      final match = label.isEmpty
          ? RegExp(r'^([^·]+)').firstMatch(hours)
          : RegExp('$label\\s*:\\s*([^·]+)').firstMatch(hours);
      return match?.group(1)?.trim() ?? '';
    }

    String? branchId = _text(task['branch_id']);
    if (branchId.isEmpty) branchId = null;
    return UnifiedTaskTableDraft(
      employee: _employeeName(_text(task['assigned_to'])),
      employeeUserId: _text(task['assigned_to']),
      role: _lineValue(description, 'المسمى الوظيفي'),
      branch: _branchName(branchId),
      branchId: branchId,
      startDate: _lineValue(description, 'تاريخ بدء التطبيق'),
      purpose: _lineValue(description, 'الهدف من الوظيفة'),
      reportNotes: _lineValue(description, 'ملاحظات وتعليمات إضافية'),
      rows: [row],
      responsibilities: _lineValue(description, 'المسؤوليات')
          .split('،')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      authorities: _lineValue(description, 'الصلاحيات')
          .split('،')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      instructions: _lineValue(description, 'التعليمات')
          .split('،')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      workType: hoursValue(''),
      workDays: '',
      weeklyException: _lineValue(description, 'الاستثناء الأسبوعي'),
      firstPeriod: hoursValue('الفترة الأولى'),
      breakPeriod: hoursValue('الاستراحة'),
      secondPeriod: hoursValue('الفترة الثانية'),
      kpis: _lineValue(description, 'مؤشرات الأداء')
          .split('؛')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      reportRequired: task['report_required'] != false,
      reportSchemasByTask: const {},
    );
  }

  UnifiedTaskTableDraft _draftFromEmployeeTasks(
      List<Map<String, dynamic>> tasks) {
    final first = _draftFromExistingTask(tasks.first);
    final rows = tasks
        .map(_draftFromExistingTask)
        .expand((draft) => draft.rows)
        .toList();
    return UnifiedTaskTableDraft(
      employee: first.employee,
      employeeUserId: first.employeeUserId,
      role: first.role,
      branch: first.branch,
      branchId: first.branchId,
      startDate: first.startDate,
      purpose: first.purpose,
      reportNotes: first.reportNotes,
      rows: rows,
      responsibilities: first.responsibilities,
      authorities: first.authorities,
      instructions: first.instructions,
      workType: first.workType,
      workDays: first.workDays,
      weeklyException: first.weeklyException,
      firstPeriod: first.firstPeriod,
      breakPeriod: first.breakPeriod,
      secondPeriod: first.secondPeriod,
      kpis: first.kpis,
      reportSchemasByTask: const {},
      reportTemplateId: first.reportTemplateId,
      reportVersionId: first.reportVersionId,
      reportRequired: first.reportRequired,
    );
  }

  Future<void> _updateSelectedEmployeeTasks(UnifiedTaskTableDraft draft) async {
    final organizationId = _organizationId;
    if (organizationId == null || _selectedEmployeeTasks.isEmpty) return;
    for (var index = 0;
        index < _selectedEmployeeTasks.length && index < draft.rows.length;
        index++) {
      final task = _selectedEmployeeTasks[index];
      final row = draft.rows[index];
      await _db.rpc('admin_update_unified_task', params: {
        'p_organization_id': organizationId,
        'p_task_id': task['id'],
        'p_title': 'الجدول الموحد - ${draft.role} · ${row.task}',
        'p_description': _descriptionForRow(draft, row),
        'p_due_at': _dueForRow(draft.startDate, row.time).toIso8601String(),
        'p_assigned_to':
            draft.employeeUserId.isEmpty ? null : draft.employeeUserId,
        'p_branch_id': draft.branchId,
        'p_role_code': _roleCode(draft.role),
      });
    }
    if (!mounted) return;
    setState(() {
      _editingTask = null;
      _selectedEmployeeTasks = const [];
      _hasUnsavedChanges = false;
    });
    await _loadOptions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث جميع مهام الموظف داخل الجدول الموحد.'),
        ),
      );
    }
  }

  String _descriptionForRow(
          UnifiedTaskTableDraft draft, UnifiedTaskRowData row) =>
      [
        'الجدول الموحد الرسمي: ${draft.role}',
        'صف الجدول: ${row.time.isEmpty ? 'غير محدد' : row.time} | ${row.task} | ${row.output.isEmpty ? '—' : row.output}',
        if (row.extras.isNotEmpty)
          'الأعمدة الإضافية: ${row.extras.entries.map((entry) => '${entry.key}: ${entry.value.isEmpty ? '—' : entry.value}').join(' · ')}',
        'المسمى الوظيفي: ${draft.role}',
        if (draft.branch.isNotEmpty) 'الفرع: ${draft.branch}',
        if (draft.startDate.isNotEmpty) 'تاريخ بدء التطبيق: ${draft.startDate}',
        'ساعات الدوام: ${draft.workType} · ${draft.workDays} · الفترة الأولى: ${draft.firstPeriod.isEmpty ? '—' : draft.firstPeriod} · الاستراحة: ${draft.breakPeriod.isEmpty ? '—' : draft.breakPeriod} · الفترة الثانية: ${draft.secondPeriod.isEmpty ? '—' : draft.secondPeriod} · الاستثناء الأسبوعي: ${draft.weeklyException}',
        if (draft.purpose.isNotEmpty) 'الهدف من الوظيفة: ${draft.purpose}',
        if (draft.reportNotes.isNotEmpty)
          'ملاحظات وتعليمات إضافية: ${draft.reportNotes}',
        if (draft.responsibilities.isNotEmpty)
          'المسؤوليات: ${draft.responsibilities.join('، ')}',
        if (draft.authorities.isNotEmpty)
          'الصلاحيات: ${draft.authorities.join('، ')}',
        if (draft.instructions.isNotEmpty)
          'التعليمات: ${draft.instructions.join('، ')}',
        if (draft.kpis.isNotEmpty) 'مؤشرات الأداء: ${draft.kpis.join('؛ ')}',
      ].join('\n');

  Widget _previousUnifiedTasksTable() {
    if (widget.employeeUserId == null || widget.employeeUserId!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final previousTasks = _selectedEmployeeTasks;
    if (previousTasks.isEmpty) return const SizedBox.shrink();
    final rows = <DataRow>[];
    for (final task in previousTasks) {
      final description = _text(task['description']);
      final matches = RegExp(
        r'^صف الجدول:\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*$',
        multiLine: true,
      ).allMatches(description);
      final taskRows = matches.isEmpty
          ? [
              [
                _lineValue(description, 'الوقت المحدد'),
                _text(task['title'], 'مهمة'),
              ],
            ]
          : matches
              .map((match) => [
                    match.group(1)?.trim() ?? '',
                    match.group(2)?.trim() ?? '',
                  ])
              .toList();
      for (final row in taskRows) {
        rows.add(
          DataRow(
            cells: [
              DataCell(Text(
                uiStatusLabel(_text(task['status'], 'new')),
                textAlign: TextAlign.right,
              )),
              DataCell(Text(
                _branchName(_text(task['branch_id'])).isEmpty
                    ? '—'
                    : _branchName(_text(task['branch_id'])),
                textAlign: TextAlign.right,
              )),
              DataCell(Text(
                _employeeName(_text(task['assigned_to'])).isEmpty
                    ? 'مهام مشتركة'
                    : _employeeName(_text(task['assigned_to'])),
                textAlign: TextAlign.right,
              )),
              DataCell(Text(row[1].isEmpty ? '—' : row[1], textAlign: TextAlign.right)),
              DataCell(Text(row[0].isEmpty ? '—' : row[0], textAlign: TextAlign.right)),
            ],
          ),
        );
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFF8FBFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFD8E4E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'المهام السابقة في الجدول الموحد',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF0B3458),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'تم العثور على ${rows.length} صف سابق. يمكن إنشاء مهمة جديدة دون حذف هذه البيانات.',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(Color(0xFFEAF1EF)),
                columns: const [
                  DataColumn(label: Text('الحالة')),
                  DataColumn(label: Text('الفرع')),
                  DataColumn(label: Text('الموظف')),
                  DataColumn(label: Text('المهمة والمسؤولية')),
                  DataColumn(label: Text('الوقت')),
                ],
                rows: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateExistingTask(UnifiedTaskTableDraft draft) async {
    final task = _editingTask;
    final organizationId = _organizationId;
    if (task == null || organizationId == null) return;
    final row = draft.rows.isEmpty
        ? const UnifiedTaskRowData(time: '', task: 'مهمة', output: '')
        : draft.rows.first;
    await _db.rpc('admin_update_unified_task', params: {
      'p_organization_id': organizationId,
      'p_task_id': task['id'],
      'p_title': 'الجدول الموحد - ${draft.role} · ${row.task}',
      'p_description': _descriptionForRow(draft, row),
      'p_due_at': _dueForRow(draft.startDate, row.time).toIso8601String(),
      'p_assigned_to':
          draft.employeeUserId.isEmpty ? null : draft.employeeUserId,
      'p_branch_id': draft.branchId,
      'p_role_code': _roleCode(draft.role),
    });
    if (!mounted) return;
    setState(() {
      _editingTask = null;
      _hasUnsavedChanges = false;
    });
    await _loadOptions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم تحديث المهمة داخل الجدول الموحد بنجاح.',
                textAlign: TextAlign.right)),
      );
    }
  }

  String _stableDispatchKey({
    required String organizationId,
    required String userId,
    required String branchId,
    required String roleCode,
    required String startDate,
    required String reportVersionId,
    required UnifiedTaskRowData row,
  }) {
    final canonical = [
      organizationId,
      userId,
      branchId,
      roleCode,
      startDate,
      reportVersionId,
      _timeSlot(row.time),
    ].join('|');
    // Stable FNV-1a hash: no package or platform-specific hashCode is used.
    var hash = 2166136261;
    for (final byte in utf8.encode(canonical)) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return 'unified:$organizationId:${hash.toRadixString(16).padLeft(8, '0')}';
  }

  Future<bool> _dispatchAlreadyExists(String key) async {
    final rows = await _db
        .from('tasks')
        .select('id')
        .eq('organization_id', _organizationId!)
        .eq('idempotency_key', key)
        .isFilter('deleted_at', null)
        .limit(1);
    return rows.isNotEmpty;
  }

  Future<bool> _dispatchTimeAlreadyExists({
    required String userId,
    required String? branchId,
    required String time,
  }) async {
    final slot = _timeSlot(time);
    if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(slot)) return false;
    final marker = 'صف الجدول: $slot';
    var query = _db
        .from('tasks')
        .select('id')
        .eq('organization_id', _organizationId!)
        .eq('assignee_employee_id', userId)
        .ilike('description', '%$marker%')
        .isFilter('deleted_at', null);
    query = branchId == null || branchId.isEmpty
        ? query.isFilter('branch_id', null)
        : query.eq('branch_id', branchId);
    final rows = await query.limit(1);
    return rows.isNotEmpty;
  }

  DateTime _dueForRow(String startDate, String time) {
    final date = DateTime.tryParse(startDate) ?? DateTime.now();
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(_timeSlot(time));
    final hour = int.tryParse(match?.group(1) ?? '') ?? 0;
    final minute = int.tryParse(match?.group(2) ?? '') ?? 0;
    return DateTime(date.year, date.month, date.day, hour, minute).toUtc();
  }

  String _timeSlot(String value) {
    final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(value.trim());
    return match?.group(1) ?? value.trim().toLowerCase();
  }

  bool _hasKeyword(String text, List<String> words) => words.any(text.contains);

  String _fieldKey(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'custom_field' : 'custom_$normalized';
  }

  List<Map<String, dynamic>> _automaticReportSchema(
    UnifiedTaskRowData row, {
    String purpose = '',
    List<String> instructions = const [],
    List<String> kpis = const [],
  }) {
    final text = [
      row.task,
      row.output,
      ...row.extras.entries.map((entry) => '${entry.key} ${entry.value}'),
      purpose,
      ...instructions,
      ...kpis,
    ].join(' ').toLowerCase();
    final fields = <Map<String, dynamic>>[];
    final keys = <String>{};

    void add(
      String key,
      String label,
      String type, {
      bool required = false,
      List<String> options = const [],
      Map<String, dynamic>? config,
    }) {
      if (keys.add(key)) {
        fields.add({
          'key': key,
          'label': label,
          'type': type,
          'required': required,
          if (options.isNotEmpty) 'options': options,
          if (config != null) 'config': config,
        });
      }
    }

    add('actual_result', 'النتيجة الفعلية', 'textarea', required: true);
    add('execution_status', 'حالة التنفيذ', 'select',
        required: true, options: ['مكتملة', 'مكتملة جزئيًا', 'تعذر التنفيذ']);

    if (_hasKeyword(text, ['مخزون', 'كمية', 'مستودع', 'صنف', 'أصناف'])) {
      add('system_quantity', 'الكمية في النظام', 'number', required: true);
      add('actual_quantity', 'الكمية الفعلية', 'number', required: true);
      add('quantity_difference', 'الفرق', 'calculated',
          config: const {'formula': '{actual_quantity} - {system_quantity}'});
      add('stock_condition', 'حالة المخزون', 'select',
          required: true, options: ['مطابق', 'يوجد فرق', 'تالف', 'غير متوفر']);
    }
    if (_hasKeyword(text, ['مبيعات', 'بيع', 'فاتورة', 'فواتير', 'إيراد'])) {
      add('sales_total', 'إجمالي المبيعات', 'number', required: true);
      add('invoice_count', 'عدد الفواتير', 'number', required: true);
      add('returns_total', 'قيمة المرتجعات', 'number');
      add('average_invoice', 'متوسط قيمة الفاتورة', 'calculated',
          config: const {'formula': '{sales_total} / {invoice_count}'});
      add('sales_evidence', 'كشف أو صورة المبيعات', 'attachment');
    }
    if (_hasKeyword(text, ['حضور', 'انصراف', 'دوام', 'تأخير'])) {
      add('attendance_time', 'وقت الحضور', 'text', required: true);
      add('departure_time', 'وقت الانصراف', 'text');
      add('attendance_status', 'حالة الحضور', 'select',
          required: true, options: ['حاضر', 'متأخر', 'غائب', 'خروج مبكر']);
      add('delay_reason', 'سبب التأخير', 'textarea');
      add('attendance_evidence', 'إثبات الحضور', 'attachment');
    }
    if (_hasKeyword(text, ['صيانة', 'إصلاح', 'عطل'])) {
      add('issue_description', 'وصف العطل', 'textarea', required: true);
      add('issue_cause', 'سبب العطل', 'text');
      add('action_taken', 'الإجراء المتخذ', 'textarea', required: true);
      add('parts_used', 'قطع الغيار المستخدمة', 'textarea');
      add('repair_cost', 'تكلفة الإصلاح', 'money');
      add('repair_status', 'حالة الإصلاح', 'select',
          required: true,
          options: ['تم الإصلاح', 'يحتاج متابعة', 'لم يتم الإصلاح']);
      add('before_repair', 'صورة قبل الإصلاح', 'attachment');
      add('after_repair', 'صورة بعد الإصلاح', 'attachment');
    }
    if (_hasKeyword(text, ['فحص', 'تفتيش', 'مراجعة', 'تدقيق', 'مطابقة'])) {
      add('inspection_result', 'نتيجة الفحص', 'select',
          required: true, options: ['سليم', 'يحتاج معالجة', 'غير مطابق']);
      add('checklist_completed', 'تم تنفيذ قائمة الفحص', 'checkbox',
          required: true);
      add('compliance_percent', 'درجة الالتزام', 'percentage');
      add('findings', 'الملاحظات والنتائج', 'textarea');
      add('corrective_action', 'الإجراء التصحيحي', 'textarea');
      add('evidence', 'مرفق الإثبات', 'attachment');
    }
    if (_hasKeyword(text, ['تنظيف', 'ترتيب', 'تجهيز', 'إنجاز'])) {
      add('completion_percent', 'نسبة الإنجاز', 'percentage', required: true);
      add('work_checklist', 'تم تنفيذ الأعمال المطلوبة', 'checkbox',
          required: true);
      add('place_status', 'حالة المكان', 'select',
          required: true, options: ['جاهز', 'جاهز جزئيًا', 'غير جاهز']);
      add('before_work', 'صورة قبل التنفيذ', 'attachment');
      add('completion_evidence', 'صورة الإنجاز', 'attachment');
    }
    final isCustomerCollectionTask = _hasKeyword(text, [
      'تحصيل',
      'المستحق',
      'مستحقات',
      'عملاء',
      'عميل',
      'اتصال',
      'اتصالات',
      'متابعة',
    ]);
    if (isCustomerCollectionTask) {
      add('customer_name', 'اسم العميل', 'text', required: true);
      add('customer_phone', 'رقم العميل', 'text');
      add('outstanding_amount', 'قيمة المستحقات', 'money');
      add('collected_amount', 'المبلغ المحصل', 'money');
      add('collection_status', 'حالة التحصيل', 'select',
          required: true,
          options: [
            'تم التحصيل',
            'تحصيل جزئي',
            'لم يتم التحصيل',
            'وعد بالسداد',
            'تعذر التواصل'
          ]);
      add('contact_result', 'نتيجة المتابعة', 'textarea', required: true);
      add('next_action', 'الإجراء التالي', 'textarea');
      add('next_follow_up', 'موعد المتابعة القادمة', 'date');
      add('collection_evidence', 'مرفق التحصيل أو إثبات التواصل', 'attachment');
    }
    // A general accounting purpose must not turn a customer-follow-up task
    // into a generic accounting transaction form.
    if (!isCustomerCollectionTask &&
        _hasKeyword(text,
            ['محاسبة', 'حساب', 'مصروف', 'قبض', 'صرف', 'تحويل', 'تسوية'])) {
      add('financial_amount', 'المبلغ', 'money', required: true);
      add('transaction_type', 'نوع العملية', 'select',
          required: true, options: ['قبض', 'صرف', 'تسوية', 'تحويل']);
      add('document_number', 'رقم المستند', 'text');
      add('account_party', 'الحساب أو الجهة', 'text');
      add('reconciliation_status', 'حالة المطابقة', 'select',
          required: true, options: ['مطابق', 'غير مطابق', 'يحتاج مراجعة']);
      add('financial_document', 'صورة المستند المالي', 'attachment');
      add('accountant_notes', 'ملاحظات المحاسب', 'textarea');
    }
    if (_hasKeyword(text, ['خطاب', 'معاملة', 'طلب', 'اعتماد', 'إجراء إداري'])) {
      add('transaction_number', 'رقم المعاملة', 'text');
      add('responsible_entity', 'الجهة المعنية', 'text');
      add('administrative_status', 'حالة المعاملة', 'select',
          required: true,
          options: ['جديدة', 'قيد المتابعة', 'مكتملة', 'متوقفة']);
      add('administrative_action', 'الإجراء المتخذ', 'textarea');
      add('next_action_date', 'تاريخ الإجراء التالي', 'date');
      add('administrative_attachments', 'مرفقات المعاملة', 'attachment');
    }
    if (_hasKeyword(text, ['تقييم', 'جودة', 'رضا', 'أداء'])) {
      add('quality_rating', 'التقييم', 'rating', required: true);
      add('quality_notes', 'ملاحظات الجودة', 'textarea');
    }
    var extraIndex = 0;
    for (final entry in row.extras.entries) {
      final label = entry.key.trim();
      if (label.isNotEmpty) {
        add('${_fieldKey(label)}_$extraIndex', label, 'text');
        extraIndex++;
      }
    }
    add('execution_date', 'تاريخ التنفيذ', 'date', required: true);
    add('notes', 'ملاحظات الموظف', 'textarea');
    return fields.length <= 30 ? fields : fields.take(30).toList();
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
        : members
            .where((row) => row['user_id']?.toString() == draft.employeeUserId)
            .toList();
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
    var skippedDuplicateCount = 0;
    for (final member in selected) {
      final userId = member['user_id']?.toString();
      if (userId == null || userId.isEmpty) continue;
      for (final row in draft.rows) {
        final due = _dueForRow(draft.startDate, row.time);
        final dispatchKey = _stableDispatchKey(
          organizationId: organizationId,
          userId: userId,
          branchId: branchId ?? '',
          roleCode: roleCode,
          startDate: draft.startDate,
          reportVersionId: draft.reportVersionId ?? '',
          row: row,
        );
        if (_successfulDispatches.contains(dispatchKey) ||
            await _dispatchAlreadyExists(dispatchKey) ||
            await _dispatchTimeAlreadyExists(
              userId: userId,
              branchId: branchId,
              time: row.time,
            )) {
          _successfulDispatches.add(dispatchKey);
          skippedDuplicateCount++;
          continue;
        }
        final description = [
          'الجدول الموحد الرسمي: ${draft.role}',
          'صف الجدول: ${row.time.isEmpty ? 'غير محدد' : row.time} | ${row.task} | ${row.output.isEmpty ? '—' : row.output}',
          if (row.extras.isNotEmpty)
            'الأعمدة الإضافية: ${row.extras.entries.map((entry) => '${entry.key}: ${entry.value.isEmpty ? '—' : entry.value}').join(' · ')}',
          'المسمى الوظيفي: ${draft.role}',
          if (draft.branch.isNotEmpty) 'الفرع: ${draft.branch}',
          if (draft.startDate.isNotEmpty)
            'تاريخ بدء التطبيق: ${draft.startDate}',
          'ساعات الدوام: ${draft.workType} · ${draft.workDays} · الفترة الأولى: ${draft.firstPeriod.isEmpty ? '—' : draft.firstPeriod} · الاستراحة: ${draft.breakPeriod.isEmpty ? '—' : draft.breakPeriod} · الفترة الثانية: ${draft.secondPeriod.isEmpty ? '—' : draft.secondPeriod} · الاستثناء الأسبوعي: ${draft.weeklyException}',
          if (draft.purpose.isNotEmpty) 'الهدف من الوظيفة: ${draft.purpose}',
          if (draft.reportNotes.isNotEmpty)
            'ملاحظات وتعليمات إضافية: ${draft.reportNotes}',
          if (draft.responsibilities.isNotEmpty)
            'المسؤوليات: ${draft.responsibilities.join('، ')}',
          if (draft.authorities.isNotEmpty)
            'الصلاحيات: ${draft.authorities.join('، ')}',
          if (draft.instructions.isNotEmpty)
            'التعليمات: ${draft.instructions.join('، ')}',
          if (draft.kpis.isNotEmpty) 'مؤشرات الأداء: ${draft.kpis.join('؛ ')}',
        ].join('\n');
        await _db.rpc('create_task_with_report_form', params: {
          'p_organization_id': organizationId,
          'p_title': 'الجدول الموحد - ${draft.role} · ${row.task}',
          'p_description': description,
          'p_due_at': due.toIso8601String(),
          'p_priority': 'normal',
          'p_branch_id': branchId,
          'p_role_code': roleCode,
          'p_template_id': draft.reportTemplateId,
          'p_assigned_to': userId,
          'p_report_template_id':
              draft.reportRequired ? draft.reportTemplateId : null,
          'p_report_version_id':
              draft.reportRequired ? draft.reportVersionId : null,
          'p_report_required': draft.reportRequired,
          'p_idempotency_key': dispatchKey,
          'p_report_schema': draft.reportRequired
              ? (draft.reportSchemasByTask[unifiedTaskReportKey(row)] ??
                  _automaticReportSchema(
                    row,
                    purpose: draft.purpose,
                    instructions: draft.instructions,
                    kpis: draft.kpis,
                  ))
              : null,
        });
        _successfulDispatches.add(dispatchKey);
      }
    }
    if (mounted) setState(() => _hasUnsavedChanges = false);
    if (skippedDuplicateCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'تم تجاهل $skippedDuplicateCount مهمة مكررة لأن وقتها سبق إرساله.',
                textAlign: TextAlign.right)),
      );
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges || !mounted) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغييرات غير محفوظة', textAlign: TextAlign.right),
        content: const Text('لديك تغييرات غير محفوظة، هل تريد الخروج؟',
            textAlign: TextAlign.right),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('البقاء')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('الخروج وفقدان التعديلات')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) => AppShell(
        title: 'إنشاء مهام بالجدول الموحد',
        subtitle: 'إنشاء المهام اليومية وإرسالها للموظفين',
        onBeforeNavigate: _confirmDiscardChanges,
        child: WillPopScope(
          onWillPop: _confirmDiscardChanges,
          child: _loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('جارٍ تحميل بيانات الجدول الموحد...',
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  if (await _confirmDiscardChanges() && mounted)
                                    context.pop();
                                },
                                icon: const Icon(Icons.arrow_forward),
                                label: const Text('العودة إلى الشاشة السابقة'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  if (await _confirmDiscardChanges() && mounted)
                                    context
                                        .push('/admin/unified-task-management');
                                },
                                icon: const Icon(Icons.manage_search_outlined),
                                label: const Text('إدارة مهام الجدول الموحد'),
                              ),
                            ],
                          ),
                        ),
                        _previousUnifiedTasksTable(),
                        UnifiedTaskTableEditor(
                          key: ValueKey(
                              _editingTask?['id'] ?? 'new-unified-task'),
                          onSend: _send,
                          previousTasks: widget.employeeUserId == null
                              ? const []
                              : _selectedEmployeeTasks,
                          initialDraft: _selectedEmployeeTasks.isNotEmpty
                              ? _draftFromEmployeeTasks(_selectedEmployeeTasks)
                              : (_editingTask == null
                                  ? null
                                  : _draftFromExistingTask(_editingTask!)),
                          onSave: _selectedEmployeeTasks.isNotEmpty
                              ? _updateSelectedEmployeeTasks
                              : (_editingTask == null
                                  ? null
                                  : _updateExistingTask),
                          reportSchemaBuilder:
                              (row, purpose, instructions, kpis) =>
                                  _automaticReportSchema(
                            row,
                            purpose: purpose,
                            instructions: instructions,
                            kpis: kpis,
                          ),
                          onChanged: () {
                            if (!_hasUnsavedChanges && mounted)
                              setState(() => _hasUnsavedChanges = true);
                          },
                          employees: _employees,
                          branches: _branches,
                          reports: _reports,
                        ),
                      ],
                    ),
        ),
      );
}
