import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_shell.dart';

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
      _requests = [];

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
              'id,title,description,branch_id,assigned_to,due_at,priority,status,deleted_at',
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
      setState(() {
        _orgId = org;
        _tasks = _rows(results[0]);
        _branches = _rows(results[1]);
        _employees = _rows(results[2]);
        _templates = _rows(results[3]);
        _requests = _rows(results[4]);
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

  Future<void> _saveTask({Map<String, dynamic>? existing}) async {
    final title = TextEditingController(text: _s(existing?['title']));
    final description = TextEditingController(
      text: _s(existing?['description']),
    );
    final due = TextEditingController(
      text: _s(existing?['due_at']).isEmpty
          ? DateTime.now().add(const Duration(days: 1)).toIso8601String()
          : _s(existing?['due_at']),
    );
    String priority = _s(existing?['priority'], 'normal');
    String? branchId = _s(existing?['branch_id']).isEmpty
        ? null
        : _s(existing?['branch_id']);
    String? role = 'admin_followup';
    String? assignee = _s(existing?['assigned_to']).isEmpty
        ? null
        : _s(existing?['assigned_to']);
    String? templateId;
    bool reportRequired = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? 'إنشاء مهمة' : 'تعديل المهمة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'العنوان *'),
                ),
                TextField(
                  controller: description,
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'الوصف'),
                ),
                TextField(
                  controller: due,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'موعد الاستحقاق ISO-8601',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: priority,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الأولوية'),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('عادية')),
                    DropdownMenuItem(value: 'important', child: Text('مهمة')),
                    DropdownMenuItem(value: 'urgent', child: Text('عاجلة')),
                    DropdownMenuItem(value: 'critical', child: Text('حرجة')),
                  ],
                  onChanged: (v) => set(() => priority = v ?? 'normal'),
                ),
                if (existing == null) ...[
                  DropdownButtonFormField<String>(
                    value: branchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الفرع (اختياري)',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('كل الفروع'),
                      ),
                      ..._branches.map(
                        (b) => DropdownMenuItem(
                          value: _s(b['id']),
                          child: Text(_s(b['name'], _s(b['code']))),
                        ),
                      ),
                    ],
                    onChanged: (v) => set(() => branchId = v),
                  ),
                  DropdownButtonFormField<String>(
                    value: templateId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'قالب المهمة (اختياري)',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('إنشاء مباشر'),
                      ),
                      ..._templates.map(
                        (t) => DropdownMenuItem(
                          value: _s(t['id']),
                          child: Text(
                            '${_s(t['title'])} · ${_s(t['role_code'])}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => set(() => templateId = v),
                  ),
                  DropdownButtonFormField<String>(
                    value: role,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الدور'),
                    items: const [
                      DropdownMenuItem(
                        value: 'owner',
                        child: Text('صاحب المؤسسة'),
                      ),
                      DropdownMenuItem(
                        value: 'admin_followup',
                        child: Text('المدير التنفيذي'),
                      ),
                      DropdownMenuItem(
                        value: 'accountant',
                        child: Text('المحاسب'),
                      ),
                      DropdownMenuItem(
                        value: 'warehouse_keeper',
                        child: Text('أمين المخازن'),
                      ),
                      DropdownMenuItem(
                        value: 'warehouse_worker',
                        child: Text('عمال التحميل'),
                      ),
                    ],
                    onChanged: (v) => set(() => role = v),
                  ),
                  DropdownButtonFormField<String>(
                    value: assignee,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الموظف المكلّف',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('اختر موظفًا'),
                      ),
                      ..._employees.map(
                        (e) => DropdownMenuItem(
                          value: _s(e['user_id']),
                          child: Text(
                            _s(e['display_name'], _s(e['employee_no'])),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => set(() => assignee = v),
                  ),
                  SwitchListTile(
                    title: const Text('التقرير مطلوب'),
                    value: reportRequired,
                    onChanged: (v) => set(() => reportRequired = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      title.dispose();
      description.dispose();
      due.dispose();
      return;
    }
    if (title.text.trim().length < 2 ||
        DateTime.tryParse(due.text.trim()) == null) {
      _message('أدخل عنوانًا وموعدًا صالحين.');
      title.dispose();
      description.dispose();
      due.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      if (existing != null) {
        await _db.rpc(
          'admin_update_task',
          params: {
            'p_organization_id': _orgId,
            'p_task_id': existing['id'],
            'p_title': title.text.trim(),
            'p_description': description.text.trim().isEmpty
                ? null
                : description.text.trim(),
            'p_due_at': due.text.trim(),
          },
        );
      } else {
        if (assignee == null || role == null)
          throw Exception('اختر الموظف والدور قبل الإنشاء.');
        if (templateId != null) {
          await _db.rpc(
            'assign_task_from_template',
            params: {
              'p_organization_id': _orgId,
              'p_template_id': templateId,
              'p_assigned_to': assignee,
              'p_branch_id': branchId,
              'p_starts_at': DateTime.now().toUtc().toIso8601String(),
              'p_due_at': due.text.trim(),
              'p_priority': priority,
              'p_instructions': description.text.trim().isEmpty
                  ? null
                  : description.text.trim(),
              'p_report_overrides': <dynamic>[],
              'p_idempotency_key':
                  'flutter-template:$templateId:$assignee:${due.text.trim()}',
            },
          );
        } else {
          await _db.rpc(
            'create_task_with_report_form',
            params: {
              'p_organization_id': _orgId,
              'p_title': title.text.trim(),
              'p_description': description.text.trim().isEmpty
                  ? null
                  : description.text.trim(),
              'p_due_at': due.text.trim(),
              'p_priority': priority,
              'p_branch_id': branchId,
              'p_role_code': role,
              'p_template_id': null,
              'p_assigned_to': assignee,
              'p_report_template_id': null,
              'p_report_version_id': null,
              'p_report_required': reportRequired,
            },
          );
        }
      }
      _message(existing == null ? 'تم إنشاء المهمة.' : 'تم تعديل المهمة.');
      await _load();
    } catch (e) {
      _message('تعذر الحفظ: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
      title.dispose();
      description.dispose();
      due.dispose();
    }
  }

  Future<void> _delete(Map<String, dynamic> task) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المهمة'),
        content: const Text(
          'سيتم تنفيذ الحذف الآمن/الأرشفة حسب عقد Backend مع الحفاظ على سجل النشاط.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      await _db.rpc(
        'admin_delete_task',
        params: {'p_organization_id': _orgId, 'p_task_id': task['id']},
      );
      _message('تمت أرشفة المهمة وحجبها من القوائم.');
      await _load();
    } catch (e) {
      _message('تعذر حذف المهمة: $e');
    } finally {
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
    final due = TextEditingController(
      text: DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    );
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
              TextField(
                controller: due,
                decoration: const InputDecoration(
                  labelText: 'موعد الاستحقاق ISO-8601',
                ),
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
    if (ok != true || template == null) {
      due.dispose();
      return;
    }
    try {
      await _db.rpc(
        'submit_task_publication_request',
        params: {
          'p_organization_id': _orgId,
          'p_template_id': template,
          'p_branch_id': branch,
          'p_due_at': due.text.trim(),
          'p_idempotency_key':
              'flutter-publication:${template}:${branch ?? 'all'}:${due.text.trim()}',
        },
      );
      _message('تم إرسال طلب النشر للموافقة.');
      await _load();
    } catch (e) {
      _message('تعذر إرسال طلب النشر: $e');
    } finally {
      due.dispose();
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
    subtitle: 'الإنشاء والتعديل والحذف الآمن وطلبات النشر',
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
                  title: 'المهام (${_tasks.length})',
                  child: _tasks.isEmpty
                      ? const Text('لا توجد مهام.', textAlign: TextAlign.right)
                      : Column(
                          children: _tasks
                              .map(
                                (t) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    _s(t['title'], 'مهمة'),
                                    textAlign: TextAlign.right,
                                  ),
                                  subtitle: Text(
                                    '${_status(_s(t['status']))} · ${_branchName(_s(t['branch_id']).isEmpty ? null : _s(t['branch_id']))} · ${_employeeName(_s(t['assigned_to']))}',
                                    textAlign: TextAlign.right,
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) => v == 'edit'
                                        ? _saveTask(existing: t)
                                        : _delete(t),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('تعديل'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('حذف آمن'),
                                      ),
                                    ],
                                  ),
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
