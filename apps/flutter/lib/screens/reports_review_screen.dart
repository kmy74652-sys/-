import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportsReviewScreen extends StatefulWidget {
  const ReportsReviewScreen({super.key, required this.profile});
  final Map<String, dynamic> profile;

  @override
  State<ReportsReviewScreen> createState() => _ReportsReviewScreenState();
}

class _ReportsReviewScreenState extends State<ReportsReviewScreen> {
  bool _loading = true;
  String? _error;
  String _busyId = '';
  List<Map<String, dynamic>> _reports = [];

  SupabaseClient get _db => Supabase.instance.client;
  String get _organizationId => widget.profile['institutionId']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _db.from('task_reports')
          .select('id,task_id,submitted_by,submitted_at,values,task_report_form_snapshots!inner(title,schema),tasks!inner(title,organization_id,branch_id)')
          .eq('organization_id', _organizationId)
          .eq('status', 'submitted')
          .order('submitted_at', ascending: false)
          .limit(150);
      if (!mounted) return;
      setState(() => _reports = List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '—';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _displayValue(dynamic value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'نعم' : 'لا';
    if (value is Map || value is List) return const JsonEncoder.withIndent('  ').convert(value);
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  Future<void> _openReport(Map<String, dynamic> report) async {
    final snapshot = report['task_report_form_snapshots'] is Map
        ? Map<String, dynamic>.from(report['task_report_form_snapshots'] as Map)
        : <String, dynamic>{};
    final task = report['tasks'] is Map
        ? Map<String, dynamic>.from(report['tasks'] as Map)
        : <String, dynamic>{};
    final schema = (snapshot['schema'] as List? ?? [])
        .whereType<Map>().map((field) => Map<String, dynamic>.from(field)).toList()
      ..sort((a, b) => (int.tryParse(a['sort_order']?.toString() ?? '') ?? 0)
          .compareTo(int.tryParse(b['sort_order']?.toString() ?? '') ?? 0));
    final values = report['values'] is Map
        ? Map<String, dynamic>.from(report['values'] as Map)
        : <String, dynamic>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(snapshot['title']?.toString() ?? 'تقرير الموظف'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('المهمة: ${task['title'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('تاريخ الإرسال: ${_date(report['submitted_at'])}'),
                const Divider(height: 24),
                ...schema.map((field) {
                  final key = field['key']?.toString() ?? '';
                  final label = field['label']?.toString() ?? key;
                  final value = values[key];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        SelectableText(_displayValue(value)),
                      ],
                    ),
                  );
                }),
                if (schema.isEmpty)
                  SelectableText(const JsonEncoder.withIndent('  ').convert(values)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
          OutlinedButton(
            onPressed: _busyId.isEmpty ? () { Navigator.pop(dialogContext); _review(report, 'returned'); } : null,
            child: const Text('إعادة للموظف'),
          ),
          FilledButton(
            onPressed: _busyId.isEmpty ? () { Navigator.pop(dialogContext); _review(report, 'approved'); } : null,
            child: const Text('اعتماد التقرير'),
          ),
        ],
      ),
    );
  }

  Future<void> _review(Map<String, dynamic> report, String decision) async {
    final noteController = TextEditingController();
    final note = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(decision == 'approved' ? 'اعتماد التقرير' : 'إعادة التقرير للموظف'),
        content: TextField(
          controller: noteController,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: decision == 'approved' ? 'ملاحظة (اختيارية)' : 'سبب الإعادة',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: decision == 'returned' && noteController.text.trim().isEmpty
                ? null
                : () => Navigator.pop(dialogContext, noteController.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (note == null || !mounted) return;
    final id = report['id'].toString();
    setState(() => _busyId = id);
    try {
      await _db.rpc('mobile_review_task_form_report', params: {
        'p_report_id': id,
        'p_decision': decision,
        'p_note': note.isEmpty ? null : note,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision == 'approved' ? 'تم اعتماد التقرير.' : 'أُعيد التقرير للموظف لاستكماله.'),
      ));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission_denied') || message.contains('review_not_allowed')) return 'حسابك لا يملك صلاحية مراجعة هذا التقرير.';
    if (message.contains('jwt') || message.contains('not_authenticated')) return 'انتهت جلسة الدخول. سجّل الدخول مجدداً.';
    if (message.contains('socketexception') || message.contains('network')) return 'تعذر الاتصال. تحقق من الإنترنت وحاول مجدداً.';
    return 'تعذر تحميل التقارير أو مراجعتها. تحقق من الصلاحيات واتصال الشبكة.';
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('مراجعة تقارير الموظفين'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                  ]),
                ))
              : _reports.isEmpty
                  ? const Center(child: Text('لا توجد تقارير بانتظار المراجعة.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final report = _reports[index];
                          final task = report['tasks'] is Map ? report['tasks'] as Map : const {};
                          final snapshot = report['task_report_form_snapshots'] is Map
                              ? report['task_report_form_snapshots'] as Map : const {};
                          return Card(
                            elevation: 0,
                            child: ListTile(
                              title: Text(task['title']?.toString() ?? 'مهمة', style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text('${snapshot['title'] ?? 'تقرير'} · ${_date(report['submitted_at'])}'),
                              trailing: _busyId == report['id'].toString()
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.chevron_left),
                              onTap: _busyId.isEmpty ? () => _openReport(report) : null,
                            ),
                          );
                        },
                      ),
                    ),
    ),
  );
}
