import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _client = Supabase.instance.client;
  bool _busy = true;
  String? _error;
  String? _submissionError;
  String? _roleReportError;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _submissionRows = [];
  List<Map<String, dynamic>> _roleReportRows = [];
  Map<String, Map<String, dynamic>> _tasksById = {};
  Map<String, String> _employeeNames = {};
  Map<String, Map<String, dynamic>> _snapshotsById = {};
  Map<String, Map<String, String>> _submissionFieldLabels = {};
  bool _canRead = false;
  bool _canReview = false;
  bool _canReviewRoleReports = false;
  bool _canReviewSubmissions = false;
  bool _canApproveSubmissions = false;
  final Set<String> _saving = {};
  String _filter = 'all';
  String _stream = 'tasks';
  final _searchController = TextEditingController();
  String _search = '';
  final Map<String, TextEditingController> _submissionNotes = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _submissionNotes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : <Map<String, dynamic>>[];

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
        _submissionError = null;
        _roleReportError = null;
      });
    }
    try {
      final rawProfile = await _client.rpc('mobile_my_profile');
      final root = rawProfile is Map ? rawProfile : const <dynamic, dynamic>{};
      final employee = root['employee'];
      final rawPermissions = employee is Map ? employee['permissions'] : null;
      final organizationId = employee is Map
          ? (employee['institutionId'] ??
                  employee['institution_id'] ??
                  employee['organization_id'])
              ?.toString() ??
              ''
          : '';
      final permissions = rawPermissions is List
          ? rawPermissions.map((e) => e.toString()).toSet()
          : <String>{};
      _canRead =
          permissions.contains('reports.read_all') ||
          permissions.contains('tasks.review') ||
          permissions.contains('tasks.manage') ||
          permissions.contains('report_submissions.review') ||
          permissions.contains('report_submissions.approve');
      _canReview =
          permissions.contains('tasks.review') ||
          permissions.contains('tasks.manage');
      _canReviewRoleReports =
          permissions.contains('tasks.review') ||
          permissions.contains('reports.read_all');
      _canReviewSubmissions = permissions.contains('report_submissions.review');
      _canApproveSubmissions = permissions.contains(
        'report_submissions.approve',
      );
      if (!_canRead) {
        _rows = [];
        _submissionRows = [];
        _roleReportRows = [];
      } else {
        final data = await _client
            .from('task_reports')
            .select(
              'id,task_id,submitted_by,report_form_snapshot_id,status,submitted_at,review_note,values',
            )
            .order('submitted_at', ascending: false)
            .limit(100);
        _rows = _maps(data);
        try {
          final contextRows = await Future.wait<dynamic>([
            _client
                .from('tasks')
                .select('id,title,assigned_to,due_at')
                .eq('organization_id', organizationId)
                .isFilter('deleted_at', null)
                .limit(1000),
            _client
                .from('organization_memberships')
                .select('user_id,display_name,employee_no')
                .eq('organization_id', organizationId)
                .eq('is_active', true)
                .limit(500),
            _client
                .from('task_report_form_snapshots')
                .select('id,task_id,title,schema')
                .limit(1000),
          ]);
          _tasksById = {
            for (final task in _maps(contextRows[0]))
              if (task['id'] != null) task['id'].toString(): task,
          };
          _employeeNames = {
            for (final member in _maps(contextRows[1]))
              if (member['user_id'] != null)
                member['user_id'].toString():
                    (member['display_name'] ?? member['employee_no'] ?? 'موظف')
                        .toString(),
          };
          _snapshotsById = {
            for (final snapshot in _maps(contextRows[2]))
              if (snapshot['id'] != null)
                snapshot['id'].toString(): snapshot,
          };
        } catch (_) {
          _tasksById = {};
          _employeeNames = {};
          _snapshotsById = {};
        }
        try {
          final submissions = await _client
              .from('report_submissions')
              .select(
                'id,form_id,employee_name,branch_name,report_date,answers,status,review_note,reviewed_by_name,approved_by_name,created_at,submitted_at,form:report_form_templates(title)',
              )
              .order('report_date', ascending: false)
              .limit(200);
          _submissionRows = _maps(submissions);
          try {
            final dynamicRows = _maps(await _client
                .from('employee_dynamic_reports')
                .select('id,template_id,version_id,employee_user_id,role_code,branch_id,report_date,values,status,review_note,created_at,submitted_at')
                .eq('organization_id', organizationId)
                .order('submitted_at', ascending: false)
                .limit(200));
            _submissionRows.addAll(dynamicRows.map((row) => {
                  ...row,
                  '_source': 'dynamic',
                  'form_id': row['template_id'],
                  'employee_name': _employeeNames[row['employee_user_id']?.toString()] ?? 'موظف',
                  'branch_name': 'غير محدد',
                  'answers': row['values'],
                  'created_at': row['created_at'],
                  'submitted_at': row['submitted_at'],
                }));
          } catch (_) {
            // لا نمنع عرض مسار report_submissions إذا كانت بنية المسار الديناميكي غير منشورة.
          }
          _submissionFieldLabels = {};
          try {
            final formIds = _submissionRows
                .map((row) => row['form_id']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList();
            if (formIds.isNotEmpty) {
              final versions = _maps(await _client
                  .from('report_form_versions')
                  .select('id,template_id,version_no,status,approved_by,approved_at')
                  .inFilter('template_id', formIds)
                  .eq('status', 'published')
                  .order('version_no', ascending: false)
                  .limit(500));
              final latest = <String, Map<String, dynamic>>{};
              for (final version in versions) {
                final templateId = version['template_id']?.toString() ?? '';
                if (templateId.isNotEmpty && !latest.containsKey(templateId)) {
                  latest[templateId] = version;
                }
              }
              final versionIds = latest.values
                  .map((version) => version['id']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toList();
              if (versionIds.isNotEmpty) {
                final fields = _maps(await _client
                    .from('report_form_version_fields')
                    .select('version_id,field_key,label,sort_order')
                    .inFilter('version_id', versionIds)
                    .order('sort_order')
                    .limit(3000));
                final labelsByVersion = <String, Map<String, String>>{};
                for (final field in fields) {
                  final versionId = field['version_id']?.toString() ?? '';
                  final key = field['field_key']?.toString() ?? '';
                  final label = field['label']?.toString().trim() ?? '';
                  if (versionId.isNotEmpty && key.isNotEmpty && label.isNotEmpty) {
                    labelsByVersion.putIfAbsent(versionId, () => {})[key] = label;
                  }
                }
                for (final entry in latest.entries) {
                  final versionId = entry.value['id']?.toString() ?? '';
                  final labels = labelsByVersion[versionId];
                  if (labels != null) _submissionFieldLabels[entry.key] = labels;
                }
              }
            }
          } catch (_) {
            // عرض التقرير لا يتوقف إذا تعذر جلب عناوين الحقول؛ نعرض المفتاح كبديل.
          }
          _submissionError = null;
        } catch (_) {
          _submissionRows = [];
          _submissionError = 'تعذر تحميل التقارير المستقلة من قاعدة البيانات. تحقق من الاتصال وسياسات الوصول ثم حدّث القائمة.';
        }
        try {
          final roleReports = await _client
              .from('employee_role_reports')
              .select(
                'id,organization_id,employee_user_id,role_code,branch_id,report_date,report_title,values,status,submitted_at,review_note',
              )
              .order('submitted_at', ascending: false)
              .limit(200);
          _roleReportRows = _maps(roleReports);
          _roleReportError = null;
        } catch (_) {
          _roleReportRows = [];
          _roleReportError = 'تعذر تحميل تقارير الأدوار اليومية. تحقق من الاتصال وسياسات الوصول ثم حدّث القائمة.';
        }
      }
      _error = null;
    } catch (_) {
      _error = 'تعذر تحميل تقارير المهام. تحقق من الاتصال وصلاحيات حسابك.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _safeId(Object? raw) {
    final id = raw?.toString() ?? '';
    if (id.isEmpty) return 'غير متاح';
    return id.length <= 8 ? id : '${id.substring(0, 8)}…';
  }

  Map<String, dynamic>? _taskFor(Map<String, dynamic> row) {
    final id = row['task_id']?.toString();
    return id == null ? null : _tasksById[id];
  }

  String _employeeForTask(Map<String, dynamic> row) {
    final task = _taskFor(row);
    final assignedId = task?['assigned_to']?.toString();
    final submittedId = row['submitted_by']?.toString();
    final assignedName = assignedId == null ? null : _employeeNames[assignedId];
    final submittedName =
        submittedId == null ? null : _employeeNames[submittedId];
    final knownName = assignedName ?? submittedName;
    if (knownName != null && knownName.trim().isNotEmpty) return knownName;
    return (assignedId ?? submittedId ?? '').isEmpty
        ? 'غير محدد'
        : 'موظف غير معروف';
  }

  String _formattedDate(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return 'غير متاح';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _snapshotTitle(Map<String, dynamic> row) {
    final snapshotId = row['report_form_snapshot_id']?.toString();
    final snapshot = snapshotId == null ? null : _snapshotsById[snapshotId];
    final title = snapshot?['title']?.toString().trim() ?? '';
    return title.isEmpty ? 'تقرير المهمة' : title;
  }

  String _label(Map<String, dynamic> row) {
    final task = _taskFor(row);
    if (task == null) {
      return row['task_id'] == null
          ? 'تقرير مستقل'
          : 'تقرير المهمة ${_safeId(row['task_id'])}';
    }
    return task['title']?.toString().trim().isNotEmpty == true
        ? task['title'].toString()
        : 'مهمة ${_safeId(row['task_id'])}';
  }

  String _statusLabel(String status) => switch (status) {
    'submitted' => 'بانتظار المراجعة',
    'reviewed' => 'بانتظار الاعتماد',
    'approved' => 'معتمد نهائياً',
    'rejected' => 'مرفوض — يحتاج استكمالًا',
    'returned' => 'معاد للموظف',
    'draft' => 'مسودة',
    _ => 'حالة التقرير: $status',
  };

  bool _matchesSearch(Map<String, dynamic> row) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return true;
    final values = <Object?>[
      row['id'],
      row['task_id'],
      row['employee_name'],
      row['branch_name'],
      row['role_code'],
      row['report_title'],
      row['report_date'],
      row['status'],
      row['values'],
      row['answers'],
      _label(row),
      _employeeForTask(row),
      _taskFor(row)?['due_at'],
    ];
    return values.any(
      (value) => value.toString().toLowerCase().contains(query),
    );
  }

  String _csvCell(Object? value) {
    var text = value is Map || value is List
        ? jsonEncode(value)
        : (value?.toString() ?? '');
    text = text.replaceAll('"', '""');
    return '"$text"';
  }

  String _csvFor(List<Map<String, dynamic>> rows) {
    final columns = switch (_stream) {
      'role_reports' => <String>[
        'report_title',
        'role_code',
        'branch_id',
        'employee_user_id',
        'report_date',
        'status',
        'submitted_at',
        'review_note',
        'values',
      ],
      'submissions' => <String>[
        'employee_name',
        'branch_name',
        'report_date',
        'status',
        'review_note',
        'answers',
      ],
      _ => <String>[
        'id',
        'task_id',
        'report_form_snapshot_id',
        'status',
        'submitted_at',
        'review_note',
        'values',
      ],
    };
    return <String>[
      columns.map(_csvCell).join(','),
      ...rows.map(
        (row) => columns.map((column) => _csvCell(row[column])).join(','),
      ),
    ].join('\n');
  }

  Future<void> _copyCsv(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد تقارير مطابقة للتصدير.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: _csvFor(rows)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم نسخ ${rows.length} تقرير إلى الحافظة بصيغة CSV.'),
        ),
      );
    }
  }

  Future<void> _saveCsv(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد تقارير مطابقة للتصدير.')),
      );
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF${_csvFor(rows)}'));
    final path = await FilePicker.saveFile(
      dialogTitle: 'حفظ تقارير الشاعري بصيغة CSV',
      fileName: 'alshaeri-reports-${DateTime.now().millisecondsSinceEpoch}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
    );
    if (mounted && path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ ${rows.length} تقرير في ملف CSV.')),
      );
    }
  }

  Future<void> _review(Map<String, dynamic> row, String decision) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _saving.contains(id)) return;
    final isFormReport = row['report_form_snapshot_id'] != null;
    final noteController = TextEditingController(
      text: row['review_note']?.toString() ?? '',
    );
    final isReturn = decision == 'returned' || decision == 'rejected';
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isReturn ? 'إعادة التقرير للموظف' : 'اعتماد التقرير'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isReturn
                  ? 'اكتب سبب الإعادة ليتمكن الموظف من استكمال التقرير.'
                  : 'يمكنك إضافة ملاحظة للمراجعة (اختياري).',
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              autofocus: true,
              maxLines: 4,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'ملاحظة المراجعة',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = noteController.text.trim();
              if (isReturn && value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: Text(isReturn ? 'تأكيد الإعادة' : 'تأكيد الاعتماد'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (note == null || !mounted) return;
    if (isReturn && note.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اكتب سبب إعادة التقرير.')));
      return;
    }
    setState(() {
      _saving.add(id);
      _error = null;
    });
    try {
      if (isFormReport) {
        await _client.rpc(
          'mobile_review_task_form_report',
          params: {
            'p_report_id': id,
            'p_decision': decision,
            'p_note': note.trim().isEmpty ? null : note.trim(),
          },
        );
      } else {
        await _client.rpc(
          'mobile_review_task',
          params: {
            'p_task_id': row['task_id'],
            'p_decision': decision,
            'p_note': note.trim().isEmpty ? null : note.trim(),
          },
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isReturn ? 'تمت إعادة التقرير للموظف.' : 'تم اعتماد التقرير.',
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'تعذر تنفيذ المراجعة. قد لا تملك الصلاحية المطلوبة أو ربما تغيرت حالة التقرير؛ حدّث القائمة وحاول مجددًا.',
        );
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  Future<void> _changeSubmissionStatus(
    Map<String, dynamic> row,
    String status,
  ) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _saving.contains(id)) return;
    final note =
        (_submissionNotes[id]?.text ?? row['review_note']?.toString() ?? '')
            .trim();
    if (status == 'returned' && note.isEmpty) {
      setState(() => _submissionError = 'اكتب سبب إعادة التقرير.');
      return;
    }
    setState(() {
      _saving.add(id);
      _submissionError = null;
    });
    try {
      await _client
          .from('report_submissions')
          .update({'status': status, 'review_note': note.isEmpty ? null : note})
          .eq('id', id)
          .select('id')
          .single();
      if (!mounted) return;
      final message = status == 'reviewed'
          ? 'تمت المراجعة وإحالة التقرير للاعتماد.'
          : status == 'approved'
          ? 'تم الاعتماد النهائي.'
          : 'تمت إعادة التقرير للموظف.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } catch (_) {
      if (mounted)
        setState(
          () => _submissionError = 'تعذر تنفيذ الإجراء؛ قد تمنع سياسات قاعدة البيانات الحفظ أو لا تملك الصلاحية، أو ربما تغيرت حالة التقرير. حدّث القائمة وحاول مجددًا.',
        );
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  Future<void> _reviewRoleReport(
    Map<String, dynamic> row,
    String decision,
  ) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _saving.contains(id)) return;
    final isReturn = decision == 'returned';
    final noteController = TextEditingController(
      text: row['review_note']?.toString() ?? '',
    );
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isReturn ? 'إعادة تقرير الدور للموظف' : 'اعتماد تقرير الدور',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isReturn
                  ? 'اكتب سبب الإعادة (حرفان على الأقل) ليتمكن الموظف من استكمال التقرير.'
                  : 'يمكنك إضافة ملاحظة للمراجعة (اختياري).',
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              autofocus: true,
              maxLines: 4,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'ملاحظة المراجعة',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = noteController.text.trim();
              if (isReturn && value.length < 2) return;
              Navigator.pop(dialogContext, value);
            },
            child: Text(isReturn ? 'تأكيد الإعادة' : 'تأكيد الاعتماد'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (note == null || !mounted) return;
    if (isReturn && note.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب سبب الإعادة بحرفين على الأقل.')),
      );
      return;
    }
    setState(() {
      _saving.add(id);
      _roleReportError = null;
    });
    try {
      await _client.rpc(
        'review_employee_role_report',
        params: {
          'p_report_id': id,
          'p_decision': decision,
          'p_note': note.trim().isEmpty ? null : note.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isReturn
                ? 'تمت إعادة تقرير الدور للموظف.'
                : 'تم اعتماد تقرير الدور.',
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (mounted)
        setState(
          () => _roleReportError = 'تعذر تنفيذ مراجعة تقرير الدور. تحقق من الصلاحية أو حالة التقرير، ثم حدّث القائمة وحاول مجددًا.',
        );
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  bool _pastDraftDeadline(Map<String, dynamic> row) {
    final raw = row['created_at'] ?? row['submitted_at'];
    final created = raw == null ? null : DateTime.tryParse(raw.toString());
    return created != null && DateTime.now().toUtc().isAfter(
      created.toUtc().add(const Duration(hours: 24)),
    );
  }

  Future<void> _finalizeDraft(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _saving.contains(id)) return;
    final isDynamic = row['_source'] == 'dynamic';
    if (isDynamic ? !_canReview : !_canReviewSubmissions) return;
    if (!_pastDraftDeadline(row)) {
      setState(() => _submissionError = 'لا يمكن الترحيل النيابي قبل مرور 24 ساعة على إنشاء المسودة.');
      return;
    }
    setState(() {
      _saving.add(id);
      _submissionError = null;
    });
    try {
      await _client.rpc(
        isDynamic ? 'finalize_employee_dynamic_report' : 'finalize_report_submission',
        params: {'p_report_id': id},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم ترحيل التقرير نهائيًا نيابةً عن الموظف وإحالته للمراجعة.')),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _submissionError = 'تعذر الترحيل النهائي النيابي: ${error.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  String _displayValue(Object? value) {
    if (value == null) return '—';
    if (value is Map && value['strokes'] is List) {
      return value['acknowledged'] == true ? 'تم التوقيع والموافقة' : 'توقيع مرفق';
    }
    if (value is Map || value is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(value);
      } catch (_) {
        return 'قيمة غير قابلة للعرض';
      }
    }
    return value.toString();
  }

  String _submissionFieldLabel(Map<String, dynamic> row, Object? key) {
    final formId = row['form_id']?.toString() ?? '';
    return _submissionFieldLabels[formId]?[key.toString()] ?? key.toString();
  }

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'تقارير الموظفين',
    subtitle: 'تقارير المهام والتقارير المستقلة الظاهرة وفق صلاحيات حسابك',
    child: RefreshIndicator(
      onRefresh: _load,
      child: _busy
          ? const Center(child: CircularProgressIndicator())
          : !_canRead
          ? ListView(
              children: const [
                SizedBox(height: 100),
                Center(child: Text('لا تملك صلاحية قراءة تقارير المؤسسة.')),
              ],
            )
          : _buildReportList(),
    ),
  );

  Widget _buildReportList() {
    final rows = _rows
        .where((row) => _filter == 'all' || row['status'] == _filter)
        .where(_matchesSearch)
        .toList();
    final submissions = _submissionRows
        .where((row) => _filter == 'all' || row['status'] == _filter)
        .where(_matchesSearch)
        .toList();
    final roleReports = _roleReportRows
        .where((row) => _filter == 'all' || row['status'] == _filter)
        .where(_matchesSearch)
        .toList();
    final exportRows = _stream == 'tasks'
        ? rows
        : _stream == 'submissions'
        ? submissions
        : roleReports;
    final error = _stream == 'tasks'
        ? _error
        : _stream == 'submissions'
        ? _submissionError
        : _roleReportError;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'تقارير الموظفين',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'تظهر هنا تقارير المهام المرتبطة بالجدول الموحد أو المهام الإدارية. يرفع الموظف التقرير من داخل المهمة، وتتم المراجعة والاعتماد من نفس المسار.',
            textAlign: TextAlign.right,
          ),
        ),
        if (_stream == 'tasks') ...[
          const Text(
            'مراجعة تقارير المهام',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'تُستخدم صلاحيات tasks.review / tasks.manage للمراجعة؛ وتتحقق قاعدة البيانات من صلاحية المستخدم وحالة التقرير عند الحفظ.',
              textAlign: TextAlign.right,
            ),
          ),
        ] else if (_stream == 'submissions') ...[
          const Text(
            'التقارير المستقلة',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'محمد يراجع التقرير أولاً، ثم عبدالرحمن يعتمد التقرير نهائياً. تُطبّق تحديثات الحالة عبر صلاحيات قاعدة البيانات.',
              textAlign: TextAlign.right,
            ),
          ),
        ] else ...[
          const Text(
            'تقارير الأدوار اليومية المستقلة',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'هذه التقارير مستقلة عن المهام ومصمم التقارير. تتطلب المراجعة tasks.review أو reports.read_all وتتحقق قاعدة البيانات من الصلاحية.',
              textAlign: TextAlign.right,
            ),
          ),
        ],
        if (error != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              error,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.red),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _load,
              child: const Text('إعادة المحاولة'),
            ),
          ),
        ],
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          children:
              (_stream == 'tasks'
                      ? <(String, String)>[
                          ('all', 'الكل'),
                          ('submitted', 'بانتظار المراجعة'),
                          ('approved', 'معتمدة'),
                          ('returned', 'معادة'),
                          ('rejected', 'مرفوضة'),
                        ]
                      : <(String, String)>[
                          ('all', 'الكل'),
                          ('submitted', 'بانتظار المراجعة'),
                          if (_stream == 'submissions')
                            ('reviewed', 'بانتظار الاعتماد'),
                          ('approved', 'معتمدة'),
                          ('returned', 'معادة'),
                        ])
                  .map(
                    (item) => ChoiceChip(
                      label: Text(item.$2),
                      selected: _filter == item.$1,
                      onSelected: (_) => setState(() => _filter = item.$1),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchController,
          textAlign: TextAlign.right,
          onChanged: (value) => setState(() => _search = value),
          decoration: InputDecoration(
            labelText: 'بحث داخل التقارير الحالية',
            hintText: 'اسم الموظف، الفرع، الدور، الرقم أو قيمة التقرير',
            prefixIcon: _search.isEmpty
                ? const Icon(Icons.search)
                : IconButton(
                    tooltip: 'مسح البحث',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _search = '');
                    },
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _saveCsv(exportRows),
                icon: const Icon(Icons.download_outlined),
                label: const Text('حفظ CSV كملف'),
              ),
              TextButton.icon(
                onPressed: () => _copyCsv(exportRows),
                icon: const Icon(Icons.content_copy_outlined),
                label: const Text('نسخ CSV إلى الحافظة'),
              ),
            ],
          ),
        ),
        if (_stream == 'tasks') ...[
          if (_error == null && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('لا توجد تقارير في هذه القائمة.')),
            ),
          for (final row in rows) _reportCard(row),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'نطاق تقارير المهام: تقارير المهام legacy ومتعددة النماذج. التقارير اليومية المستقلة والتحليلات وإرساليات التقارير الديناميكية ليست ضمن هذا المسار.',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ] else if (_stream == 'submissions') ...[
          if (_submissionError == null && submissions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('لا توجد تقارير في هذه القائمة.')),
            ),
          for (final row in submissions) _submissionCard(row),
        ] else ...[
          if (_roleReportError == null && roleReports.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('لا توجد تقارير في هذه القائمة.')),
            ),
          for (final row in roleReports) _roleReportCard(row),
        ],
      ],
    );
  }

  Widget _roleReportCard(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final status = row['status']?.toString() ?? 'غير معروف';
    final values = row['values'];
    final actionable =
        status == 'submitted' && _canReviewRoleReports && id.isNotEmpty;
    return Card(
      child: ExpansionTile(
        title: Text(
          row['report_title']?.toString() ?? 'تقرير دور',
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        subtitle: Text(
          'الدور: ${row['role_code'] ?? 'غير محدد'} · الفرع: ${_safeId(row['branch_id'])} · التاريخ: ${_formattedDate(row['report_date'])}\nالموظف: ${_employeeNames[row['employee_user_id']?.toString()] ?? 'موظف غير معروف'} · ${_statusLabel(status)}',
          textAlign: TextAlign.right,
        ),
        children: [
          if (values is Map && values.isNotEmpty)
            for (final entry in values.entries)
              ListTile(
                title: Text(entry.key.toString(), textAlign: TextAlign.right),
                subtitle: Text(
                  _displayValue(entry.value),
                  textAlign: TextAlign.right,
                ),
              ),
          if (values is! Map || values.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'لا توجد قيم قابلة للعرض.',
                textAlign: TextAlign.right,
              ),
            ),
          if ((row['review_note'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'ملاحظة المراجعة: ${row['review_note']}',
                textAlign: TextAlign.right,
              ),
            ),
          if (actionable)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _saving.contains(id)
                        ? null
                        : () => _reviewRoleReport(row, 'returned'),
                    child: const Text('إعادة مع ملاحظة'),
                  ),
                  FilledButton(
                    onPressed: _saving.contains(id)
                        ? null
                        : () => _reviewRoleReport(row, 'approved'),
                    child: Text(
                      _saving.contains(id) ? 'جارٍ الحفظ…' : 'اعتماد التقرير',
                    ),
                  ),
                ],
              ),
            ),
          if (status == 'submitted' && !_canReviewRoleReports)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'للقراءة فقط: لا تملك صلاحية مراجعة تقارير الأدوار.',
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }

  Widget _submissionCard(Map<String, dynamic> row) {
    if (row['_source'] == 'dynamic') return _dynamicSubmissionCard(row);
    final status = row['status']?.toString() ?? 'غير معروف';
    final id = row['id']?.toString() ?? '';
    final formValue = row['form'];
    final form = formValue is Map ? formValue : const <dynamic, dynamic>{};
    final canReview = status == 'submitted' && _canReviewSubmissions;
    final canApprove = status == 'reviewed' && _canApproveSubmissions;
    final actionable = (canReview || canApprove) && id.isNotEmpty;
    final noteController = _submissionNotes.putIfAbsent(
      id,
      () => TextEditingController(text: row['review_note']?.toString() ?? ''),
    );
    return Card(
      child: ExpansionTile(
        title: Text(
          (form['title'] ?? 'نموذج تقرير').toString(),
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        subtitle: Text(
          'الموظف: ${row['employee_name'] ?? 'غير محدد'} · الفرع: ${row['branch_name'] ?? 'غير محدد'}\nالتاريخ: ${row['report_date'] ?? 'غير محدد'} · ${_statusLabel(status)}',
          textAlign: TextAlign.right,
        ),
        children: [
          if (row['answers'] is Map)
            for (final entry in (row['answers'] as Map).entries)
              ListTile(
                title: Text(
                  _submissionFieldLabel(row, entry.key),
                  textAlign: TextAlign.right,
                ),
                leading: Text(
                  entry.key.toString(),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Colors.black45, fontSize: 11),
                ),
                subtitle: Text(
                  _displayValue(entry.value),
                  textAlign: TextAlign.right,
                ),
              ),
          if (row['answers'] is! Map || (row['answers'] as Map).isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'لا توجد إجابات قابلة للعرض.',
                textAlign: TextAlign.right,
              ),
            ),
          if ((row['reviewed_by_name'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'المراجع: ${row['reviewed_by_name']}',
                textAlign: TextAlign.right,
              ),
            ),
          if ((row['approved_by_name'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'المعتمد: ${row['approved_by_name']}',
                textAlign: TextAlign.right,
              ),
            ),
          if ((row['review_note'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'ملاحظة: ${row['review_note']}',
                textAlign: TextAlign.right,
              ),
            ),
          if (actionable)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    textAlign: TextAlign.right,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'ملاحظة أو سبب الإعادة',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (canReview)
                    FilledButton(
                      onPressed: _saving.contains(id)
                          ? null
                          : () => _changeSubmissionStatus(row, 'reviewed'),
                      child: Text(
                        _saving.contains(id)
                            ? 'جارٍ الحفظ…'
                            : 'اعتماد المراجعة وإحالة التقرير',
                      ),
                    ),
                  if (canApprove)
                    FilledButton(
                      onPressed: _saving.contains(id)
                          ? null
                          : () => _changeSubmissionStatus(row, 'approved'),
                      child: Text(
                        _saving.contains(id)
                            ? 'جارٍ الحفظ…'
                            : 'اعتماد التقرير نهائياً',
                      ),
                    ),
                  OutlinedButton(
                    onPressed:
                        _saving.contains(id) ||
                            noteController.text.trim().isEmpty
                        ? null
                        : () => _changeSubmissionStatus(row, 'returned'),
                    child: const Text('إعادة التقرير للموظف'),
                  ),
                ],
              ),
            ),
          if (status == 'draft' && _canReviewSubmissions)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _pastDraftDeadline(row)
                        ? 'مضى أكثر من 24 ساعة — التقرير غير مرحّل نهائيًا.'
                        : 'تبقى المسودة قابلة للإكمال لدى الموظف حتى مرور 24 ساعة.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _pastDraftDeadline(row) ? Colors.deepOrange : Colors.black54,
                      fontWeight: _pastDraftDeadline(row) ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: id.isEmpty || _saving.contains(id) || !_pastDraftDeadline(row)
                        ? null
                        : () => _finalizeDraft(row),
                    child: const Text('ترحيل نهائي نيابةً عن الموظف'),
                  ),
                ],
              ),
            ),
          if (status == 'submitted' && !_canReviewSubmissions)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'للقراءة فقط: لا تملك صلاحية report_submissions.review.',
                textAlign: TextAlign.right,
              ),
            ),
          if (status == 'reviewed' && !_canApproveSubmissions)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'للقراءة فقط: لا تملك صلاحية report_submissions.approve.',
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }

  Widget _dynamicSubmissionCard(Map<String, dynamic> row) {
    final answers = row['answers'];
    final id = row['id']?.toString() ?? '';
    final status = row['status']?.toString() ?? 'غير معروف';
    return Card(
      child: ExpansionTile(
        title: const Text(
          'تقرير ديناميكي مرتبط بالقالب',
          textAlign: TextAlign.right,
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy),
        ),
        subtitle: Text(
          'الموظف: ${row['employee_name'] ?? 'غير محدد'} · الدور: ${row['role_code'] ?? 'غير محدد'}\nالتاريخ: ${row['report_date'] ?? 'غير محدد'} · ${_statusLabel(status)}',
          textAlign: TextAlign.right,
        ),
        children: [
          if (answers is Map)
            for (final entry in answers.entries)
              ListTile(
                title: Text(_submissionFieldLabel(row, entry.key), textAlign: TextAlign.right),
                leading: Text(entry.key.toString(), textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.black45, fontSize: 11)),
                subtitle: Text(_displayValue(entry.value), textAlign: TextAlign.right),
              ),
          if (answers is! Map || answers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('لا توجد إجابات قابلة للعرض.', textAlign: TextAlign.right),
            ),
          if (status == 'draft' && _canReview)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _pastDraftDeadline(row)
                        ? 'مضى أكثر من 24 ساعة — التقرير غير مرحّل نهائيًا.'
                        : 'تبقى المسودة قابلة للإكمال لدى الموظف حتى مرور 24 ساعة.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _pastDraftDeadline(row) ? Colors.deepOrange : Colors.black54,
                      fontWeight: _pastDraftDeadline(row) ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: id.isEmpty || _saving.contains(id) || !_pastDraftDeadline(row)
                        ? null
                        : () => _finalizeDraft(row),
                    child: const Text('ترحيل نهائي نيابةً عن الموظف'),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('هذا التقرير محفوظ عبر المسار الديناميكي. تبقى المسودة قابلة للتعديل، ثم تُحال للمراجعة بعد الترحيل النهائي.', textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? 'غير معروف';
    final id = row['id']?.toString() ?? '';
    final canAct =
        _canReview &&
        status == 'submitted' &&
        id.isNotEmpty &&
        row['task_id'] != null;
    final isForm = row['report_form_snapshot_id'] != null;
    final task = _taskFor(row);
    final employeeName = _employeeForTask(row);
    return Card(
      child: ExpansionTile(
        title: Text(
          _label(row),
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        subtitle: Text(
          'الموظف: $employeeName\n'
          'الإرسال: ${_formattedDate(row['submitted_at'])} · '
          'الاستحقاق: ${_formattedDate(task?['due_at'])} · ${_statusLabel(status)}',
          textAlign: TextAlign.right,
        ),
        children: [
          if (isForm)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'القالب: ${_snapshotTitle(row)}',
                textAlign: TextAlign.right,
              ),
            ),
          if (row['review_note'] != null &&
              row['review_note'].toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'ملاحظة المراجعة: ${row['review_note']}',
                textAlign: TextAlign.right,
              ),
            ),
          if (row['values'] is Map)
            for (final entry in (row['values'] as Map).entries)
              ListTile(
                title: Text(entry.key.toString(), textAlign: TextAlign.right),
                subtitle: Text(
                  _displayValue(entry.value),
                  textAlign: TextAlign.right,
                ),
              ),
          if (row['values'] is! Map)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'لا توجد إجابات قابلة للعرض.',
                textAlign: TextAlign.right,
              ),
            ),
          if (canAct && isForm)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _saving.contains(id)
                        ? null
                        : () => _review(row, 'returned'),
                    child: const Text('إعادة مع ملاحظة'),
                  ),
                  FilledButton(
                    onPressed: _saving.contains(id)
                        ? null
                        : () => _review(row, 'approved'),
                    child: Text(
                      _saving.contains(id) ? 'جارٍ الحفظ…' : 'اعتماد التقرير',
                    ),
                  ),
                ],
              ),
            ),
          if (canAct && !isForm)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _saving.contains(id)
                        ? null
                        : () => _review(row, 'rejected'),
                    child: const Text('رفض مع ملاحظة'),
                  ),
                  FilledButton(
                    onPressed: _saving.contains(id)
                        ? null
                        : () => _review(row, 'approved'),
                    child: Text(
                      _saving.contains(id) ? 'جارٍ الحفظ…' : 'اعتماد التقرير',
                    ),
                  ),
                ],
              ),
            ),
          if (status == 'submitted' && !_canReview)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'للقراءة فقط: لا تملك صلاحية مراجعة تقارير المهام.',
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }
}
