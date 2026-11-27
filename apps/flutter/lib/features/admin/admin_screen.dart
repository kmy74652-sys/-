import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/app_shell.dart';
import '../../core/theme.dart';
import '../../shared/ui_labels.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({
    super.key,
    this.embedded = false,
    this.inline = false,
    this.initialSection,
  });

  /// In embedded mode, the parent AppShell owns the page header/navigation.
  final bool embedded;

  /// Renders the administration panel as content inside another scroll view.
  final bool inline;

  final String? initialSection;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _loading = true;
  String? _error;
  String _section = 'overview';
  String _name = '';
  String? _organizationId;
  bool _branchBusy = false;
  String? _branchError;
  String? _branchNotice;
  String _newBranchCode = '';
  String _newBranchName = '';
  final Map<String, String> _branchRenames = {};
  List<String> _permissions = [];
  List<Map<String, dynamic>> _tasks = [],
      _branches = [],
      _employees = [],
      _reports = [],
      _roleReports = [],
      _activity = [];

  @override
  void initState() {
    super.initState();
    const sections = {'overview', 'tasks', 'reports', 'branches', 'employees', 'activity', 'performance'};
    if (sections.contains(widget.initialSection)) {
      _section = widget.initialSection!;
    }
    _load();
  }

  bool _can(String permission) => _permissions.contains(permission);
  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      if (db.auth.currentSession == null) {
        if (mounted) context.go('/login');
        return;
      }
      final profileResult = await db.rpc('mobile_my_profile');
      final root = profileResult is Map
          ? profileResult
          : const <String, dynamic>{};
      final employee = root['employee'];
      if (employee is! Map) throw Exception('الحساب غير مرتبط بملف موظف نشط.');
      final rawPermissions = employee['permissions'];
      final permissions = rawPermissions is List
          ? rawPermissions.map((v) => v.toString()).toList()
          : <String>[];
      final organizationId =
          (employee['institutionId'] ??
                  employee['institution_id'] ??
                  employee['organization_id'])
              ?.toString();
      if (!permissions.contains('tasks.manage'))
        throw Exception(
          'لا تملك صلاحية الوصول إلى لوحة الإدارة (tasks.manage).',
        );
      // These select shapes and table names mirror the existing mobile admin data layer.
      final results = await Future.wait([
        db
            .from('tasks')
            .select(
              'id,title,description,branch_id,assigned_to,due_at,priority,status',
            )
            .isFilter('deleted_at', null)
            .order('due_at')
            .limit(200),
        db
            .from('branches')
            .select('id,code,name,is_active,branch_level')
            .order('code')
            .limit(100),
        db
            .from('organization_memberships')
            .select('id,user_id,display_name,employee_no,is_active')
            .order('display_name')
            .limit(200),
        db
            .from('task_reports')
            .select(
              'id,task_id,status,submitted_at,review_note,values,report_form_snapshot_id',
            )
            .order('submitted_at', ascending: false)
            .limit(100),
        db
            .from('employee_role_reports')
            .select(
              'id,employee_user_id,role_code,branch_id,report_date,report_title,status,submitted_at,review_note,values',
            )
            .order('submitted_at', ascending: false)
            .limit(100),
        db
            .from('task_activity_log')
            .select('id,task_id,action,created_at')
            .order('created_at', ascending: false)
            .limit(100),
      ]);
      if (!mounted) return;
      setState(() {
        _permissions = permissions;
        _organizationId = organizationId;
        _name = (employee['fullName'] ?? employee['full_name'] ?? '')
            .toString();
        _tasks = _rows(results[0]);
        _branches = _rows(results[1]);
        _employees = _rows(results[2]);
        _reports = _rows(results[3]);
        _roleReports = _rows(results[4]);
        _activity = _rows(results[5]);
      });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _rows(dynamic value) => (value as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  String _text(dynamic value, [String fallback = '—']) =>
      value == null || value.toString().isEmpty ? fallback : value.toString();
  String _date(dynamic value) {
    if (value == null) return 'غير محدد';
    final parsed = DateTime.tryParse(value.toString());
    return parsed == null
        ? 'غير محدد'
        : '${parsed.toLocal().year}/${parsed.toLocal().month.toString().padLeft(2, '0')}/${parsed.toLocal().day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inline) {
      if (_loading && _tasks.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (_error != null) {
        return SectionCard(
          title: 'تعذر تحميل لوحة الإدارة',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_error!, textAlign: TextAlign.right),
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
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(),
          _overview(),
        ],
      );
    }
    final content = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (_loading && _tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(44),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SectionCard(
              title: 'تعذر تحميل لوحة الإدارة',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!, textAlign: TextAlign.right),
                  const SizedBox(height: 8),
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
            )
          else ...[
            if (_loading) const LinearProgressIndicator(),
            if (_section == 'overview') _overview() else _sectionContent(),
          ],
        ],
      ),
    );
    if (widget.embedded) return content;
    return AppShell(
      title: _section == 'overview'
          ? 'لوحة الإدارة'
          : const {
              'tasks': 'مهام الجدول الموحد',
              'reports': 'مراجعة التقارير',
              'branches': 'الفروع',
              'employees': 'الموظفون',
              'activity': 'سجل النشاط',
              'performance': 'تحليلات الأداء',
            }[_section] ?? 'الإدارة',
      subtitle: _name.isEmpty
          ? 'إدارة وفق صلاحيات الحساب وسياسات RLS'
          : 'مرحبًا $_name',
      child: content,
    );
  }

  Widget _overview() {
    return const SectionCard(
      title: 'لوحة الإدارة',
      child: Text(
        'اختر القسم المطلوب من القائمة الجانبية أو من شاشة الموظفين والإعدادات.',
        textAlign: TextAlign.right,
      ),
    );
  }
  Widget _sectionContent() {
    final title =
        {
          'tasks': 'مهام الجدول الموحد',
          'reports': 'مراجعة التقارير',
          'branches': 'الفروع',
          'employees': 'الموظفون',
          'activity': 'سجل النشاط',
          'performance': 'الأداء',
        }[_section] ??
        'الإدارة';
    List<Map<String, dynamic>> rows = [];
    var allowed = true;
    if (_section == 'tasks') rows = _tasks;
    if (_section == 'branches') {
      allowed = _can('branches.read_all') || _can('branches.manage');
      rows = _branches;
    }
    if (_section == 'employees') {
      allowed = _can('employees.read') || _can('employees.manage');
      rows = _employees;
    }
    if (_section == 'reports') {
      allowed = _can('reports.read_all') || _can('tasks.review');
      rows = [..._reports, ..._roleReports];
    }
    if (_section == 'activity') {
      allowed = _can('audit.read');
      rows = _activity;
    }
    if (_section == 'performance') {
      allowed = _can('reports.read_all') || _can('tasks.review');
      rows = _tasks;
    }
    if (!allowed)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _back(),
          SectionCard(
            title: title,
            child: const Text(
              'لا تسمح صلاحيات الحساب بعرض هذا القسم.',
              textAlign: TextAlign.right,
            ),
          ),
        ],
      );
    if (_section == 'performance')
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _back(),
          SectionCard(
            title: title,
            child: Text(
              'ملخص للقراءة فقط من المهام المتاحة عبر RLS: ${_tasks.length} مهمة، ${_tasks.where((t) => t['status'] == 'completed_approved').length} مكتملة ومعتمدة، ${_reports.length + _roleReports.length} تقريرًا.',
              textAlign: TextAlign.right,
            ),
          ),
        ],
      );
    if (_section == 'branches') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _back(),
          SectionCard(
            title: 'إدارة الفروع (${_branches.length})',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'يمكن إضافة الفروع وتعديل أسمائها وأرشفتها. الأرشفة توقف استخدام الفرع الجديد وتحافظ على المهام والسجلات السابقة.',
                  textAlign: TextAlign.right,
                ),
                if (_branchBusy) const LinearProgressIndicator(),
                if (_branchError != null)
                  Text(
                    _branchError!,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.red),
                  ),
                if (_branchNotice != null)
                  Text(
                    _branchNotice!,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.green),
                  ),
                if (_can('branches.manage')) ...[
                  const Divider(),
                  const Text('إضافة فرع جديد', textAlign: TextAlign.right),
                  const Text(
                    'سيتم إنشاء كود الفرع تلقائيًا بعد الحفظ.',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Colors.black54),
                  ),
                  TextField(
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(labelText: 'اسم الفرع'),
                    onChanged: (v) => setState(() => _newBranchName = v),
                  ),
                  FilledButton(
                    onPressed:
                        _branchBusy ||
                            _newBranchName.trim().isEmpty
                        ? null
                        : () => _manageBranch('create'),
                    child: Text(_branchBusy ? 'جارٍ الحفظ…' : 'إضافة الفرع'),
                  ),
                ],
                const Divider(),
                if (_branches.isEmpty)
                  const Text(
                    'لا توجد سجلات للعرض.',
                    textAlign: TextAlign.right,
                  ),
                ..._branches.map(_branchCard),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _back(),
        SectionCard(
          title: '$title (${rows.length})',
          child: rows.isEmpty
              ? const Text('لا توجد سجلات للعرض.', textAlign: TextAlign.right)
              : Column(
                  children: rows.take(100).map((row) => _record(row)).toList(),
                ),
        ),
      ],
    );
  }

  Widget _branchCard(Map<String, dynamic> branch) {
    final id = branch['id'].toString();
    final active = branch['is_active'] == true;
    final currentName = branch['name']?.toString() ?? '';
    return SectionCard(
      title: currentName,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الكود: ${_text(branch['code'])} · المستوى: ${_text(branch['branch_level'], 'غير محدد')} · ${active ? 'نشط' : 'مؤرشف'}',
              textAlign: TextAlign.right,
            ),
            if (_can('branches.manage') && active) ...[
              TextField(
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'الاسم الجديد للفرع',
                ),
                controller:
                    TextEditingController(
                        text: _branchRenames[id] ?? currentName,
                      )
                      ..selection = TextSelection.collapsed(
                        offset: (_branchRenames[id] ?? currentName).length,
                      ),
                onChanged: (v) => _branchRenames[id] = v,
              ),
              OutlinedButton(
                onPressed:
                    _branchBusy ||
                        (_branchRenames[id] ?? currentName).trim().isEmpty
                    ? null
                    : () => _manageBranch(
                        'update',
                        id,
                        _branchRenames[id] ?? currentName,
                      ),
                child: const Text('حفظ الاسم'),
              ),
              OutlinedButton(
                onPressed: _branchBusy
                    ? null
                    : () => _confirmBranch(
                        'أرشفة الفرع',
                        'سيتم إيقاف الفرع مع الاحتفاظ بسجلاته ومهامه. هل تريد المتابعة؟',
                        'أرشفة',
                        () => _manageBranch('archive', id),
                      ),
                child: const Text('أرشفة الفرع'),
              ),
              TextButton(
                onPressed: _branchBusy
                    ? null
                    : () => _confirmBranch(
                        'حذف الفرع نهائيًا',
                        'لا يمكن التراجع عن حذف الفرع. إذا كان مرتبطًا بمهام أو موظفين سيرفض النظام العملية. اكتب اسم الفرع للتأكيد.',
                        'حذف نهائي',
                        () => _manageBranch('delete', id),
                        requiredText: currentName,
                      ),
                child: const Text(
                  'حذف الفرع نهائيًا',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
            if (_can('branches.manage') && !active)
              OutlinedButton(
                onPressed: _branchBusy
                    ? null
                    : () => _manageBranch('activate', id),
                child: const Text('إعادة تفعيل الفرع'),
              ),
          ],
        ),
    );
  }

  Future<void> _confirmBranch(
    String title,
    String message,
    String action,
    Future<void> Function() confirm, {
    String? requiredText,
  }) async {
    final input = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.right),
            if (requiredText != null)
              TextField(
                controller: input,
                decoration: const InputDecoration(
                  labelText: 'اسم الفرع حرفيًا',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              ctx,
              requiredText == null || input.text.trim() == requiredText,
            ),
            child: Text(action, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    input.dispose();
    if (accepted == true) await confirm();
  }

  Future<void> _manageBranch(
    String action, [
    String? branchId,
    String? branchName,
  ]) async {
    if (!_can('branches.manage') ||
        _organizationId == null ||
        _organizationId!.isEmpty) {
      setState(() {
        _branchError = 'تعذر تحديد المؤسسة أو لا تملك صلاحية إدارة الفروع.';
        _branchNotice = null;
      });
      return;
    }
    setState(() {
      _branchBusy = true;
      _branchError = null;
      _branchNotice = null;
    });
    try {
      final db = Supabase.instance.client;
      final generatedBranchCode = _newBranchCode.trim().isEmpty
          ? 'BR${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}'
          : _newBranchCode.trim().toUpperCase();
      if (action == 'delete') {
        await db.rpc(
          'admin_delete_branch',
          params: {
            'p_organization_id': _organizationId,
            'p_branch_id': branchId,
          },
        );
      } else {
        await db.functions.invoke(
          'employee-code-auth',
          body: {
            'action': 'manage_branch',
            'branchAction': action,
            'branchId': branchId,
            'code': action == 'create' ? generatedBranchCode : null,
            'name': action == 'create'
                ? _newBranchName.trim()
                : action == 'update'
                ? branchName?.trim()
                : null,
          },
        );
      }
      if (!mounted) return;
      setState(() {
        _branchNotice = action == 'create'
            ? 'تمت إضافة الفرع وإنشاء كوده تلقائيًا.'
            : action == 'update'
            ? 'تم تعديل اسم الفرع.'
            : action == 'archive'
            ? 'تمت أرشفة الفرع وإيقاف استخدامه.'
            : action == 'activate'
            ? 'تمت إعادة تفعيل الفرع.'
            : 'تم حذف الفرع نهائيًا.';
        if (action == 'create') {
          _newBranchCode = '';
          _newBranchName = '';
        }
      });
      await _load();
    } catch (e) {
      if (mounted)
        setState(
          () => _branchError = e.toString().contains('403')
              ? 'لا تملك صلاحية إدارة الفروع.'
              : 'تعذر تنفيذ العملية. تحقق من صلاحية الفرع أو تكرار الكود.',
        );
    } finally {
      if (mounted) setState(() => _branchBusy = false);
    }
  }

  Widget _back() => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      onPressed: () => setState(() => _section = 'overview'),
      icon: const Icon(Icons.arrow_forward),
      label: const Text('العودة إلى لوحة الإدارة'),
    ),
  );
  Widget _record(Map<String, dynamic> row) {
    final rawHeadline = _text(
      row['title'] ??
          row['name'] ??
          row['display_name'] ??
          row['report_title'] ??
          row['action'] ??
          row['id'],
    );
    final headline = _section == 'activity'
        ? uiActivityLabel(rawHeadline)
        : rawHeadline;
    final details = <String>[];
    for (final key in [
      'status',
      'priority',
      'branch_level',
      'employee_no',
      'code',
      'role_code',
    ]) {
      if (row[key] != null) details.add(_text(row[key]));
    }
    final when = row['due_at'] ?? row['submitted_at'] ?? row['created_at'];
    if (when != null) details.add(_date(when));
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.circle, size: 9, color: AppColors.green),
      title: Text(headline, textAlign: TextAlign.right),
      subtitle: Text(
        details.isEmpty ? 'سجل متاح وفق صلاحياتك' : details.join(' · '),
        textAlign: TextAlign.right,
      ),
    );
  }
}
