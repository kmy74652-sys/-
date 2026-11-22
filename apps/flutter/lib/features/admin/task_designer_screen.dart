import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';

class TaskDesignerScreen extends StatefulWidget {
  const TaskDesignerScreen({super.key});
  @override
  State<TaskDesignerScreen> createState() => _TaskDesignerScreenState();
}

class _TaskDesignerScreenState extends State<TaskDesignerScreen> {
  final _db = Supabase.instance.client;
  String? _orgId;
  bool _loading = true, _saving = false, _editing = false;
  String? _error;
  List<Map<String, dynamic>> _templates = [],
      _categories = [],
      _roles = [],
      _steps = [],
      _reportFields = [];
  String? _templateId, _categoryId, _subcategoryId, _roleCode;
  String _priority = 'normal';
  bool _active = true;
  final _title = TextEditingController(),
      _description = TextEditingController(),
      _instructions = TextEditingController(),
      _duration = TextEditingController();

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
    _duration.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : <Map<String, dynamic>>[];
  String _str(dynamic value, [String fallback = '']) =>
      value == null ? fallback : value.toString();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _db.auth.currentUser;
      if (user == null) throw Exception('يرجى تسجيل الدخول أولاً.');
      final memberships = _rows(
        await _db
            .from('organization_memberships')
            .select('organization_id,created_at')
            .eq('user_id', user.id)
            .eq('is_active', true)
            .order('created_at')
            .limit(100),
      );
      String? org;
      for (final membership in memberships) {
        final candidate = _str(membership['organization_id']);
        final allowed = await _db.rpc(
          'task_library_allowed_for_org',
          params: {
            'p_organization_id': candidate,
            'p_required_permission': 'task_library.manage',
          },
        );
        if (allowed == true) {
          org = candidate;
          break;
        }
      }
      if (org == null)
        throw Exception('لا توجد مؤسسة نشطة تملك صلاحية إدارة مكتبة المهام.');
      final results = await Future.wait<dynamic>([
        _db
            .from('task_categories')
            .select('id,code,title,parent_id,is_main,active')
            .eq('organization_id', org)
            .eq('active', true)
            .order('title')
            .limit(500),
        _db
            .from('roles')
            .select('code,name_ar')
            .order('name_ar')
            .limit(200),
        _db
            .from('task_templates')
            .select(
              'id,title,description,role_code,task_type,default_priority,category_id,subcategory_id,instructions,default_duration_minutes,is_active,version',
            )
            .eq('organization_id', org)
            .order('title')
            .limit(300),
      ]);
      if (!mounted) return;
      setState(() {
        _orgId = org;
        _categories = _rows(results[0]);
        _roles = _rows(results[1]);
        _templates = _rows(results[2]);
      });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic>? row) async {
    if (row == null) {
      setState(() {
        _editing = true;
        _templateId = null;
        _title.clear();
        _description.clear();
        _instructions.clear();
        _duration.clear();
        _categoryId = null;
        _subcategoryId = null;
        _roleCode = _roles.isEmpty ? null : _str(_roles.first['code']);
        _priority = 'normal';
        _active = true;
        _steps = [];
        _reportFields = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = _str(row['id']);
      final values = await Future.wait<dynamic>([
        _db
            .from('task_template_steps')
            .select(
              'title,instructions,sort_order,is_required,evidence_required,evidence_instructions',
            )
            .eq('template_id', id)
            .order('sort_order')
            .limit(300),
        _db
            .from('task_template_report_fields')
            .select('field_key,label,field_type,is_required,options,sort_order,description,repeatable,validation,config')
            .eq('template_id', id)
            .order('sort_order')
            .limit(300),
      ]);
      if (!mounted) return;
      setState(() {
        _templateId = id;
        _title.text = _str(row['title']);
        _description.text = _str(row['description']);
        _instructions.text = _str(row['instructions']);
        _duration.text = _str(row['default_duration_minutes']);
        _categoryId = _nullable(row['category_id']);
        _subcategoryId = _nullable(row['subcategory_id']);
        _roleCode = _str(row['role_code']);
        _priority = _str(row['default_priority'], 'normal');
        _active = row['is_active'] != false;
        _steps = _rows(values[0])
            .map(
              (s) => {
                ...s,
                'title': _str(s['title']),
                'instructions': _str(s['instructions']),
                'evidence_instructions': _str(s['evidence_instructions']),
              },
            )
            .toList();
        _reportFields = _rows(values[1]);
        _editing = true;
      });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _nullable(dynamic value) => value == null ? null : value.toString();
  List<Map<String, dynamic>> get _mainCategories => _categories
      .where((c) => c['parent_id'] == null && c['is_main'] == true)
      .toList();
  List<Map<String, dynamic>> get _subcategories =>
      _categories.where((c) => _str(c['parent_id']) == _categoryId).toList();

  Future<void> _save() async {
    if (_title.text.trim().length < 2) {
      _message('أدخل عنواناً صالحاً للقالب (حرفان على الأقل).');
      return;
    }
    if (_steps.any((s) => _str(s['title']).trim().isEmpty)) {
      _message('أدخل عنواناً لكل خطوة أو احذف الخطوة الفارغة.');
      return;
    }
    if (_reportFields.any((f) {
      final key = _str(f['field_key']).trim();
      final label = _str(f['label']).trim();
      return label.isEmpty || !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(key);
    })) {
      _message('أدخل اسم كل بند ومفتاحاً يبدأ بحرف إنجليزي ويحتوي a-z أو _.');
      return;
    }
    if (_roleCode == null || _orgId == null) {
      _message('اختر دوراً مسؤولاً.');
      return;
    }
    final mins = int.tryParse(_duration.text.trim());
    if (_duration.text.trim().isNotEmpty &&
        (mins == null || mins < 1 || mins > 10080)) {
      _message('المدة يجب أن تكون بين 1 و10080 دقيقة.');
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'role_code': _roleCode,
        'task_type': 'operational',
        'default_priority': _priority,
        'category_id': _categoryId,
        'subcategory_id': _subcategoryId,
        'instructions': _instructions.text.trim().isEmpty
            ? null
            : _instructions.text.trim(),
        'default_duration_minutes': mins,
        'is_active': _active,
        'steps': _steps
            .asMap()
            .entries
            .map(
              (entry) => <String, dynamic>{
                'title': _str(entry.value['title']).trim(),
                'instructions': _str(entry.value['instructions']).trim().isEmpty
                    ? null
                    : _str(entry.value['instructions']).trim(),
                'sort_order': entry.key,
                'is_required': entry.value['is_required'] == true,
                'evidence_required': entry.value['evidence_required'] == true,
                'evidence_instructions':
                    entry.value['evidence_required'] == true &&
                        _str(entry.value['evidence_instructions'])
                            .trim()
                            .isNotEmpty
                    ? _str(entry.value['evidence_instructions']).trim()
                    : null,
              },
            )
            .toList(),
        'report_fields': _reportFields
            .asMap()
            .entries
            .map(
              (entry) => <String, dynamic>{
                'field_key': _str(entry.value['field_key']).trim(),
                'label': _str(entry.value['label']).trim(),
                'field_type': _str(entry.value['field_type'], 'text'),
                'is_required': entry.value['is_required'] == true,
                'sort_order': entry.key,
                'description': _str(entry.value['description']).trim().isEmpty
                    ? null
                    : _str(entry.value['description']).trim(),
                'repeatable': entry.value['repeatable'] == true,
                'options': entry.value['options'] is List
                    ? entry.value['options']
                    : <dynamic>[],
                'validation': entry.value['validation'] is Map
                    ? entry.value['validation']
                    : <String, dynamic>{},
                'config': entry.value['config'] is Map
                    ? entry.value['config']
                    : <String, dynamic>{},
              },
            )
            .toList(),
      };
      await _db.rpc(
        'save_task_designer_template',
        params: {
          'p_organization_id': _orgId,
          'p_template_id': _templateId,
          'p_payload': payload,
        },
      );
      if (!mounted) return;
      _message('تم حفظ قالب المهمة.');
      await _load();
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text, textAlign: TextAlign.right)));
  }

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'مصمم قوالب المهام',
    subtitle: 'إعداد الخطوات وربط نماذج التقارير',
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: _loading && _orgId == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (_error != null)
                    SectionCard(
                      title: 'تعذر إكمال العملية',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(_error!, textAlign: TextAlign.right),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  if (_loading) const LinearProgressIndicator(),
                  if (!_editing) ...[
                    SectionCard(
                      title: 'مكتبة قوالب المهام',
                      trailing: IconButton(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'تحديث',
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: _roles.isEmpty
                                ? null
                                : () => _edit(null),
                            icon: const Icon(Icons.add),
                            label: const Text('إنشاء قالب'),
                          ),
                          const SizedBox(height: 8),
                          if (_templates.isEmpty)
                            const Text(
                              'لا توجد قوالب بعد.',
                              textAlign: TextAlign.right,
                            )
                          else
                            ..._templates.map(
                              (t) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  _str(t['title']),
                                  textAlign: TextAlign.right,
                                ),
                                subtitle: Text(
                                  '${_roleTitle(_str(t['role_code']))} · ${t['is_active'] == true ? 'نشط' : 'مؤرشف'}',
                                  textAlign: TextAlign.right,
                                ),
                                leading: const Icon(Icons.edit_outlined),
                                onTap: () => _edit(t),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else
                    ..._editor(),
                ],
              ),
            ),
    ),
  );

  List<Widget> _editor() => [
    SectionCard(
      title: _templateId == null ? 'إنشاء قالب مهمة' : 'تحرير قالب المهمة',
      trailing: TextButton(
        onPressed: () => setState(() => _editing = false),
        child: const Text('رجوع'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(labelText: 'عنوان القالب *'),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _description,
            textAlign: TextAlign.right,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'الوصف'),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _instructions,
            textAlign: TextAlign.right,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'تعليمات التنفيذ'),
          ),
          const SizedBox(height: 12),
          _dropdown<String>(
            'الدور المسؤول',
            _roleCode,
            _roles
                .map(
                  (r) => DropdownMenuItem(
                    value: _str(r['code']),
                    child: Text(
                      _str(r['title'], _str(r['name_ar'], _str(r['code']))),
                    ),
                  ),
                )
                .toList(),
            (v) => setState(() {
              _roleCode = v;
            }),
          ),
          const SizedBox(height: 10),
          _dropdown<String>(
            'التصنيف',
            _categoryId,
            [
              const DropdownMenuItem(value: null, child: Text('بدون تصنيف')),
              ..._mainCategories.map(
                (c) => DropdownMenuItem(
                  value: _str(c['id']),
                  child: Text(_str(c['title'])),
                ),
              ),
            ],
            (v) => setState(() {
              _categoryId = v;
              _subcategoryId = null;
            }),
          ),
          if (_categoryId != null) ...[
            const SizedBox(height: 10),
            _dropdown<String>('التصنيف الفرعي', _subcategoryId, [
              const DropdownMenuItem(
                value: null,
                child: Text('بدون تصنيف فرعي'),
              ),
              ..._subcategories.map(
                (c) => DropdownMenuItem(
                  value: _str(c['id']),
                  child: Text(_str(c['title'])),
                ),
              ),
            ], (v) => setState(() => _subcategoryId = v)),
          ],
          const SizedBox(height: 10),
          _dropdown<String>('الأولوية الافتراضية', _priority, const [
            DropdownMenuItem(value: 'normal', child: Text('عادية')),
            DropdownMenuItem(value: 'important', child: Text('مهمة')),
            DropdownMenuItem(value: 'urgent', child: Text('عاجلة')),
            DropdownMenuItem(value: 'critical', child: Text('حرجة')),
          ], (v) => setState(() => _priority = v ?? 'normal')),
          const SizedBox(height: 10),
          TextField(
            controller: _duration,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'المدة بالدقائق (اختياري)',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _active ? 'القالب نشط' : 'القالب مؤرشف',
              textAlign: TextAlign.right,
            ),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ],
      ),
    ),
    SectionCard(
      title: 'جدول خطوات التنفيذ',
      trailing: FilledButton.icon(
        onPressed: _addStep,
        icon: const Icon(Icons.add),
        label: const Text('إضافة صف'),
      ),
      child: _steps.isEmpty
          ? const Text(
              'أضف صفًا لكل خطوة. ستُنقل الصفوف نفسها إلى تنفيذ المهمة بالترتيب الظاهر هنا.',
              textAlign: TextAlign.right,
            )
          : _stepsGrid(),
    ),
    SectionCard(
      title: 'مصمم التقرير الديناميكي',
      trailing: FilledButton.icon(
        onPressed: _addReportField,
        icon: const Icon(Icons.add),
        label: const Text('إضافة حقل'),
      ),
      child: _reportFields.isEmpty
          ? const Text(
              'أضف بنود التقرير كحقول مستقلة. ستظهر للموظف كحقول إدخال منظمة، ويمكن تكرارها كسجلات جدول.',
              textAlign: TextAlign.right,
            )
          : Column(
              children: [
              const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'صمّم التقرير من نفس الشاشة. اختر «جدول متعدد الصفوف» لإضافة أعمدة وصفوف التقرير وحفظها مع القالب.',
                    style: TextStyle(fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _reportFields.length; i++)
                  _reportFieldEditor(i),
              ],
            ),
    ),
    const SizedBox(height: 8),
    FilledButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_outlined),
      label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ القالب'),
    ),
  ];

  void _addStep() => setState(() => _steps.add({
        'title': '',
        'instructions': '',
        'is_required': true,
        'evidence_required': false,
        'evidence_instructions': '',
      }));

  void _addReportField() => setState(() => _reportFields.add({
        'field_key': 'field_${_reportFields.length + 1}',
        'label': '',
        'field_type': 'short_text',
        'is_required': false,
        'repeatable': false,
        'options': <dynamic>[],
        'config': <String, dynamic>{},
      }));

  Widget _stepsGrid() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            AppColors.navy.withOpacity(.08),
          ),
          columnSpacing: 18,
          dataRowMinHeight: 72,
          dataRowMaxHeight: 180,
          columns: const [
            DataColumn(label: Text('رقم')),
            DataColumn(label: Text('عنوان الخطوة *')),
            DataColumn(label: Text('وصف التنفيذ')),
            DataColumn(label: Text('إلزامية')),
            DataColumn(label: Text('إثبات')),
            DataColumn(label: Text('إجراءات')),
          ],
          rows: [
            for (var i = 0; i < _steps.length; i++) _stepRow(i),
          ],
        ),
      );

  DataRow _stepRow(int index) {
    final step = _steps[index];
    return DataRow(cells: [
      DataCell(Text('${index + 1}')),
      DataCell(SizedBox(
        width: 190,
        child: TextFormField(
          key: ValueKey('step_title_$index'),
          initialValue: _str(step['title']),
          textAlign: TextAlign.right,
          decoration: const InputDecoration(labelText: 'العنوان'),
          onChanged: (v) => step['title'] = v,
        ),
      )),
      DataCell(SizedBox(
        width: 250,
        child: TextFormField(
          key: ValueKey('step_instructions_$index'),
          initialValue: _str(step['instructions']),
          textAlign: TextAlign.right,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'التعليمات'),
          onChanged: (v) => step['instructions'] = v,
        ),
      )),
      DataCell(Checkbox(
        value: step['is_required'] == true,
        onChanged: (v) => setState(() => step['is_required'] = v == true),
      )),
      DataCell(Checkbox(
        value: step['evidence_required'] == true,
        onChanged: (v) => setState(() => step['evidence_required'] = v == true),
      )),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'نقل لأعلى',
          onPressed: index == 0 ? null : () => setState(() {
            final item = _steps.removeAt(index);
            _steps.insert(index - 1, item);
          }),
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          tooltip: 'نقل لأسفل',
          onPressed: index == _steps.length - 1 ? null : () => setState(() {
            final item = _steps.removeAt(index);
            _steps.insert(index + 1, item);
          }),
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        IconButton(
          tooltip: 'حذف الصف من المسودة',
          onPressed: () => setState(() => _steps.removeAt(index)),
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
      ])),
    ]);
  }

  Widget _reportFieldEditor(int index) {
    final field = _reportFields[index];
    return Card(
      color: AppColors.canvas,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('بند التقرير ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => setState(() => _reportFields.removeAt(index)),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'حذف البند',
                ),
              ],
            ),
            TextFormField(
              initialValue: _str(field['field_key']),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'المفتاح البرمجي *'),
              onChanged: (v) => field['field_key'] = v.trim().toLowerCase(),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _str(field['label']),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'اسم البند الظاهر *'),
              onChanged: (v) => field['label'] = v,
            ),
            const SizedBox(height: 8),
            _dropdown<String>(
              'نوع الحقل',
              _str(field['field_type'], 'text'),
              const [
                DropdownMenuItem(value: 'text', child: Text('نص قصير')),
                DropdownMenuItem(value: 'short_text', child: Text('نص قصير')),
                DropdownMenuItem(value: 'long_text', child: Text('نص طويل')),
                DropdownMenuItem(value: 'number', child: Text('رقم')),
                DropdownMenuItem(value: 'date', child: Text('تاريخ')),
                DropdownMenuItem(value: 'select', child: Text('اختيار')),
                DropdownMenuItem(value: 'multi_select', child: Text('اختيارات متعددة')),
                DropdownMenuItem(value: 'attachment', child: Text('مرفق / صورة')),
                DropdownMenuItem(value: 'table', child: Text('جدول متعدد الصفوف')),
              ],
              (v) => setState(() => field['field_type'] = v ?? 'text'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('البند إلزامي', textAlign: TextAlign.right),
              value: field['is_required'] == true,
              onChanged: (v) => setState(() => field['is_required'] = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('سجلات متكررة (عرض جدولي)', textAlign: TextAlign.right),
              subtitle: const Text('فعّلها للدوام أو المصروفات أو الحضور المتعدد.', textAlign: TextAlign.right),
              value: field['repeatable'] == true,
              onChanged: (v) => setState(() => field['repeatable'] = v),
            ),
            TextFormField(
              initialValue: _str(field['description']),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'شرح البند (اختياري)'),
              onChanged: (v) => field['description'] = v,
            ),
            if (field['field_type'] == 'table') _taskTableColumnsEditor(index),
          ],
        ),
      ),
    );
  }

  Widget _taskTableColumnsEditor(int index) {
    final field = _reportFields[index];
    final raw = field['config'] is Map
        ? (field['config'] as Map)['columns']
        : null;
    final columns = raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    void update(List<Map<String, dynamic>> next) {
      setState(() => field['config'] = {
        ...(field['config'] is Map
            ? Map<String, dynamic>.from(field['config'] as Map)
            : <String, dynamic>{}),
        'columns': next,
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'أعمدة الجدول',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: () => update([
                ...columns,
                {
                  'key': 'column_${columns.length + 1}',
                  'label': 'عمود ${columns.length + 1}',
                  'type': 'short_text',
                  'required': false,
                  'options': <String>[],
                },
              ]),
              icon: const Icon(Icons.view_column_outlined),
              label: const Text('إضافة عمود'),
            ),
          ],
        ),
        if (columns.isEmpty)
          const Text(
            'أضف أعمدة الجدول التي سيملؤها الموظف.',
            textAlign: TextAlign.right,
          ),
        for (var j = 0; j < columns.length; j++)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('task_table_label_${index}_$j'),
                      initialValue: _str(columns[j]['label']),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: 'اسم العمود'),
                      onChanged: (v) {
                        final next = [...columns];
                        next[j] = {...next[j], 'label': v};
                        update(next);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('task_table_key_${index}_$j'),
                      initialValue: _str(columns[j]['key']),
                      textAlign: TextAlign.left,
                      decoration: const InputDecoration(labelText: 'المفتاح الإنجليزي'),
                      onChanged: (v) {
                        final next = [...columns];
                        next[j] = {...next[j], 'key': v.trim().toLowerCase()};
                        update(next);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'إزالة العمود',
                    onPressed: () => update([
                      for (var k = 0; k < columns.length; k++)
                        if (k != j) columns[k],
                    ]),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _dropdown<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
  ) => DropdownButtonFormField<T>(
    value: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: items,
    onChanged: onChanged,
  );
  String _roleTitle(String code) {
    for (final r in _roles) {
      if (_str(r['code']) == code) return _str(r['title'], code);
    }
    return code;
  }
}
