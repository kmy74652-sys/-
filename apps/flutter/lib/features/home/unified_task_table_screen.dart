import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_shell.dart';
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
  List<String> _branches = const [];
  List<UnifiedReportOption> _reports = const [];

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
            .select('name')
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
            .map((row) => (row['name'] ?? '').toString())
            .where((name) => name.isNotEmpty)
            .toList();
        _reports = reports;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
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
    final requested = draft.employee.trim();
    final selected = requested == 'مهام مشتركة'
        ? members
        : members
            .where((row) =>
                (row['display_name'] ?? '').toString().trim() == requested)
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
    var branchId = _defaultBranchId;
    if (draft.branch.trim().isNotEmpty) {
      final branches = (await _db
              .from('branches')
              .select('id,name')
              .eq('organization_id', organizationId)
              .eq('is_active', true)
              .limit(200) as List)
          .whereType<Map>();
      for (final row in branches) {
        if ((row['name'] ?? '').toString().trim() == draft.branch.trim()) {
          branchId = row['id']?.toString();
        }
      }
    }
    final due = DateTime.tryParse(draft.startDate)?.toUtc() ??
        DateTime.now().toUtc().add(const Duration(days: 1));
    for (final member in selected) {
      final userId = member['user_id']?.toString();
      if (userId == null || userId.isEmpty) continue;
      for (final row in draft.rows) {
        final description = [
          'المسمى الوظيفي: ${draft.role}',
          if (draft.branch.isNotEmpty) 'الفرع: ${draft.branch}',
          if (draft.startDate.isNotEmpty)
            'تاريخ بدء التطبيق: ${draft.startDate}',
          'ساعات الدوام: ${draft.workType} · ${draft.workDays} · الاستثناء الأسبوعي: ${draft.weeklyException}',
          if (draft.purpose.isNotEmpty) 'الهدف من الوظيفة: ${draft.purpose}',
          'الوقت المحدد: ${row.time.isEmpty ? 'غير محدد' : row.time}',
          if (row.output.isNotEmpty) 'المخرج المطلوب: ${row.output}',
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
          'p_title': row.task,
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
      }
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
                    ],
                  ),
      );
}
