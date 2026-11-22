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
      _forms = [],
      _steps = [],
      _links = [];
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
            .select('institution_id,code,title')
            .eq('institution_id', org)
            .order('title')
            .limit(200),
        _db.rpc(
          'list_task_library_report_forms',
          params: {'p_organization_id': org},
        ),
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
        _forms = _rows(results[2]);
        _templates = _rows(results[3]);
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
        _links = [];
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
            .from('task_template_report_forms')
            .select('version_id,sort_order,is_required')
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
        _links = _rows(values[1])
            .map(
              (f) => {
                'version_id': _str(f['version_id']),
                'required': f['is_required'] == true,
              },
            )
            .toList();
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
        'report_forms': _links
            .asMap()
            .entries
            .map(
              (entry) => <String, dynamic>{
                'version_id': entry.value['version_id'],
                'sort_order': entry.key,
                'required': entry.value['required'] == true,
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

  void _toggleForm(String versionId, bool checked) {
    setState(() {
      final index = _links.indexWhere((e) => e['version_id'] == versionId);
      if (checked && index < 0)
        _links.add({'version_id': versionId, 'required': true});
      if (!checked && index >= 0) _links.removeAt(index);
    });
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
                    child: Text(_str(r['title'], _str(r['code']))),
                  ),
                )
                .toList(),
            (v) => setState(() {
              _roleCode = v;
              _links.clear();
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
      title: 'خطوات التنفيذ',
      trailing: IconButton(
        onPressed: () => setState(
          () => _steps.add({
            'title': '',
            'instructions': '',
            'is_required': true,
            'evidence_required': false,
            'evidence_instructions': '',
          }),
        ),
        icon: const Icon(Icons.add_circle_outline),
        tooltip: 'إضافة خطوة',
      ),
      child: _steps.isEmpty
          ? const Text(
              'أضف الخطوات بالترتيب المطلوب.',
              textAlign: TextAlign.right,
            )
          : Column(
              children: [
                for (var i = 0; i < _steps.length; i++) _stepEditor(i),
              ],
            ),
    ),
    SectionCard(
      title: 'نماذج التقارير المعتمدة',
      child: _forms.isEmpty
          ? const Text(
              'لا توجد نماذج تقارير معتمدة متاحة لهذا الدور.',
              textAlign: TextAlign.right,
            )
          : Column(
              children: _forms.where((f) => _str(f['role_code']) == _roleCode).map((
                form,
              ) {
                final version = _str(form['approved_version_id']);
                final index = _links.indexWhere(
                  (e) => e['version_id'] == version,
                );
                final selected = index >= 0;
                return Column(
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        '${_str(form['title'])} · إصدار ${_str(form['approved_version_no'])}',
                        textAlign: TextAlign.right,
                      ),
                      subtitle: Text(
                        _str(form['description']),
                        textAlign: TextAlign.right,
                      ),
                      value: selected,
                      onChanged: (v) => _toggleForm(version, v == true),
                    ),
                    if (selected)
                      SwitchListTile(
                        contentPadding: const EdgeInsets.only(right: 24),
                        title: const Text(
                          'التقرير مطلوب',
                          textAlign: TextAlign.right,
                        ),
                        value: _links[index]['required'] == true,
                        onChanged: (v) =>
                            setState(() => _links[index]['required'] = v),
                      ),
                  ],
                );
              }).toList(),
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

  Widget _stepEditor(int index) {
    final step = _steps[index];
    return Card(
      color: AppColors.canvas,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الخطوة ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: index == 0
                      ? null
                      : () => setState(() {
                          final item = _steps.removeAt(index);
                          _steps.insert(index - 1, item);
                        }),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  onPressed: index == _steps.length - 1
                      ? null
                      : () => setState(() {
                          final item = _steps.removeAt(index);
                          _steps.insert(index + 1, item);
                        }),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  onPressed: () => setState(() => _steps.removeAt(index)),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            TextFormField(
              initialValue: _str(step['title']),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'عنوان الخطوة *'),
              onChanged: (v) => step['title'] = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _str(step['instructions']),
              textAlign: TextAlign.right,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'تعليمات الخطوة'),
              onChanged: (v) => step['instructions'] = v,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الخطوة إلزامية', textAlign: TextAlign.right),
              value: step['is_required'] == true,
              onChanged: (v) => setState(() => step['is_required'] = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تتطلب إثباتاً', textAlign: TextAlign.right),
              value: step['evidence_required'] == true,
              onChanged: (v) => setState(() => step['evidence_required'] = v),
            ),
            if (step['evidence_required'] == true)
              TextFormField(
                initialValue: _str(step['evidence_instructions']),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'تعليمات الإثبات'),
                onChanged: (v) => step['evidence_instructions'] = v,
              ),
          ],
        ),
      ),
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
