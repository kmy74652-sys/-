import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

const _roleNames = <String, String>{
  'owner': 'صاحب المؤسسة',
  'admin_followup': 'مسؤول المتابعة الإدارية والتنفيذية',
  'accountant': 'المحاسب',
  'warehouse_keeper': 'أمين المخزن',
  'warehouse_worker': 'عامل التحميل',
};

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.profile});
  final Map<String, dynamic> profile;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = [];

  SupabaseClient get _db => Supabase.instance.client;
  String get _organizationId => widget.profile['institutionId'] as String? ?? '';

  bool get _canReadAll {
    final permissions = (widget.profile['permissions'] as List? ?? []).cast<String>();
    return permissions.contains('tasks.read_all') ||
        permissions.contains('tasks.manage') ||
        permissions.contains('tasks.review');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final user = _db.auth.currentUser;
      if (user == null) throw Exception('not_authenticated');
      final baseQuery = _db.from('tasks')
          .select('id,title,description,assigned_to,branch_id,due_at,starts_at,priority,status,report_flow,task_instructions,created_at')
          .eq('organization_id', _organizationId)
          .isFilter('deleted_at', null)
          .order('due_at');
      final rows = _canReadAll
          ? await baseQuery.limit(300)
          : await baseQuery.eq('assigned_to', user.id).limit(300);
      if (!mounted) return;
      setState(() => _tasks = List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _status(String? value) => switch (value) {
    'new' || 'received' || 'pending' => 'جديدة',
    'in_progress' || 'on_hold' => 'قيد التنفيذ',
    'report_submitted' || 'submitted' => 'بانتظار المراجعة',
    'completed_approved' || 'approved' => 'معتمدة',
    'needs_revision' || 'rejected' => 'تحتاج استكمالاً',
    'cancelled' => 'ملغاة',
    _ => value ?? 'غير محددة',
  };

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المهام'),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _tasks.isEmpty
                    ? const Center(child: Text('لا توجد مهام ظاهرة لهذا الحساب حالياً.'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _tasks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            return Card(
                              elevation: 0,
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: Text(
                                  task['title']?.toString() ?? 'مهمة',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('الحالة: ${_status(task['status']?.toString())}'),
                                      if (task['due_at'] != null)
                                        Text('موعد التسليم: ${_date(task['due_at'].toString())}'),
                                      if ((task['task_instructions'] ?? task['description']) != null)
                                        Text((task['task_instructions'] ?? task['description']).toString()),
                                    ],
                                  ),
                                ),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () async {
                                  await Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => TaskDetailScreen(task: task),
                                  ));
                                  _load();
                                },
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.task});
  final Map<String, dynamic> task;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _snapshots = [];
  final Map<String, Map<String, dynamic>?> _latestReports = {};

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
    _markOpened();
  }

  Future<void> _markOpened() async {
    try {
      await _db.rpc('mobile_mark_task_opened', params: {'p_task_id': widget.task['id']});
    } catch (_) {
      // Opening the task must remain possible if the optional receipt RPC is unavailable.
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final id = widget.task['id'].toString();
      final rows = await _db.from('task_report_form_snapshots')
          .select('id,title,sort_order,is_required,schema')
          .eq('task_id', id)
          .order('sort_order');
      final snapshots = List<Map<String, dynamic>>.from(rows);
      _snapshots = snapshots;
      _latestReports.clear();
      for (final snapshot in snapshots) {
        final reports = await _db.from('task_reports')
            .select('id,status,values,review_note,submitted_at')
            .eq('task_id', id)
            .eq('report_form_snapshot_id', snapshot['id'])
            .order('submitted_at', ascending: false)
            .limit(1);
        if (reports.isNotEmpty) _latestReports[snapshot['id'].toString()] = Map<String, dynamic>.from(reports.first);
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _reportStatus(String? value) => switch (value) {
    'submitted' => 'تم الإرسال — بانتظار المراجعة',
    'approved' => 'تم اعتماد التقرير',
    'returned' => 'أُعيد للتعديل',
    _ => 'لم يُرسل بعد',
  };

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final flow = task['report_flow'] == 'multi_form';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تفاصيل المهمة')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(task['title']?.toString() ?? 'مهمة',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text((task['task_instructions'] ?? task['description'] ?? '').toString()),
                      const SizedBox(height: 18),
                      const Text('نماذج التقرير والحقول المطلوبة',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (flow && _snapshots.isEmpty)
                        const _InfoCard(text: 'لم يُرفق بهذه المهمة نموذج تقرير.'),
                      if (!flow)
                        const _InfoCard(text: 'هذه المهمة تستخدم مسار التقرير السابق.'),
                      ..._snapshots.map((snapshot) {
                        final report = _latestReports[snapshot['id'].toString()];
                        final status = report?['status']?.toString();
                        final fields = (snapshot['schema'] as List? ?? []).length;
                        final canEdit = status != 'submitted' && status != 'approved';
                        return Card(
                          elevation: 0,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(snapshot['title']?.toString() ?? 'نموذج التقرير',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Text('$fields حقل · ${_reportStatus(status)}'
                                  '${report?['review_note'] == null ? '' : '\nملاحظة: ${report?['review_note']}'}'),
                            ),
                            trailing: Icon(canEdit ? Icons.edit_note : Icons.verified_outlined),
                            onTap: canEdit ? () async {
                              await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => DynamicReportScreen(
                                  taskId: task['id'].toString(),
                                  snapshot: snapshot,
                                  existingValues: (report?['values'] as Map?)?.cast<String, dynamic>(),
                                ),
                              ));
                              _load();
                            } : null,
                          ),
                        );
                      }),
                    ],
                  ),
      ),
    );
  }
}

class DynamicReportScreen extends StatefulWidget {
  const DynamicReportScreen({
    super.key,
    required this.taskId,
    required this.snapshot,
    this.existingValues,
  });
  final String taskId;
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic>? existingValues;

  @override
  State<DynamicReportScreen> createState() => _DynamicReportScreenState();
}

class _DynamicReportScreenState extends State<DynamicReportScreen> {
  final Map<String, dynamic> _values = {};
  bool _saving = false;

  List<Map<String, dynamic>> get _fields =>
      (widget.snapshot['schema'] as List? ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();

  @override
  void initState() {
    super.initState();
    _values.addAll(widget.existingValues ?? {});
    for (final field in _fields) {
      final key = field['key']?.toString() ?? '';
      if (key.isNotEmpty && !_values.containsKey(key)) {
        final defaultValue = (field['config'] as Map?)?['default_value'];
        _values[key] = defaultValue ?? (field['type'] == 'table' || field['type'] == 'multiselect' ? [] : '');
      }
    }
  }

  String? _validate() {
    for (final field in _fields) {
      final key = field['key'].toString();
      final value = _values[key];
      final type = field['type']?.toString() ?? 'text';
      final required = field['required'] == true;
      final empty = value == null || value == '' || (value is List && value.isEmpty);
      if (required && empty) return 'أكمل الحقل: ${field['label']}';
      if (empty) continue;
      final validation = (field['validation'] as Map?)?.cast<String, dynamic>() ?? {};
      if (['number','integer','decimal','quantity','money','percentage','progress'].contains(type)) {
        final number = num.tryParse(value.toString());
        if (number == null) return 'أدخل رقماً صحيحاً في حقل ${field['label']}';
        if (validation['min'] != null && number < num.parse(validation['min'].toString())) return 'قيمة ${field['label']} أقل من الحد الأدنى';
        if (validation['max'] != null && number > num.parse(validation['max'].toString())) return 'قيمة ${field['label']} تتجاوز الحد الأعلى';
      }
      if (type == 'select' && !(field['options'] as List? ?? []).map((e) => e.toString()).contains(value)) return 'اختر قيمة صحيحة في ${field['label']}';
    }
    return null;
  }

  Future<void> _submit() async {
    final issue = _validate();
    if (issue != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(issue)));
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('mobile_submit_task_report_form', params: {
        'p_task_id': widget.taskId,
        'p_snapshot_id': widget.snapshot['id'],
        'p_values': _values,
        'p_idempotency_key': 'flutter:${widget.taskId}:${widget.snapshot['id']}:${DateTime.now().microsecondsSinceEpoch}',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال التقرير للمراجعة.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(Map<String, dynamic> field) {
    final key = field['key'].toString();
    final label = field['label']?.toString() ?? key;
    final type = field['type']?.toString() ?? 'text';
    final options = (field['options'] as List? ?? []).map((e) => e.toString()).toList();
    final current = _values[key];
    final config = (field['config'] as Map?)?.cast<String, dynamic>() ?? {};
    final validation = (field['validation'] as Map?)?.cast<String, dynamic>() ?? {};
    final description = field['description']?.toString() ?? '';
    Widget editor;

    if (type == 'select') {
      editor = DropdownButtonFormField<String>(
        value: options.contains(current?.toString()) ? current.toString() : null,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: options.map((option) => DropdownMenuItem(value: option, child: Text(option))).toList(),
        onChanged: (value) => setState(() => _values[key] = value ?? ''),
      );
    } else if (type == 'multiselect') {
      final selected = (current is List ? current : []).map((e) => e.toString()).toSet();
      editor = Wrap(
        spacing: 8,
        children: options.map((option) => FilterChip(
          label: Text(option),
          selected: selected.contains(option),
          onSelected: (enabled) => setState(() {
            final next = {...selected};
            enabled ? next.add(option) : next.remove(option);
            _values[key] = next.toList();
          }),
        )).toList(),
      );
    } else if (type == 'boolean' || type == 'checkbox') {
      editor = SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(current == true ? 'نعم' : 'لا'),
        value: current == true,
        onChanged: (value) => setState(() => _values[key] = value),
      );
    } else if (type == 'table') {
      editor = _DynamicTableEditor(
        columns: (config['columns'] as List? ?? []).map((e) => Map<String, dynamic>.from(e is Map ? e : {'label': e.toString(), 'key': e.toString()})).toList(),
        rows: (current is List ? current : []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        minRows: int.tryParse(config['min_rows']?.toString() ?? '') ?? 0,
        maxRows: int.tryParse(config['max_rows']?.toString() ?? '') ?? 100,
        onChanged: (rows) => setState(() => _values[key] = rows),
      );
    } else if (type == 'calculated') {
      editor = TextFormField(
        initialValue: current?.toString() ?? '',
        readOnly: true,
        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'يُحسب تلقائياً عند توفر الحقول المرتبطة'),
      );
    } else if (['long_text','textarea','notes','decision_notes'].contains(type)) {
      editor = TextFormField(
        initialValue: current?.toString() ?? '',
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'اكتب التفاصيل هنا'),
        onChanged: (value) => _values[key] = value,
      );
    } else {
      editor = TextFormField(
        initialValue: current?.toString() ?? '',
        keyboardType: ['number','integer','decimal','percentage','quantity','money','progress'].contains(type)
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: validation['min'] != null || validation['max'] != null
              ? 'الحدود: ${validation['min'] ?? '—'} إلى ${validation['max'] ?? '—'}'
              : 'أدخل ${label}',
        ),
        onChanged: (value) => _values[key] = value,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label${field['required'] == true ? ' *' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (description.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 7),
            child: Text(description, style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12)),
          ),
          const SizedBox(height: 7),
          editor,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.snapshot['title']?.toString() ?? 'تقرير المهمة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('أكمل الحقول والجداول كما صممتها الإدارة.',
              style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ..._fields.map(_field),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('إرسال التقرير للمراجعة'),
          ),
        ],
      ),
    ),
  );
}

class _DynamicTableEditor extends StatelessWidget {
  const _DynamicTableEditor({
    required this.columns,
    required this.rows,
    required this.minRows,
    required this.maxRows,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> columns;
  final List<Map<String, dynamic>> rows;
  final int minRows;
  final int maxRows;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (columns.isEmpty) return const Text('لم تُحدد أعمدة هذا الجدول في المصمم.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows.asMap().entries.map((entry) => Card(
          elevation: 0,
          color: const Color(0xFFF4F6F9),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(children: [
                  Text('صف ${entry.key + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    onPressed: rows.length > minRows
                        ? () => onChanged(rows.where((row) => !identical(row, entry.value)).toList())
                        : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]),
                ...columns.map((column) {
                  final key = (column['key'] ?? column['label'] ?? 'value').toString();
                  final label = (column['label'] ?? key).toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextFormField(
                      initialValue: entry.value[key]?.toString() ?? '',
                      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
                      onChanged: (value) {
                        final next = rows.map((row) => Map<String, dynamic>.from(row)).toList();
                        next[entry.key][key] = value;
                        onChanged(next);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        )),
        OutlinedButton.icon(
          onPressed: rows.length < maxRows
              ? () => onChanged([...rows, {for (final column in columns) (column['key'] ?? column['label'] ?? 'value').toString(): ''}])
              : null,
          icon: const Icon(Icons.add),
          label: Text('إضافة صف (الحد الأدنى $minRows)'),
        ),
      ],
    );
  }
}

class TaskDesignerScreen extends StatefulWidget {
  const TaskDesignerScreen({super.key, required this.profile});
  final Map<String, dynamic> profile;

  @override
  State<TaskDesignerScreen> createState() => _TaskDesignerScreenState();
}

class _TaskDesignerScreenState extends State<TaskDesignerScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _instructions = TextEditingController();
  final List<Map<String, dynamic>> _fields = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _templates = [];
  String _role = 'accountant';
  String _priority = 'normal';
  String? _categoryId;
  bool _busy = false;
  String? _error;

  SupabaseClient get _db => Supabase.instance.client;
  String get _org => widget.profile['institutionId'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final categories = await _db.from('task_categories')
          .select('id,code,title,is_main,parent_id')
          .eq('organization_id', _org).eq('active', true).eq('is_main', true)
          .order('title');
      final templates = await _db.from('task_templates')
          .select('id,title,role_code,default_priority,is_active,version')
          .eq('organization_id', _org).order('updated_at', ascending: false).limit(100);
      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(categories);
        _templates = List<Map<String, dynamic>>.from(templates);
        _categoryId ??= _categories.isEmpty ? null : _categories.first['id'].toString();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addField() async {
    final labelController = TextEditingController();
    final keyController = TextEditingController();
    final optionsController = TextEditingController();
    String type = 'text';
    bool required = false;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('إضافة حقل للتقرير'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: labelController, decoration: const InputDecoration(labelText: 'اسم الحقل')),
              TextField(controller: keyController, decoration: const InputDecoration(labelText: 'المفتاح بالإنجليزية (مثال sales_total)')),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'نوع الحقل'),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('نص قصير')),
                  DropdownMenuItem(value: 'textarea', child: Text('نص طويل')),
                  DropdownMenuItem(value: 'number', child: Text('رقم / كمية')),
                  DropdownMenuItem(value: 'money', child: Text('مبلغ مالي')),
                  DropdownMenuItem(value: 'date', child: Text('تاريخ')),
                  DropdownMenuItem(value: 'select', child: Text('اختيار من قائمة')),
                  DropdownMenuItem(value: 'multiselect', child: Text('اختيار متعدد')),
                  DropdownMenuItem(value: 'boolean', child: Text('نعم / لا')),
                  DropdownMenuItem(value: 'table', child: Text('جدول بيانات')),
                ],
                onChanged: (value) => refresh(() => type = value ?? 'text'),
              ),
              if (type == 'select' || type == 'multiselect')
                TextField(controller: optionsController, decoration: const InputDecoration(labelText: 'الخيارات مفصولة بفاصلة')),
              CheckboxListTile(
                value: required,
                contentPadding: EdgeInsets.zero,
                title: const Text('حقل إلزامي'),
                onChanged: (value) => refresh(() => required = value ?? false),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final label = labelController.text.trim();
                final key = keyController.text.trim().toLowerCase();
                if (label.isEmpty || !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(key)) return;
                Navigator.pop(dialogContext, {
                  'field_key': key, 'label': label, 'field_type': type,
                  'is_required': required, 'options': (type == 'select' || type == 'multiselect')
                      ? optionsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
                      : <String>[],
                  'description': '', 'repeatable': false, 'validation': <String, dynamic>{},
                  'config': type == 'table'
                      ? {'columns': [{'key': 'item', 'label': 'البيان', 'type': 'short_text', 'required': true}, {'key': 'quantity', 'label': 'الكمية', 'type': 'quantity'}], 'min_rows': 0, 'max_rows': 100}
                      : <String, dynamic>{},
                });
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    labelController.dispose();
    keyController.dispose();
    optionsController.dispose();
    if (result != null && mounted) setState(() => _fields.add(result));
  }

  Future<void> _saveAndAssign() async {
    if (_title.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب عنوان المهمة أولاً.')));
      return;
    }
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد فئة مهمة نشطة في قاعدة البيانات.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'instructions': _instructions.text.trim(),
        'role_code': _role,
        'task_type': 'operational',
        'default_priority': _priority,
        'category_id': _categoryId,
        'is_active': true,
        'steps': <Map<String, dynamic>>[],
        'report_fields': _fields.asMap().entries.map((entry) => {
          ...entry.value,
          'sort_order': entry.key,
        }).toList(),
      };
      final templateId = await _db.rpc('save_task_designer_template', params: {
        'p_organization_id': _org,
        'p_template_id': null,
        'p_payload': payload,
      }) as String;
      if (!mounted) return;
      await _assignTemplate(templateId, _role);
      await _load();
      _title.clear();
      _description.clear();
      _instructions.clear();
      setState(() => _fields.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ قالب المهمة وإسناده للموظف.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assignTemplate(String templateId, String roleCode) async {
    final memberships = await _db.from('organization_memberships')
        .select('id,user_id,display_name,employee_no')
        .eq('organization_id', _org).eq('is_active', true)
        .order('display_name');
    final rows = List<Map<String, dynamic>>.from(memberships);
    final assignments = await _db.from('role_assignments')
        .select('membership_id,role_code,branch_id')
        .eq('organization_id', _org).eq('role_code', roleCode);
    final matching = assignments.map((e) => e['membership_id'].toString()).toSet();
    final eligible = rows.where((row) => matching.contains(row['id'].toString())).toList();
    if (eligible.isEmpty) throw Exception('no_employee_for_role_branch');
    if (!mounted) return;
    String selectedUser = eligible.first['user_id'].toString();
    String? branchId;
    final branches = await _db.from('branches')
        .select('id,name').eq('organization_id', _org).eq('is_active', true).order('name');
    final branchRows = List<Map<String, dynamic>>.from(branches);
    if (!mounted) return;
    final choice = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('إسناد المهمة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: selectedUser,
              decoration: const InputDecoration(labelText: 'الموظف'),
              items: eligible.map((employee) => DropdownMenuItem(
                value: employee['user_id'].toString(),
                child: Text('${employee['display_name'] ?? 'موظف'} — ${employee['employee_no'] ?? ''}'),
              )).toList(),
              onChanged: (value) => refresh(() => selectedUser = value ?? selectedUser),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: branchId,
              decoration: const InputDecoration(labelText: 'الفرع (اختياري)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('كل الفروع / دون تحديد')),
                ...branchRows.map((branch) => DropdownMenuItem<String?>(
                  value: branch['id'].toString(), child: Text(branch['name'].toString()),
                )),
              ],
              onChanged: (value) => refresh(() => branchId = value),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, {'user': selectedUser, 'branch': branchId}), child: const Text('إرسال المهمة')),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final now = DateTime.now();
    final starts = DateTime(now.year, now.month, now.day);
    final due = starts.add(const Duration(days: 1));
    await _db.rpc('assign_task_from_template', params: {
      'p_organization_id': _org,
      'p_template_id': templateId,
      'p_assigned_to': choice['user'],
      'p_branch_id': choice['branch'],
      'p_starts_at': starts.toUtc().toIso8601String(),
      'p_due_at': due.toUtc().toIso8601String(),
      'p_priority': _priority,
      'p_instructions': null,
      'p_report_overrides': [],
      'p_idempotency_key': 'flutter-task:$templateId:${DateTime.now().microsecondsSinceEpoch}',
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('مصمم المهام')),
      body: _busy && _templates.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) _InfoCard(text: _error!),
                const Text('إنشاء مهمة جديدة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(controller: _title, decoration: const InputDecoration(labelText: 'عنوان المهمة')),
                const SizedBox(height: 10),
                TextField(controller: _description, decoration: const InputDecoration(labelText: 'وصف مختصر')),
                const SizedBox(height: 10),
                TextField(controller: _instructions, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'تعليمات التنفيذ')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'التصنيف الوظيفي المستهدف'),
                  items: _roleNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (value) => setState(() => _role = value ?? _role),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _priority,
                  decoration: const InputDecoration(labelText: 'الأولوية'),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('عادية')),
                    DropdownMenuItem(value: 'important', child: Text('مهمة')),
                    DropdownMenuItem(value: 'urgent', child: Text('عاجلة')),
                    DropdownMenuItem(value: 'critical', child: Text('حرجة')),
                  ],
                  onChanged: (value) => setState(() => _priority = value ?? 'normal'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  decoration: const InputDecoration(labelText: 'تصنيف المهمة'),
                  items: _categories.map((category) => DropdownMenuItem(
                    value: category['id'].toString(), child: Text(category['title'].toString()),
                  )).toList(),
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  const Expanded(child: Text('حقول تقرير الموظف', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  OutlinedButton.icon(onPressed: _addField, icon: const Icon(Icons.add), label: const Text('إضافة حقل')),
                ]),
                if (_fields.isEmpty) const _InfoCard(text: 'أضف حقول التقرير. ستظهر للموظف بنفس ترتيبها عند فتح المهمة.'),
                ..._fields.asMap().entries.map((entry) => Card(
                  elevation: 0,
                  child: ListTile(
                    title: Text(entry.value['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${entry.value['field_type']} · ${entry.value['is_required'] == true ? 'إلزامي' : 'اختياري'}'),
                    trailing: IconButton(
                      onPressed: () => setState(() => _fields.removeAt(entry.key)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                )),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _saveAndAssign,
                  child: _busy ? const CircularProgressIndicator(color: Colors.white) : const Text('حفظ القالب وإسناد المهمة'),
                ),
                const Divider(height: 36),
                const Text('قوالب المهام المحفوظة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ..._templates.map((template) => Card(
                  elevation: 0,
                  child: ListTile(
                    title: Text(template['title'].toString()),
                    subtitle: Text('${_roleNames[template['role_code']] ?? template['role_code']} · الإصدار ${template['version']}'),
                    trailing: Icon(template['is_active'] == true ? Icons.check_circle_outline : Icons.pause_circle_outline),
                  ),
                )),
              ],
            ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: const Color(0xFFEAF0F5),
    child: Padding(padding: const EdgeInsets.all(14), child: Text(text)),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 42),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ]),
    ),
  );
}

String _date(String raw) {
  final date = DateTime.tryParse(raw)?.toLocal();
  if (date == null) return raw;
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('permission_denied') || message.contains('42501')) return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
  if (message.contains('no_employee_for_role_branch')) return 'لا يوجد موظف نشط مرتبط بهذا الدور في الفرع المحدد.';
  if (message.contains('task_template_not_found')) return 'قالب المهمة غير موجود أو غير نشط.';
  if (message.contains('PGRST202') || message.contains('42883')) return 'تحديث Supabase المطلوب غير متاح في قاعدة البيانات المتصلة.';
  if (message.contains('network') || message.contains('SocketException')) return 'تعذر الاتصال بالشبكة. تحقق من الإنترنت.';
  return 'تعذر إكمال العملية. راجع البيانات والصلاحيات ثم حاول مجدداً.';
}
