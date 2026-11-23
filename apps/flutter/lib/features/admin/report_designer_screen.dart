import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';

class ReportDesignerScreen extends StatefulWidget {
  const ReportDesignerScreen({super.key});
  @override
  State<ReportDesignerScreen> createState() => _ReportDesignerScreenState();
}

class _ReportDesignerScreenState extends State<ReportDesignerScreen> {
  final _db = Supabase.instance.client;
  bool _busy = false,
      _loading = true,
      _required = true,
      _editing = false,
      _dirty = false;
  String? _error, _notice, _templateId, _versionId, _orgId;
  String _status = 'draft',
      _title = '',
      _description = '',
      _role = 'admin_followup';
  List<Map<String, dynamic>> _templates = [], _fields = [], _employees = [];
  int? _selected;

  static const _roles = <String, String>{
    'owner': 'صاحب المؤسسة',
    'admin_followup': 'المدير التنفيذي',
    'accountant': 'المحاسب',
    'warehouse_keeper': 'أمين المخازن',
    'warehouse_worker': 'عمال التحميل',
  };
  static const _types = <String, String>{
    'short_text': 'نص قصير',
    'long_text': 'نص طويل وملاحظات',
    'integer': 'رقم صحيح',
    'quantity': 'كمية ووحدة قياس',
    'money': 'مبلغ وعملة',
    'decimal': 'رقم عشري',
    'percentage': 'نسبة مئوية',
    'datetime': 'تاريخ ووقت تلقائي',
    'date_range': 'نطاق تاريخ / فترة',
    'system_reference': 'مرجع من النظام',
    'barcode': 'باركود / رمز صنف',
    'select': 'قائمة اختيار',
    'multiselect': 'اختيار متعدد',
    'boolean': 'نعم أو لا',
    'table': 'جدول متعدد الصفوف',
    'image': 'صورة',
    'multi_image': 'صور متعددة',
    'file': 'ملف أو مستند',
    'signature': 'توقيع أو إقرار',
    'calculated': 'حقل محسوب',
    'decision_notes': 'ملاحظات وقرارات',
  };
  static const _columnTypes = <String, String>{
    'short_text': 'نص',
    'long_text': 'نص طويل',
    'integer': 'عدد صحيح',
    'decimal': 'رقم عشري',
    'quantity': 'كمية',
    'money': 'مبلغ',
    'select': 'قائمة',
    'boolean': 'نعم/لا',
  };
  static const _sections = <String, String>{
    'basic': 'البيانات الأساسية',
    'execution': 'تفاصيل التنفيذ',
    'results': 'النتائج والملاحظات',
    'evidence': 'الإثباتات والمرفقات',
  };

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<String> _organizationId() async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('يلزم تسجيل الدخول.');
    final memberships = await _db
        .from('organization_memberships')
        .select('organization_id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .order('created_at')
        .limit(100);
    for (final row in memberships) {
      final orgId = row['organization_id']?.toString();
      if (orgId == null) continue;
      final allowed = await _db.rpc(
        'report_designer_allowed_for_org',
        params: {'p_organization_id': orgId},
      );
      if (allowed == true) return orgId;
    }
    throw Exception('لا تملك صلاحية تصميم التقارير في مؤسسة نشطة.');
  }

  List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  Future<void> _loadTemplates() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final org = await _organizationId();
      final rows = await _db
          .from('report_form_templates')
          .select(
            'id,code,title,description,role_code,is_active,created_by,updated_by,created_at,updated_at',
          )
          .eq('organization_id', org)
          .eq('is_active', true)
          .order('title')
          .limit(100);
      final employees = await _db
          .from('organization_memberships')
          .select('user_id,display_name,employee_no')
          .eq('organization_id', org)
          .eq('is_active', true)
          .order('display_name')
          .limit(300);
      if (mounted) {
        setState(() {
          _orgId = org;
          _templates = _maps(rows);
          _employees = _maps(employees);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object e) => e.toString().replaceFirst('Exception: ', '');
  Map<String, dynamic> _newField(int i, Set<String> used) {
    var n = i + 1;
    while (used.contains('field_$n')) {
      n++;
    }
    return {
      'field_key': 'field_$n',
      'label': '',
      'description': '',
      'field_type': 'short_text',
      'is_required': false,
      'repeatable': false,
      'sort_order': i,
      'options': <String>[],
      'validation': <String, dynamic>{},
      'config': <String, dynamic>{'section': 'basic'},
    };
  }

  Map<String, dynamic> _obj(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _open(Map<String, dynamic> template, {bool copy = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final versions = await _db
          .from('report_form_versions')
          .select(
            'id,template_id,version_no,status,report_required,approved_by,approved_at',
          )
          .eq('template_id', template['id'])
          .order('version_no', ascending: false)
          .limit(1);
      if (versions.isEmpty) throw Exception('لا يوجد إصدار متاح لهذا القالب.');
      final version = Map<String, dynamic>.from(versions.first);
      final rows = await _db
          .from('report_form_version_fields')
          .select(
            'field_key,label,description,field_type,is_required,repeatable,sort_order,options,validation,config',
          )
          .eq('version_id', version['id'])
          .order('sort_order')
          .limit(200);
      final fields = _maps(rows)
          .map(
            (f) => <String, dynamic>{
              ...f,
              'description': f['description'] ?? '',
              'options': f['options'] is List
                  ? List<String>.from(
                      (f['options'] as List).map((x) => x.toString()),
                    )
                  : <String>[],
              'validation': _obj(f['validation']),
              'config': _obj(f['config']),
            },
          )
          .toList();
      setState(() {
        _editing = true;
        _templateId = copy ? null : template['id']?.toString();
        _versionId = copy ? null : version['id']?.toString();
        _status = copy ? 'draft' : (version['status']?.toString() ?? 'draft');
        _title = copy
            ? '${template['title']} — نسخة'
            : (template['title']?.toString() ?? '');
        _description = template['description']?.toString() ?? '';
        _role = template['role_code']?.toString() ?? 'admin_followup';
        _required = version['report_required'] == true;
        _fields = fields;
        _selected = fields.isEmpty ? null : 0;
        _notice = copy
            ? 'نسخة مستقلة؛ القالب الأصلي لم يتغير.'
            : 'تحرير إصدار جديد انطلاقًا من الإصدار ${version['version_no']}.';
        _dirty = false;
      });
    } catch (e) {
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _newTemplate() => setState(() {
    _editing = true;
    _templateId = null;
    _versionId = null;
    _status = 'draft';
    _title = '';
    _description = '';
    _role = 'admin_followup';
    _required = true;
    _fields = [];
    _selected = null;
    _error = null;
    _notice = null;
    _dirty = true;
  });
  void _patchField(int i, Map<String, dynamic> patch) => setState(() {
        _fields[i] = {..._fields[i], ...patch};
        _dirty = true;
      });

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغييرات غير محفوظة'),
          content: const Text(
            'لديك تغييرات غير محفوظة في مصمم التقارير. هل تريد الخروج دون حفظ؟',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('البقاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('الخروج دون حفظ'),
            ),
          ],
        ),
      ),
    );
    return leave == true;
  }

  Future<void> _leaveEditor() async {
    if (await _confirmExit() && mounted) {
      setState(() {
        _editing = false;
        _dirty = false;
      });
    }
  }

  String? _validate() {
    if (_title.trim().length < 2 || _title.trim().length > 160)
      return 'اسم النموذج مطلوب (2–160 محرفًا).';
    if (_fields.isEmpty) return 'أضف حقلًا واحدًا على الأقل.';
    if (_fields.length > 100) return 'لا يمكن أن يتجاوز النموذج 100 حقل.';
    final keys = <String>{};
    for (var i = 0; i < _fields.length; i++) {
      final f = _fields[i],
          key = (f['field_key'] ?? '').toString(),
          label = (f['label'] ?? '').toString().trim(),
          type = (f['field_type'] ?? '').toString();
      if (label.isEmpty || label.length > 200)
        return 'تحقق من اسم الحقل ${i + 1} (حتى 200 محرف).';
      if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(key))
        return 'مفتاح الحقل «$key» غير صالح.';
      if (!keys.add(key)) return 'مفتاح الحقل «$key» مكرر.';
      if (!_types.containsKey(type)) return 'نوع الحقل غير مدعوم.';
      final opts = (f['options'] as List? ?? [])
          .map((x) => x.toString())
          .toList();
      if ((type == 'select' || type == 'multiselect') &&
          (opts.isEmpty ||
              opts.any((x) => x.trim().isEmpty) ||
              opts.toSet().length != opts.length))
        return 'تحقق من خيارات «$label»؛ يلزم خيار واحد على الأقل بلا تكرار.';
      if (type == 'table') {
        final cols = _tableColumns(f);
        if (cols.isEmpty || cols.length > 20)
          return 'جدول «$label» يجب أن يحتوي من 1 إلى 20 عمودًا.';
        final colKeys = <String>{};
        for (final c in cols) {
          final ck = c['key'].toString();
          if (c['label'].toString().trim().isEmpty ||
              !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(ck) ||
              !colKeys.add(ck))
            return 'تحقق من أسماء ومفاتيح الأعمدة في «$label». ';
          final co = (c['options'] as List? ?? [])
              .map((x) => x.toString())
              .toList();
          if (c['type'] == 'select' &&
              (co.isEmpty ||
                  co.any((x) => x.trim().isEmpty) ||
                  co.toSet().length != co.length))
            return 'تحقق من خيارات عمود «${c['label']}».';
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _tableColumns(Map<String, dynamic> field) {
    final raw = _obj(field['config'])['columns'];
    if (raw is! List) return [];
    return raw.asMap().entries.map((entry) {
      final i = entry.key, value = entry.value;
      if (value is String)
        return <String, dynamic>{
          'key': value,
          'label': value,
          'type': 'short_text',
          'required': false,
          'options': <String>[],
          'validation': <String, dynamic>{},
        };
      final c = _obj(value);
      final type = (c['type'] ?? c['field_type'] ?? 'short_text').toString();
      return <String, dynamic>{
        'key': (c['key'] ?? 'column_${i + 1}').toString(),
        'label': (c['label'] ?? c['name'] ?? c['key'] ?? 'column_${i + 1}')
            .toString(),
        'type': _columnTypes.containsKey(type) ? type : 'short_text',
        'required': c['required'] == true || c['is_required'] == true,
        'options': c['options'] is List
            ? (c['options'] as List).map((x) => x.toString()).toList()
            : <String>[],
        'validation': _obj(c['validation']),
      };
    }).toList();
  }

  Future<void> _save() async {
    final issue = _validate();
    if (issue != null) {
      setState(() => _error = issue);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final org = await _organizationId();
      final payload = _fields.asMap().entries.map((entry) {
        final f = entry.value;
        return <String, dynamic>{
          'field_key': f['field_key'].toString().trim(),
          'label': f['label'].toString().trim(),
          'description': (f['description']?.toString().trim().isEmpty ?? true)
              ? null
              : f['description'].toString().trim(),
          'field_type': f['field_type'],
          'is_required': f['is_required'] == true,
          'repeatable': f['repeatable'] == true,
          'sort_order': entry.key,
          'options': f['options'] ?? <String>[],
          'validation': f['validation'] ?? <String, dynamic>{},
          'config': f['config'] ?? <String, dynamic>{},
        };
      }).toList();
      final result = await _db.rpc(
        'save_report_form_draft',
        params: {
          'p_organization_id': org,
          'p_template_id': _templateId,
          'p_title': _title.trim(),
          'p_description': _description.trim().isEmpty
              ? null
              : _description.trim(),
          'p_role_code': _role,
          'p_fields': payload,
          'p_report_required': _required,
        },
      );
      if (result is! Map ||
          result['template_id'] == null ||
          result['version_id'] == null)
        throw Exception('استجابة الحفظ غير مكتملة.');
      setState(() {
        _templateId = result['template_id'].toString();
        _versionId = result['version_id'].toString();
        _status = 'draft';
        _dirty = false;
        _notice = 'حُفظ إصدار مسودة جديد. اعتمده صاحب المؤسسة قبل استخدامه.';
      });
      await _loadTemplates();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final id = _versionId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _db.rpc(
        'approve_report_form_version',
        params: {'p_version_id': id},
      );
      setState(() {
        _status = 'published';
        _dirty = false;
        _notice = 'تم اعتماد الإصدار؛ سيبقى محفوظًا كنسخة ثابتة.';
      });
    } catch (e) {
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveAndSend() async {
    if (_status == 'draft') await _approve();
    if (_status == 'published') await _sendToEmployee();
  }

  Future<void> _sendToEmployee() async {
    final org = _orgId;
    final templateId = _templateId;
    final versionId = _versionId;
    if (org == null || templateId == null || versionId == null) return;
    if (_fields.isEmpty) {
      setState(() => _error = 'لا يمكن إرسال التقرير؛ أضف حقلًا واحدًا على الأقل ثم احفظه واعتمده.');
      return;
    }
    String? employeeId;
    var due = DateTime.now().add(const Duration(days: 1));
    due = DateTime(due.year, due.month, due.day, 17);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إرسال التقرير للموظف'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: employeeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الموظف المسؤول *'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('اختر الموظف'),
                  ),
                  ..._employees.map(
                    (e) => DropdownMenuItem(
                      value: e['user_id']?.toString(),
                      child: Text(
                        '${e['display_name'] ?? 'موظف'} · ${e['employee_no'] ?? ''}',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setDialogState(() => employeeId = value),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الموعد النهائي', textAlign: TextAlign.right),
                subtitle: Text(
                  '${due.day}/${due.month}/${due.year} ${due.hour}:00',
                  textAlign: TextAlign.right,
                ),
                trailing: const Icon(Icons.event_available_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: due,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) {
                    setDialogState(
                      () => due = DateTime(picked.year, picked.month, picked.day, 17),
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: employeeId == null
                  ? null
                  : () => Navigator.of(dialogContext).pop({
                        'employee_id': employeeId,
                        'due_at': due.toUtc().toIso8601String(),
                      }),
              child: const Text('اعتماد وإرسال'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result['employee_id'] == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final safeDescription = _description.trim().isEmpty
          ? 'التقرير المطلوب: ${_title.trim()}'
          : _description.trim();
      await _db.rpc(
        'create_task_with_report_form',
        params: {
          'p_organization_id': org,
          'p_title': _title.trim(),
          'p_description': safeDescription,
          'p_due_at': result['due_at'],
          'p_priority': 'normal',
          'p_branch_id': null,
          'p_role_code': _role,
          'p_template_id': null,
          'p_assigned_to': result['employee_id'],
          'p_report_template_id': templateId,
          'p_report_version_id': versionId,
          'p_report_required': _required,
        },
      );
      setState(() => _notice = 'تم اعتماد التقرير وإرساله للموظف داخل قائمة المهام.');
    } catch (e) {
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvoked: (didPop) async {
      if (didPop || !_dirty) return;
      if (await _confirmExit() && mounted) context.pop();
    },
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: AppShell(
        title: 'مصمم التقارير',
        subtitle: 'مكتبة قوالب النماذج وإصداراتها',
        onBeforeNavigate: _confirmExit,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (_error != null) _messageBox(_error!, true),
                  if (_notice != null) _messageBox(_notice!, false),
                  if (_busy) const LinearProgressIndicator(),
                  if (_editing) _editor() else _library(),
                ],
              ),
      ),
    ),
  );

  Widget _messageBox(String text, bool error) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: error ? const Color(0xfffff0ef) : const Color(0xffe8f5eb),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(color: error ? Colors.red.shade800 : AppColors.green),
    ),
  );
  Widget _library() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'مكتبة التقارير',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _newTemplate,
            icon: const Icon(Icons.add),
            label: const Text('نموذج جديد'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (_templates.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'لا توجد قوالب نشطة. أنشئ نموذجًا جديدًا للبدء.',
              textAlign: TextAlign.right,
            ),
          ),
        ),
      for (final t in _templates)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t['title']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                  textAlign: TextAlign.right,
                ),
                Text(
                  '${_roles[t['role_code']] ?? t['role_code'] ?? ''}${t['updated_at'] == null ? '' : ' · ${t['updated_at']}'}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.muted),
                ),
                if ((t['description']?.toString() ?? '').isNotEmpty)
                  Text(t['description'].toString(), textAlign: TextAlign.right),
                Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => _open(t),
                      child: const Text('تعديل / إصدار جديد'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _open(t, copy: true),
                      child: const Text('نسخ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      TextButton.icon(
        onPressed: _loadTemplates,
        icon: const Icon(Icons.refresh),
        label: const Text('تحديث المكتبة'),
      ),
    ],
  );

  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          IconButton(
            onPressed: _leaveEditor,
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(
              _templateId == null ? 'نموذج جديد' : 'إصدار جديد',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 19,
                color: AppColors.navy,
              ),
            ),
          ),
          TextButton(
            onPressed: _leaveEditor,
            child: const Text('المكتبة'),
          ),
        ],
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                textAlign: TextAlign.right,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'اسم النموذج'),
                controller: _controllerForTitle(),
              ),
              const SizedBox(height: 8),
              TextField(
                textAlign: TextAlign.right,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'الوصف وتعليمات الموظف',
                ),
                controller: _controllerForDescription(),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _roles.containsKey(_role) ? _role : 'admin_followup',
                decoration: const InputDecoration(labelText: 'الدور الوظيفي'),
                items: _roles.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: _templateId == null
                    ? (v) => setState(() {
                        _role = v ?? _role;
                        _dirty = true;
                      })
                    : null,
              ),
              if (_templateId != null)
                const Text(
                  'دور القالب ثابت؛ أنشئ نسخة مستقلة لتغييره.',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: AppColors.muted),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'التقرير مطلوب عند التنفيذ',
                  textAlign: TextAlign.right,
                ),
                value: _required,
                onChanged: (v) => setState(() {
                  _required = v ?? false;
                  _dirty = true;
                }),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'الحقول (${_fields.length}/100)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _fields.length >= 100
                        ? null
                        : () {
                            final f = _newField(
                              _fields.length,
                              _fields
                                  .map((x) => x['field_key'].toString())
                                  .toSet(),
                            );
                            setState(() {
                              _fields.add(f);
                              _selected = _fields.length - 1;
                              _dirty = true;
                            });
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة'),
                  ),
                ],
              ),
              if (_fields.isEmpty)
                const Text(
                  'أضف حقلًا واحدًا على الأقل.',
                  textAlign: TextAlign.right,
                ),
              if (_fields.isNotEmpty)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _fields.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final field = _fields.removeAt(oldIndex);
                      _fields.insert(newIndex, field);
                      _dirty = true;
                      if (_selected == oldIndex) {
                        _selected = newIndex;
                      } else if (_selected != null) {
                        if (oldIndex < _selected! && newIndex >= _selected!) {
                          _selected = _selected! - 1;
                        } else if (oldIndex > _selected! && newIndex <= _selected!) {
                          _selected = _selected! + 1;
                        }
                      }
                    });
                  },
                  itemBuilder: (context, i) => KeyedSubtree(
                    key: ValueKey('report_field_${_fields[i]['field_key']}'),
                    child: _fieldTile(i),
                  ),
                ),
            ],
          ),
        ),
      ),
      _preview(),
      OutlinedButton.icon(
        onPressed: _showFullPreview,
        icon: const Icon(Icons.fullscreen_outlined),
        label: const Text('معاينة التقرير بشكل كامل'),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _save,
        icon: const Icon(Icons.save),
        label: Text(_busy ? 'جارٍ الحفظ…' : 'حفظ كمسودة'),
      ),
      if (_versionId != null && _status == 'draft')
        OutlinedButton.icon(
          onPressed: _busy ? null : _approve,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('اعتماد الإصدار'),
        ),
      if (_versionId != null && (_status == 'draft' || _status == 'published'))
        FilledButton.icon(
          onPressed: _busy ? null : _approveAndSend,
          icon: const Icon(Icons.send_outlined),
          label: const Text('اعتماد وإرسال للموظف'),
        ),
      if (_status == 'published')
        const Text(
          'الإصدار معتمد وثابت ✓',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.green, fontWeight: FontWeight.bold),
        ),
    ],
  );

  final _titleController = TextEditingController(),
      _descriptionController = TextEditingController();
  TextEditingController _controllerForTitle() {
    if (_titleController.text != _title) {
      _titleController.value = TextEditingValue(
        text: _title,
        selection: TextSelection.collapsed(offset: _title.length),
      );
    }
    _titleController.removeListener(_syncTitle);
    _titleController.addListener(_syncTitle);
    return _titleController;
  }

  void _syncTitle() {
    if (_title != _titleController.text) {
      _title = _titleController.text;
      _dirty = true;
    }
  }

  TextEditingController _controllerForDescription() {
    if (_descriptionController.text != _description) {
      _descriptionController.value = TextEditingValue(
        text: _description,
        selection: TextSelection.collapsed(offset: _description.length),
      );
    }
    _descriptionController.removeListener(_syncDescription);
    _descriptionController.addListener(_syncDescription);
    return _descriptionController;
  }

  void _syncDescription() {
    if (_description != _descriptionController.text) {
      _description = _descriptionController.text;
      _dirty = true;
    }
  }

  Widget _fieldTile(int i) {
    final f = _fields[i], expanded = _selected == i;
    return Card(
      color: expanded ? const Color(0xfff4f7f8) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'أعلى',
                  onPressed: i == 0
                      ? null
                      : () => setState(() => _swap(i, i - 1)),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: 'أسفل',
                  onPressed: i == _fields.length - 1
                      ? null
                      : () => setState(() => _swap(i, i + 1)),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: 'إزالة من المسودة',
                  onPressed: () => setState(() {
                    _fields.removeAt(i);
                    _dirty = true;
                    _selected = _fields.isEmpty
                        ? null
                        : ((_selected ?? 0) >= _fields.length
                              ? _fields.length - 1
                              : _selected);
                  }),
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.drag_indicator, color: AppColors.muted),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _selected = expanded ? null : i),
                    child: Text(
                      '${f['label'].toString().isEmpty ? 'حقل ${i + 1}' : f['label']} · ${_types[f['field_type']] ?? f['field_type']}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              _textEditor(i, 'اسم الحقل', 'label'),
              _textEditor(i, 'تعليمات الحقل (اختياري)', 'description'),
              DropdownButtonFormField<String>(
                value: _types.containsKey(f['field_type'])
                    ? f['field_type']
                    : 'short_text',
                decoration: const InputDecoration(labelText: 'نوع الحقل'),
                items: _types.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => _patchField(i, {'field_type': v}),
              ),
              DropdownButtonFormField<String>(
                value: _sections.containsKey(_fieldSection(f))
                    ? _fieldSection(f)
                    : 'basic',
                decoration: const InputDecoration(labelText: 'قسم التقرير'),
                items: _sections.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => _patchField(i, {
                  'config': {..._obj(f['config']), 'section': v ?? 'basic'},
                }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('حقل مطلوب', textAlign: TextAlign.right),
                value: f['is_required'] == true,
                onChanged: (v) => _patchField(i, {'is_required': v == true}),
              ),
              if (['select', 'multiselect'].contains(f['field_type']))
                _optionsEditor(i),
              if (f['field_type'] == 'table') _columnsEditor(i),
            ],
          ],
        ),
      ),
    );
  }

  String _fieldSection(Map<String, dynamic> field) =>
      _obj(field['config'])['section']?.toString() ?? 'basic';

  Widget _preview() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final key in _sections.keys) {
      final fields = _fields.where((f) => _fieldSection(f) == key).toList();
      if (fields.isNotEmpty) groups[key] = fields;
    }
    return Card(
      color: const Color(0xfff5f8fa),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.preview_outlined, color: AppColors.navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'معاينة التقرير للموظف',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy),
                  ),
                ),
              ],
            ),
            const Divider(),
            if (groups.isEmpty)
              const Text('أضف حقولًا لتظهر المعاينة هنا.', textAlign: TextAlign.right),
            for (final entry in groups.entries) ...[
              Text(_sections[entry.key]!, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final field in entry.value)
                _previewField(field),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewField(Map<String, dynamic> field) {
    final type = field['field_type']?.toString() ?? 'short_text';
    final label = (field['label']?.toString().trim().isEmpty ?? true)
        ? 'حقل بدون اسم'
        : field['label'].toString();
    final required = field['is_required'] == true ? ' *' : '';
    final options = (field['options'] as List? ?? []).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    Widget control;
    if (type == 'long_text' || type == 'decision_notes') {
      control = const TextField(maxLines: 3, enabled: false, decoration: InputDecoration(hintText: 'اكتب التفاصيل هنا...'));
    } else if (type == 'select' || type == 'multiselect') {
      control = InputDecorator(
        decoration: const InputDecoration(border: OutlineInputBorder(), suffixIcon: Icon(Icons.arrow_drop_down)),
        child: Text(options.isEmpty ? 'اختر من القائمة' : options.take(2).join('، '), textAlign: TextAlign.right),
      );
    } else if (type == 'boolean') {
      control = const Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('لا'), SizedBox(width: 10), Icon(Icons.radio_button_unchecked), SizedBox(width: 18), Text('نعم'), SizedBox(width: 10), Icon(Icons.radio_button_unchecked)]);
    } else if (type == 'image' || type == 'multi_image') {
      control = _uploadPreview(Icons.photo_camera_outlined, type == 'multi_image' ? 'إضافة صور' : 'رفع صورة');
    } else if (type == 'file' || type == 'attachment') {
      control = _uploadPreview(Icons.attach_file, 'إرفاق ملف أو مستند');
    } else if (type == 'signature') {
      control = _uploadPreview(Icons.draw_outlined, 'منطقة التوقيع');
    } else if (type == 'table') {
      final columns = _tableColumns(field);
      control = Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xffdce4e8)), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [for (final column in columns.take(3)) Expanded(child: Padding(padding: const EdgeInsets.all(4), child: Text(column['label'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))))]),
      );
    } else if (type == 'date' || type == 'datetime' || type == 'date_range') {
      control = const TextField(enabled: false, decoration: InputDecoration(hintText: 'اختر التاريخ', suffixIcon: Icon(Icons.calendar_today_outlined)));
    } else if (type == 'calculated' || type == 'system_reference') {
      control = const InputDecorator(decoration: InputDecoration(border: OutlineInputBorder()), child: Text('يُعبّأ تلقائيًا', textAlign: TextAlign.right));
    } else {
      control = TextField(enabled: false, decoration: InputDecoration(hintText: type == 'short_text' ? 'اكتب هنا...' : 'أدخل القيمة'));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xffdce4e8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$label$required', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        control,
      ]),
    );
  }

  Widget _uploadPreview(IconData icon, String label) => OutlinedButton.icon(
    onPressed: null,
    icon: Icon(icon),
    label: Text(label),
  );

  Future<void> _showFullPreview() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.preview_outlined, color: AppColors.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title.trim().isEmpty ? 'معاينة التقرير' : _title.trim(),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_description.trim().isNotEmpty) ...[
                    Text(_description.trim(), textAlign: TextAlign.right),
                    const Divider(height: 24),
                  ],
                  _preview(),
                  const SizedBox(height: 8),
                  const Text(
                    'هذه معاينة توضيحية؛ لن يتم حفظ أي قيمة أو رفع ملف من هذه الشاشة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إغلاق المعاينة'),
            ),
          ],
        ),
      ),
    );
  }

  void _swap(int a, int b) {
    final item = _fields.removeAt(a);
    _fields.insert(b, item);
    _selected = b;
    _dirty = true;
  }

  Widget _textEditor(int i, String label, String key) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextFormField(
      initialValue: _fields[i][key]?.toString() ?? '',
      textAlign: TextAlign.right,
      maxLength: key == 'label' ? 200 : null,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => _patchField(i, {key: v}),
    ),
  );
  Widget _optionsEditor(int i) {
    final options = (_fields[i]['options'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('خيارات القائمة', textAlign: TextAlign.right),
        for (var j = 0; j < options.length; j++)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('opt_${i}_${j}_${options[j]}'),
                  initialValue: options[j],
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(labelText: 'خيار ${j + 1}'),
                  onChanged: (v) {
                    final n = [...options];
                    n[j] = v;
                    _patchField(i, {'options': n});
                  },
                ),
              ),
              IconButton(
                onPressed: () => _patchField(i, {
                  'options': options
                      .asMap()
                      .entries
                      .where((e) => e.key != j)
                      .map((e) => e.value)
                      .toList(),
                }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _patchField(i, {
              'options': [...options, ''],
            }),
            icon: const Icon(Icons.add),
            label: const Text('إضافة خيار'),
          ),
        ),
      ],
    );
  }

  Widget _columnsEditor(int i) {
    final field = _fields[i],
        config = _obj(field['config']),
        cols = _tableColumns(field);
    void update(int j, Map<String, dynamic> patch) {
      final next = cols.map((c) => Map<String, dynamic>.from(c)).toList();
      next[j] = {...next[j], ...patch};
      _patchField(i, {
        'config': {...config, 'columns': next},
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const Text(
          'أعمدة الجدول',
          textAlign: TextAlign.right,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (var j = 0; j < cols.length; j++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  TextFormField(
                    key: ValueKey('col_label_${i}_$j'),
                    initialValue: cols[j]['label'].toString(),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(labelText: 'اسم العمود'),
                    onChanged: (v) => update(j, {'label': v}),
                  ),
                  TextFormField(
                    key: ValueKey('col_key_${i}_$j'),
                    initialValue: cols[j]['key'].toString(),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'المفتاح (إنجليزي)',
                    ),
                    onChanged: (v) => update(j, {'key': v}),
                  ),
                  DropdownButtonFormField<String>(
                    value: _columnTypes.containsKey(cols[j]['type'])
                        ? cols[j]['type']
                        : 'short_text',
                    decoration: const InputDecoration(labelText: 'نوع العمود'),
                    items: _columnTypes.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => update(j, {'type': v}),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('عمود مطلوب', textAlign: TextAlign.right),
                    value: cols[j]['required'] == true,
                    onChanged: (v) => update(j, {'required': v == true}),
                  ),
                  if (cols[j]['type'] == 'select')
                    TextFormField(
                      key: ValueKey('col_options_${i}_$j'),
                      initialValue: (cols[j]['options'] as List).join('، '),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'الخيارات مفصولة بـ ،',
                      ),
                      onChanged: (v) => update(j, {
                        'options': v
                            .split('،')
                            .map((x) => x.trim())
                            .where((x) => x.isNotEmpty)
                            .toList(),
                      }),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _patchField(i, {
                        'config': {
                          ...config,
                          'columns': cols
                              .asMap()
                              .entries
                              .where((e) => e.key != j)
                              .map((e) => e.value)
                              .toList(),
                        },
                      }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('إزالة العمود'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _patchField(i, {
              'config': {
                ...config,
                'columns': [
                  ...cols,
                  {
                    'key': 'column_${cols.length + 1}',
                    'label': 'عمود ${cols.length + 1}',
                    'type': 'short_text',
                    'required': false,
                    'options': <String>[],
                    'validation': <String, dynamic>{},
                  },
                ],
              },
            }),
            icon: const Icon(Icons.add),
            label: const Text('إضافة عمود'),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
