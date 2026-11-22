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
              'id,task_id,report_form_snapshot_id,status,submitted_at,review_note,values',
            )
            .order('submitted_at', ascending: false)
            .limit(100);
        _rows = _maps(data);
        try {
          final submissions = await _client
              .from('report_submissions')
              .select(
                'id,employee_name,branch_name,report_date,answers,status,review_note,reviewed_by_name,approved_by_name,form:report_form_templates(title)',
              )
              .neq('status', 'draft')
              .order('report_date', ascending: false)
              .limit(200);
          _submissionRows = _maps(submissions);
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

  String _label(Map<String, dynamic> row) => row['task_id'] == null
      ? 'تقرير مستقل'
      : 'تقرير المهمة ${_safeId(row['task_id'])}';

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
    final path = await FilePicker.platform.saveFile(
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

  String _displayValue(Object? value) {
    if (value == null) return '—';
    if (value is Map || value is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(value);
      } catch (_) {
        return 'قيمة غير قابلة للعرض';
      }
    }
    return value.toString();
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
          'مصادر التقارير',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('تقارير المهام'),
              selected: _stream == 'tasks',
              onSelected: (_) => setState(() {
                _stream = 'tasks';
                _filter = 'all';
              }),
            ),
            ChoiceChip(
              label: const Text('التقارير المستقلة'),
              selected: _stream == 'submissions',
              onSelected: (_) => setState(() {
                _stream = 'submissions';
                _filter = 'all';
              }),
            ),
            ChoiceChip(
              label: const Text('تقارير الأدوار اليومية'),
              selected: _stream == 'role_reports',
              onSelected: (_) => setState(() {
                _stream = 'role_reports';
                _filter = 'all';
              }),
            ),
          ],
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
          'الدور: ${row['role_code'] ?? 'غير محدد'} · الفرع: ${_safeId(row['branch_id'])} · التاريخ: ${row['report_date'] ?? 'غير محدد'}\nالموظف: ${_safeId(row['employee_user_id'])} · ${_statusLabel(status)}',
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
                title: Text(entry.key.toString(), textAlign: TextAlign.right),
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

  Widget _reportCard(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? 'غير معروف';
    final id = row['id']?.toString() ?? '';
    final canAct =
        _canReview &&
        status == 'submitted' &&
        id.isNotEmpty &&
        row['task_id'] != null;
    final isForm = row['report_form_snapshot_id'] != null;
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
          '${_statusLabel(status)} · ${row['submitted_at'] ?? 'وقت الإرسال غير متاح'}',
          textAlign: TextAlign.right,
        ),
        children: [
          if (isForm)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'تقرير مرتبط بنموذج مهمة متعدد النماذج.',
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
