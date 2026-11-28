import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/offline_attachment_store.dart';
import '../../core/offline_queue.dart';
import '../../shared/app_shell.dart';
import '../../shared/form_widgets.dart';
import '../../shared/report_pdf_theme.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;
  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  bool _busy = true, _saving = false;
  String? _error;
  Map<String, dynamic>? _task;
  List<Map<String, dynamic>> _fields = [], _steps = [];
  final Map<String, TextEditingController> _inputs = {};
  final Map<String, List<String>> _evidenceIds = {};
  List<Map<String, dynamic>> _forms = [];
  final Map<String, TextEditingController> _formInputs = {};
  RealtimeChannel? _taskChannel;
  String _formInputKey(String snapshot, String field) => '$snapshot:$field';

  List<Map<String, String>> _unifiedRows(String value) {
    final rows = <Map<String, String>>[];
    final pattern = RegExp(
      r'^صف الجدول:\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*$',
      multiLine: true,
    );
    for (final match in pattern.allMatches(value)) {
      rows.add({
        'time': match.group(1)?.trim() ?? 'غير محدد',
        'task': match.group(2)?.trim() ?? '—',
        'output': match.group(3)?.trim() ?? '—',
      });
    }
    return rows;
  }

  Widget _unifiedTable(String description) {
    final rows = _unifiedRows(description);
    if (rows.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: 'الجدول الموحد للمهام',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          columns: const [
            DataColumn(label: Text('الوقت')),
            DataColumn(label: Text('المهمة والمسؤولية')),
            DataColumn(label: Text('المخرج المطلوب')),
          ],
          rows: rows
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(Text(row['time'] ?? '—')),
                    DataCell(Text(row['task'] ?? '—')),
                    DataCell(Text(row['output'] ?? '—')),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  String _taskStatusLabel(Object? value) => const {
    'pending': 'لم تبدأ',
    'new': 'جديدة',
    'received': 'مستلمة',
    'in_progress': 'قيد التنفيذ',
    'on_hold': 'متوقفة مؤقتًا',
    'submitted': 'بانتظار المراجعة',
    'report_submitted': 'التقرير بانتظار المراجعة',
    'completed': 'مكتملة',
    'completed_approved': 'مكتملة ومعتمدة',
    'approved': 'معتمدة',
    'needs_revision': 'تحتاج إلى تعديل',
    'returned': 'معادة للموظف',
  }['$value'] ?? 'غير محددة';

  String _priorityLabel(Object? value) => const {
    'low': 'منخفضة',
    'normal': 'عادية',
    'high': 'عالية',
    'urgent': 'عاجلة',
  }['$value'] ?? 'عادية';

  String _localDateTime(Object? value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return 'غير محدد';
    return formatArabicDateTime(parsed.toLocal());
  }

  String _taskTitle() {
    final raw = '${_task?['title'] ?? 'مهمة'}'.trim();
    final withoutPrefix = raw.replaceFirst(RegExp(r'^الجدول الموحد\s*-\s*'), '').trim();
    final separator = RegExp(r'\s*[·•]\s*').firstMatch(withoutPrefix);
    return (separator == null
            ? withoutPrefix
            : withoutPrefix.substring(separator.end))
        .trim();
  }

  void _goBackFromDetails() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/tasks');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _taskChannel = Supabase.instance.client
        .channel('task-detail-${widget.taskId}-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (_) {
            if (mounted) _load();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_reports',
          callback: (_) {
            if (mounted) _load();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_report_drafts',
          callback: (_) {
            if (mounted) _load();
          },
        )
      ..subscribe();
  }

  @override
  void dispose() {
    for (final controller in _inputs.values) {
      controller.dispose();
    }
    for (final controller in _formInputs.values) {
      controller.dispose();
    }
    if (_taskChannel != null) {
      Supabase.instance.client.removeChannel(_taskChannel!);
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _busy = true);
    try {
      final db = Supabase.instance.client;
      final task = await db
          .from('tasks')
          .select(
            'id,title,description,due_at,priority,status,task_instructions,proof_required,proof_instructions,report_flow,report_required',
          )
          .eq('id', widget.taskId)
          .single();
      _task = Map<String, dynamic>.from(task as Map);
      final fieldsFuture = _task!['report_flow'] == 'multi_form'
          ? Future.value(const <Map<String, dynamic>>[])
          : db
                .from('task_report_fields')
                .select(
                  'id,label,field_key,field_type,is_required,options,sort_order',
                )
                .eq('task_id', widget.taskId)
                .order('sort_order')
                .then(
                  (rows) => List<Map<String, dynamic>>.from(rows as List),
                );
      // Unified-table tasks use immutable report snapshots and do not have
      // execution-step rows. Do not query that optional table for them: an
      // employee may read the task while RLS correctly hides step rows.
      final stepsFuture = _task!['report_flow'] == 'multi_form'
          ? Future.value(const <Map<String, dynamic>>[])
          : db
                .from('task_execution_steps')
                .select(
                  'id,title,instructions,sort_order,is_required,evidence_required,evidence_instructions,completed_at',
                )
                .eq('task_id', widget.taskId)
                .order('sort_order')
                .then((rows) => List<Map<String, dynamic>>.from(rows as List));
      final results = await Future.wait<dynamic>([fieldsFuture, stepsFuture]);
      _fields = List<Map<String, dynamic>>.from(results[0] as List);
      _steps = List<Map<String, dynamic>>.from(results[1] as List);
      _forms = [];
      if (_task!['report_flow'] == 'multi_form') {
        final snapshots = await db
            .from('task_report_form_snapshots')
            .select('id,task_id,title,sort_order,is_required,schema')
            .eq('task_id', widget.taskId)
            .order('sort_order')
            .order('id');
        final reports = await db
            .from('task_reports')
            .select('id,report_form_snapshot_id,values,status,review_note')
            .eq('task_id', widget.taskId)
            .order('submitted_at', ascending: false);
        final drafts = await db
            .from('task_report_drafts')
            .select('snapshot_id,values,updated_at')
            .eq('task_id', widget.taskId)
            .order('updated_at', ascending: false);
        final reportRows = List<Map<String, dynamic>>.from(reports);
        final draftRows = List<Map<String, dynamic>>.from(drafts);
        // Keep a second client-side guard as defense in depth. A report form
        // must never be rendered unless its immutable snapshot belongs to the
        // task currently open, even if a future query or view changes.
        final taskSnapshots = List<Map<String, dynamic>>.from(snapshots)
            .where((snapshot) => '${snapshot['task_id']}' == widget.taskId)
            .toList();
        _forms = taskSnapshots.map((snapshot) {
          final sid = '${snapshot['id']}';
          final matchingReports = reportRows.where(
            (r) => r['report_form_snapshot_id'] == sid,
          );
          final matchingDrafts = draftRows.where(
            (r) => r['snapshot_id'] == sid,
          );
          final report = matchingReports.isEmpty ? null : matchingReports.first;
          final draft = matchingDrafts.isEmpty ? null : matchingDrafts.first;
          final schema = (snapshot['schema'] is List)
              ? List<Map<String, dynamic>>.from(
                  (snapshot['schema'] as List).map(
                    (f) => Map<String, dynamic>.from(f as Map),
                  ),
                )
              : <Map<String, dynamic>>[];
          final values = Map<String, dynamic>.from(
            (draft?['values'] as Map?) ?? (report?['values'] as Map?) ?? {},
          );
          for (final field in schema) {
            final name = '${field['key'] ?? ''}';
            final initial = values[name];
            final text = initial == null
                ? ''
                : (initial is String &&
                          ![
                            'attachment',
                            'file',
                            'image',
                            'multi_image',
                            'signature',
                          ].contains('${field['type']}')
                      ? initial
                      : jsonEncode(initial));
            final inputKey = _formInputKey(sid, name);
            if (_formInputs.containsKey(inputKey)) {
              _formInputs[inputKey]!.text = text;
            } else {
              _formInputs[inputKey] = TextEditingController(text: text);
            }
          }
          return {
            ...snapshot,
            'schema': schema,
            'status': report?['status'],
            'values': report?['values'],
            'review_note': report?['review_note'],
          };
        }).toList();
      }
      for (final field in _fields) {
        _inputs.putIfAbsent('${field['field_key']}', TextEditingController.new);
      }
      // Opening telemetry must never hide an otherwise readable task.
      try {
        await db.rpc(
          'mobile_mark_task_opened',
          params: {'p_task_id': widget.taskId},
        );
      } catch (_) {
        // The task details are already loaded; status telemetry can retry on
        // the next open without blocking the employee.
      }
      _error = null;
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      _error = message.isEmpty
          ? 'تعذر تحميل تفاصيل المهمة. تحقق من صلاحيات الحساب والاتصال.'
          : 'تعذر تحميل تفاصيل المهمة: $message';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _status(String status) async {
    setState(() => _saving = true);
    try {
      try {
        await Supabase.instance.client.rpc(
          'mobile_record_task_update',
          params: {
            'p_task_id': widget.taskId,
            'p_status': status,
            'p_note': null,
          },
        );
        await _load();
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم تحديث حالة المهمة')));
      } catch (error) {
        if (!await OfflineQueue.isNetworkError(error)) rethrow;
        await OfflineQueue.enqueue(OfflineQueueKind.status, {
          'taskId': widget.taskId,
          'status': status,
          'note': null,
          'idempotencyKey':
              'status:$status:${DateTime.now().microsecondsSinceEpoch}',
        });
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حفظ الطلب؛ بانتظار المزامنة عند عودة الاتصال'),
            ),
          );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _operationError(
                error,
                'تعذر تحديث المهمة. تحقق من حالة المهمة أو صلاحيات الحساب.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitReport() async {
    final missing = _fields.where(
      (field) =>
          field['is_required'] == true &&
          (_inputs['${field['field_key']}']?.text.trim().isEmpty ?? true),
    );
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أكمل الحقول المطلوبة: ${missing.map((e) => e['label']).join('، ')}',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      var values = <String, dynamic>{
        for (final field in _fields)
          '${field['field_key']}': _convert(
            _inputs['${field['field_key']}']?.text ?? '',
            '${field['field_type']}',
          ),
      };
      final idempotencyKey =
          'flutter:${widget.taskId}:${DateTime.now().microsecondsSinceEpoch}';
      try {
        values = await OfflineQueue.resolvePendingAttachments(
          values,
          widget.taskId,
        );
        await Supabase.instance.client.rpc(
          'mobile_submit_task_report',
          params: {
            'p_task_id': widget.taskId,
            'p_values': values,
            'p_idempotency_key': idempotencyKey,
          },
        );
        await _load();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال التقرير للمراجعة')),
          );
      } catch (error) {
        if (!await OfflineQueue.isNetworkError(error)) rethrow;
        await OfflineQueue.enqueue(OfflineQueueKind.report, {
          'taskId': widget.taskId,
          'values': values,
          'idempotencyKey': idempotencyKey,
        });
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم حفظ التقرير؛ بانتظار المزامنة عند عودة الاتصال',
              ),
            ),
          );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _operationError(
                error,
                'تعذر إرسال التقرير. ابدأ تنفيذ المهمة أولاً ثم راجع الحقول المطلوبة أو الاتصال.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitTaskForReview() async {
    // The administration's report_required flag decides whether a report is
    // needed. Optional-report tasks go through the secured status RPC directly.
    if (_task?['report_required'] != true) {
      await _status('submitted');
      return;
    }
    if (_forms.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أكمل إرسال نماذج التقرير أولًا')),
        );
      }
      return;
    }
    await _submitReport();
  }

  Object? _convert(String value, String type) {
    if (value.isEmpty) return null;
    if (type == 'integer' || type == 'number' || type == 'decimal')
      return num.tryParse(value);
    if (type == 'boolean') return value == 'true';
    return value;
  }

  DateTime? _parseFlexibleDate(String value) {
    final normalized = value
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .trim();
    final parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed;
    final match = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?:\s*[·T ]\s*(\d{1,2}):?(\d{2})?)?',
    ).firstMatch(normalized);
    if (match == null) return null;
    return DateTime.tryParse(
      '${match.group(3)}-${match.group(2)!.padLeft(2, '0')}-${match.group(1)!.padLeft(2, '0')}'
      '${match.group(4) == null ? '' : 'T${match.group(4)!.padLeft(2, '0')}:${(match.group(5) ?? '00').padLeft(2, '0')}'}',
    );
  }

  String? _canonicalDateValue(String value, String type) {
    final parsed = _parseFlexibleDate(value);
    if (parsed == null) return null;
    if (type == 'date') {
      final local = parsed.toLocal();
      return '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
    }
    return parsed.toUtc().toIso8601String();
  }

  String _automaticDateLabel(String value, String type) {
    final parsed = _parseFlexibleDate(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    final date = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    return type == 'date' ? date : '$date · ${formatArabicTime(local)}';
  }

  String _snapshotDisplayValue(Map<String, dynamic> field, Object? value) {
    final type = '${field['type'] ?? ''}';
    if (value == null || '$value'.trim().isEmpty) return '—';
    if (type == 'date' || type == 'datetime') {
      return _automaticDateLabel('$value', type);
    }
    if (['attachment', 'file', 'image', 'multi_image'].contains(type)) {
      return reportPdfAttachmentText(value);
    }
    if (type == 'signature') {
      Map<String, dynamic> signature = {};
      if (value is Map) {
        signature = _obj(value);
      } else {
        try {
          signature = _obj(jsonDecode('$value'));
        } catch (_) {}
      }
      final strokes = signature['strokes'] is List
          ? (signature['strokes'] as List).whereType<String>().length
          : 0;
      final hasAttachment = '${signature['signature_attachment_id'] ?? ''}'
          .trim()
          .isNotEmpty;
      final signedAt = '${signature['signed_at'] ?? ''}'.trim();
      if (strokes == 0 && !hasAttachment && signedAt.isEmpty) {
        return 'لم يتم التوقيع';
      }
      final signedLabel = signedAt.isEmpty
          ? 'تم التوقيع'
          : 'تم التوقيع · ${_localDateTime(signedAt)}';
      return signature['acknowledged'] == true
          ? '$signedLabel · تمت الموافقة'
          : signedLabel;
    }
    if (value is Map || value is List) {
      try {
        return jsonEncode(value);
      } catch (_) {}
    }
    return '$value';
  }

  Future<String?> _snapshotAttachmentUrl(Map<String, dynamic> item) async {
    final direct = '${item['url'] ?? item['publicUrl'] ?? ''}'.trim();
    if (direct.startsWith('http://') || direct.startsWith('https://')) {
      return direct;
    }
    final path = '${item['storagePath'] ?? item['storage_path'] ?? item['path'] ?? ''}'.trim();
    if (path.isEmpty) return null;
    try {
      return await Supabase.instance.client.storage
          .from('task-attachments')
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  bool _snapshotAttachmentIsImage(Map<String, dynamic> item) {
    final mime = '${item['mimeType'] ?? item['mime_type'] ?? ''}'.toLowerCase();
    if (mime.startsWith('image/')) return true;
    final name = '${item['name'] ?? item['path'] ?? ''}'.toLowerCase();
    return RegExp(r'\.(png|jpe?g|webp|gif|bmp)$').hasMatch(name);
  }

  bool _snapshotAttachmentIsPdf(Map<String, dynamic> item) {
    final mime = '${item['mimeType'] ?? item['mime_type'] ?? ''}'.toLowerCase();
    if (mime == 'application/pdf') return true;
    final name = '${item['name'] ?? item['path'] ?? ''}'.toLowerCase();
    return name.endsWith('.pdf');
  }

  Future<void> _openSnapshotAttachment(
    Map<String, dynamic> item,
    String url,
  ) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('attachment_download_failed');
      }
      if (!mounted) return;
      final bytes = response.bodyBytes;
      final name = '${item['name'] ?? 'المرفق'}'.trim();
      if (_snapshotAttachmentIsImage(item)) {
        await showDialog<void>(
          context: context,
          builder: (_) => Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(name.isEmpty ? 'معاينة الصورة' : name),
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              body: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text('تعذر عرض الصورة.'),
                  ),
                ),
              ),
            ),
          ),
        );
        return;
      }
      if (_snapshotAttachmentIsPdf(item)) {
        await showDialog<void>(
          context: context,
          builder: (_) => Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(name.isEmpty ? 'معاينة PDF' : name),
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              body: PdfPreview(
                canChangeOrientation: false,
                canChangePageFormat: false,
                allowPrinting: true,
                allowSharing: true,
                pdfFileName: name.isEmpty ? 'attachment.pdf' : name,
                build: (_) async => bytes,
              ),
            ),
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('معاينة المرفق'),
          content: Text(
            name.isEmpty
                ? 'هذا النوع من الملفات لا يدعم المعاينة الداخلية حاليًا.'
                : 'لا تتوفر معاينة داخلية لهذا النوع من الملفات:\n$name',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل المرفق للمعاينة داخل التطبيق.')),
      );
    }
  }

  Widget _snapshotAttachmentPreview(Object? raw) {
    final items = reportPdfAttachmentItems(raw);
    if (items.isEmpty) return const Text('لا يوجد', textAlign: TextAlign.right);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          FutureBuilder<String?>(
            future: _snapshotAttachmentUrl(item),
            builder: (context, snapshot) {
              final url = snapshot.data;
              final name = '${item['name'] ?? ''}'.trim();
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  width: 34,
                  height: 34,
                  child: Padding(
                    padding: EdgeInsets.all(7),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (url == null || url.isEmpty) {
                return Chip(
                  avatar: const Icon(Icons.attach_file, size: 18),
                  label: Text(name.isEmpty ? 'مرفق' : name),
                );
              }
              if (_snapshotAttachmentIsImage(item)) {
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openSnapshotAttachment(item, url),
                  child: Tooltip(
                    message: name.isEmpty ? 'عرض الصورة' : name,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        url,
                        width: 76,
                        height: 62,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 76,
                          height: 62,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return OutlinedButton.icon(
                onPressed: () => _openSnapshotAttachment(item, url),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(name.isEmpty ? 'فتح المرفق' : name),
              );
            },
          ),
      ],
    );
  }

  String _operationError(Object error, String fallback) {
    final message = error is PostgrestException
        ? error.message
        : error.toString().replaceFirst('Exception: ', '').trim();
    if (message.contains('permission_denied')) {
      return 'لا تملك صلاحية تنفيذ هذا الإجراء على المهمة.';
    }
    if (message.contains('task_not_found')) {
      return 'المهمة غير موجودة أو لم تعد مسندة إلى حسابك.';
    }
    if (message.contains('invalid_progress_status')) {
      return 'لا يمكن تغيير الحالة من المرحلة الحالية. حدّث الشاشة وحاول مرة أخرى.';
    }
    if (message.contains('task_report_required')) {
      return 'أكمل التقرير المطلوب وأرسله قبل إنهاء المهمة.';
    }
    return message.isEmpty ? fallback : '$fallback\n$message';
  }

  Object? _snapshotValue(Map<String, dynamic> field, String snapshotId) {
    final key = '${field['key'] ?? ''}';
    final raw = _formInputs[_formInputKey(snapshotId, key)]?.text.trim() ?? '';
    final type = '${field['type'] ?? ''}';
    if (type == 'calculated') return _calculatedValue(field, snapshotId);
    if (raw.isEmpty) return null;
    if (type == 'date' || type == 'datetime') {
      return _canonicalDateValue(raw, type) ?? raw;
    }
    if ([
      'table',
      'multiselect',
      'date_range',
      'attachment',
      'file',
      'image',
      'multi_image',
      'signature',
    ].contains(type)) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if ([
      'integer',
      'number',
      'decimal',
      'percentage',
      'quantity',
      'money',
      'progress',
      'calculated',
    ].contains(type))
      return num.tryParse(raw);
    if (type == 'boolean' || type == 'checkbox')
      return raw == 'true'
          ? true
          : raw == 'false'
          ? false
          : null;
    return raw;
  }

  num? _calculatedValue(Map<String, dynamic> field, String snapshotId) {
    final formula = '${_obj(field['config'])['formula'] ?? ''}';
    try {
      final sum = RegExp(r'^sum_rows\(([a-z][a-z0-9_]*)\.([a-z][a-z0-9_]*)\)$')
          .firstMatch(formula);
      if (sum != null) {
        final rows = _rows(
          _formInputs[_formInputKey(snapshotId, sum.group(1)!)]?.text ?? '[]',
        );
        return rows.fold<num>(
          0,
          (total, row) => total + (num.tryParse('${row[sum.group(2)] ?? ''}') ?? 0),
        );
      }
      var expression = formula;
      for (final match in RegExp(r'\{([a-z][a-z0-9_]*)\}').allMatches(formula)) {
        final value = num.tryParse(
          _formInputs[_formInputKey(snapshotId, match.group(1)!)]?.text ?? '',
        );
        if (value == null) return null;
        expression = expression.replaceAll(match.group(0)!, '$value');
      }
      return _arithmetic(expression);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _obj(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<Map<String, dynamic>> _rows(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is List
          ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _cols(Map<String, dynamic> f) {
    final raw = _obj(f['config'])['columns'];
    if (raw is! List) return [];
    return raw.asMap().entries.map((e) {
      if (e.value is String)
        return {
          'key': e.value,
          'label': e.value,
          'type': 'short_text',
          'required': false,
        };
      final c = _obj(e.value);
      return {
        'key': '${c['key'] ?? 'column_${e.key + 1}'}',
        'label': '${c['label'] ?? c['name'] ?? c['key'] ?? 'عمود'}',
        'type': '${c['type'] ?? c['field_type'] ?? 'short_text'}',
        'required': c['required'] == true || c['is_required'] == true,
        'options': c['options'] is List ? c['options'] : <dynamic>[],
      };
    }).toList();
  }

  String? _validateSnapshot(Map<String, dynamic> f, String sid) {
    final v = _snapshotValue(f, sid),
        type = '${f['type']}',
        label = '${f['label'] ?? f['key']}';
    if (v == null) {
      final raw =
          _formInputs[_formInputKey(sid, '${f['key']}')]?.text.trim() ?? '';
      return raw.isNotEmpty
          ? 'تحقق من صيغة الحقل «$label».'
          : (f['required'] == true ? 'أكمل الحقل «$label».' : null);
    }
    if (type == 'signature') {
      final sig = _obj(v),
          strokes = sig['strokes'],
          consent = '${_obj(f['config'])['consent_text'] ?? ''}'.trim();
      if (strokes is! List ||
          ((f['required'] == true || consent.isNotEmpty) && strokes.isEmpty) ||
          strokes.length > 200 ||
          strokes.any(
            (x) =>
                x is! String ||
                x.length > 15000 ||
                !RegExp(r'^[ML0-9 .+\-]+$').hasMatch(x),
          ) ||
          strokes.fold<int>(0, (n, x) => n + (x is String ? x.length : 0)) >
              200000)
        return 'التوقيع في «$label» غير صالح.';
      if (consent.isNotEmpty && sig['acknowledged'] != true)
        return 'يرجى الموافقة على «$label».';
    }
    if (['attachment', 'file', 'image', 'multi_image'].contains(type)) {
      if (v is! List ||
          v.length > 20 ||
          v.any(
            (x) => x is! Map || x['path'] is! String || x['id'] is! String,
          ) ||
          (type == 'image' && v.length > 1))
        return 'المرفقات في «$label» غير صالحة.';
    }
    if ([
          'integer',
          'number',
          'decimal',
          'percentage',
          'quantity',
          'money',
          'progress',
        ].contains(type) &&
        (v is! num || !v.isFinite || (type == 'integer' && v % 1 != 0)))
      return 'أدخل رقمًا صالحًا في «$label». ${type == 'integer' ? 'يجب أن يكون عددًا صحيحًا.' : ''}';
    if (type == 'select' &&
        (!(f['options'] is List) || !(f['options'] as List).contains(v)))
      return 'اختر قيمة متاحة في «$label».';
    if (type == 'multiselect' &&
        (v is! List ||
            (f['required'] == true && v.isEmpty) ||
            v.any((x) => !(f['options'] as List? ?? []).contains(x))))
      return 'تحقق من الاختيارات في «$label».';
    if ((type == 'boolean' || type == 'checkbox') && v is! bool)
      return 'اختر نعم أو لا في «$label».';
    if ((type == 'date' || type == 'datetime') &&
        (v is! String || _parseFlexibleDate(v) == null))
      return 'أدخل تاريخًا صالحًا في «$label».';
    if (type == 'date_range') {
      final r = _obj(v);
      final a = DateTime.tryParse('${r['from'] ?? ''}'),
          b = DateTime.tryParse('${r['to'] ?? ''}');
      if (a == null || b == null)
        return 'حدد تاريخ البداية والنهاية في «$label».';
      if (a.isAfter(b))
        return 'تاريخ البداية يجب ألا يتجاوز النهاية في «$label».';
    }
    if (type == 'table') {
      if (v is! List) return 'بيانات الجدول «$label» غير صالحة.';
      final cfg = _obj(f['config']);
      final min = int.tryParse('${cfg['min_rows'] ?? 0}') ?? 0,
          max = int.tryParse('${cfg['max_rows'] ?? 0}') ?? 0;
      if (v.length < min) return 'أضف $min صفوفًا على الأقل إلى «$label».';
      if (max > 0 && v.length > max)
        return 'الحد الأقصى لجدول «$label» هو $max صفًا.';
      final cols = _cols(f);
      for (var i = 0; i < v.length; i++) {
        final row = _obj(v[i]);
        for (final c in cols) {
          final cell = row['${c['key']}'],
              str = '${cell ?? ''}'.trim(),
              ct = '${c['type']}';
          if (str.isEmpty && c['required'] == true)
            return 'أكمل «${c['label']}» في الصف ${i + 1}.';
          if (str.isEmpty) continue;
          if (['integer', 'decimal', 'quantity', 'money'].contains(ct) &&
              (num.tryParse(str) == null ||
                  (ct == 'integer' && num.parse(str) % 1 != 0)))
            return 'أدخل رقمًا صالحًا في «${c['label']}» بالصف ${i + 1}.';
          if (ct == 'select' && !(c['options'] as List).contains(str))
            return 'اختر خيارًا صالحًا في «${c['label']}» بالصف ${i + 1}.';
          if (ct == 'boolean' &&
              cell != true &&
              cell != false &&
              cell != 'true' &&
              cell != 'false')
            return 'اختر نعم أو لا في «${c['label']}» بالصف ${i + 1}.';
        }
      }
    }
    return null;
  }

  double? _arithmetic(String src) {
    final s = src.replaceAll(' ', '');
    if (!RegExp(r'^[0-9.+*/()\-]+$').hasMatch(s)) throw const FormatException();
    final t = RegExp(r'\d+(?:\.\d+)?|[()+*/-]')
        .allMatches(s)
        .map((m) => m.group(0)!)
        .toList();
    var i = 0;
    late double Function() expr;
    double primary() {
      if (i >= t.length) throw const FormatException();
      final x = t[i++];
      if (x == '-') return -primary();
      if (x == '+') return primary();
      if (x == '(') {
        final n = expr();
        if (i >= t.length || t[i++] != ')') throw const FormatException();
        return n;
      }
      return double.parse(x);
    }

    double term() {
      var n = primary();
      while (i < t.length && (t[i] == '*' || t[i] == '/')) {
        final o = t[i++], r = primary();
        if (o == '/' && r == 0) throw const FormatException();
        n = o == '*' ? n * r : n / r;
      }
      return n;
    }

    double expression() {
      var n = term();
      while (i < t.length && (t[i] == '+' || t[i] == '-')) {
        final o = t[i++], r = term();
        n = o == '+' ? n + r : n - r;
      }
      return n;
    }

    expr = expression;
    final n = expr();
    if (i != t.length || !n.isFinite) throw const FormatException();
    return n;
  }

  Widget _tableField(Map<String, dynamic> f, String sid, String title) {
    final ctl = _formInputs[_formInputKey(sid, '${f['key']}')]!,
        cols = _cols(f),
        cfg = _obj(f['config']),
        rows = _rows(ctl.text);
    final max = int.tryParse('${cfg['max_rows'] ?? 0}') ?? 0,
        min = int.tryParse('${cfg['min_rows'] ?? 0}') ?? 0;
    void save(List<Map<String, dynamic>> r) {
      ctl.text = jsonEncode(r);
      setState(() {});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, textAlign: TextAlign.right),
        for (var i = 0; i < rows.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('صف ${i + 1}'),
                      IconButton(
                        onPressed: _saving || rows.length <= min
                            ? null
                            : () {
                                final n = [...rows]..removeAt(i);
                                save(n);
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  for (final c in cols)
                    _tableCell(c, rows[i]['${c['key']}'], (v) {
                      final n = [...rows];
                      n[i] = {...n[i], '${c['key']}': v};
                      save(n);
                    }),
                ],
              ),
            ),
          ),
        if (cols.any(
              (c) => [
                'integer',
                'decimal',
                'quantity',
                'money',
              ].contains(c['type']),
            ) &&
            rows.isNotEmpty)
          for (final c in cols.where(
            (c) =>
                ['integer', 'decimal', 'quantity', 'money'].contains(c['type']),
          ))
            Text(
              'إجمالي ${c['label']}: ${rows.fold<double>(0, (a, r) => a + (num.tryParse('${r[c['key']] ?? ''}') ?? 0))}',
              textAlign: TextAlign.right,
            ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _saving || (max > 0 && rows.length >= max)
                ? null
                : () {
                    save([
                      ...rows,
                      {
                        for (final c in cols)
                          '${c['key']}': c['type'] == 'boolean' ? null : '',
                      },
                    ]);
                  },
            icon: const Icon(Icons.add),
            label: Text(
              max > 0 && rows.length >= max ? 'بلغت الحد الأعلى' : 'إضافة صف',
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableCell(
    Map<String, dynamic> c,
    dynamic value,
    ValueChanged<dynamic> onChange,
  ) {
    final type = '${c['type']}',
        label = '${c['label']}${c['required'] == true ? ' *' : ''}';
    if (type == 'select')
      return DropdownButtonFormField<String>(
        value:
            (c['options'] as List).map((e) => '$e').contains(value?.toString())
            ? value.toString()
            : null,
        decoration: InputDecoration(labelText: label),
        items: (c['options'] as List)
            .map((e) => DropdownMenuItem(value: '$e', child: Text('$e')))
            .toList(),
        onChanged: onChange,
      );
    if (type == 'boolean')
      return CheckboxListTile(
        tristate: true,
        value: value == true || value == 'true'
            ? true
            : value == false || value == 'false'
            ? false
            : null,
        title: Text(label),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: onChange,
      );
    return TextFormField(
      key: ValueKey('${c['key']}_$value'),
      initialValue: '${value ?? ''}',
      maxLines: type == 'long_text' ? 3 : 1,
      keyboardType: ['integer', 'decimal', 'quantity', 'money'].contains(type)
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      onChanged: onChange,
    );
  }

  Future<void> _saveSnapshotDraft(
    String snapshotId,
    List<Map<String, dynamic>> schema,
  ) async {
    var values = <String, dynamic>{};
    for (final field in schema) {
      final value = _snapshotValue(field, snapshotId);
      if (value != null) values['${field['key']}'] = value;
    }
    setState(() => _saving = true);
    try {
      values = await OfflineQueue.resolvePendingAttachments(
        values,
        widget.taskId,
      );
      await Supabase.instance.client.rpc(
        'save_task_report_draft',
        params: {
          'p_task_id': widget.taskId,
          'p_snapshot_id': snapshotId,
          'p_values': values,
        },
      );
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ مسودة النموذج')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ المسودة. تحقق من الاتصال.')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitSnapshot(
    String snapshotId,
    List<Map<String, dynamic>> schema,
  ) async {
    for (final f in schema) {
      final issue = _validateSnapshot(f, snapshotId);
      if (issue != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(issue)));
        return;
      }
    }
    var values = <String, dynamic>{};
    for (final field in schema) {
      final value = _snapshotValue(field, snapshotId);
      if (value != null) values['${field['key']}'] = value;
    }
    setState(() => _saving = true);
    final idempotencyKey =
        'report:$snapshotId:${widget.taskId}:${DateTime.now().millisecondsSinceEpoch}';
    try {
      try {
        values = await OfflineQueue.resolvePendingAttachments(
          values,
          widget.taskId,
        );
        await Supabase.instance.client.rpc(
          'mobile_submit_task_report_form',
          params: {
            'p_task_id': widget.taskId,
            'p_snapshot_id': snapshotId,
            'p_values': values,
            'p_idempotency_key': idempotencyKey,
          },
        );
        final currentForm = _forms.firstWhere(
          (form) => '${form['id']}' == snapshotId,
          orElse: () => <String, dynamic>{'title': 'نموذج تقرير'},
        );
        await _shareSnapshotPdf(
          title: _taskTitle(),
          reportTitle: '${currentForm['title'] ?? 'نموذج تقرير'}',
          schema: schema,
          values: values,
          status: 'مرسل للمراجعة',
        );
        await _load();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال النموذج للمراجعة')),
          );
      } catch (error) {
        if (!await OfflineQueue.isNetworkError(error)) rethrow;
        await OfflineQueue.enqueue(OfflineQueueKind.report, {
          'taskId': widget.taskId,
          'snapshotId': snapshotId,
          'values': values,
          'idempotencyKey': idempotencyKey,
        });
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم حفظ النموذج؛ بانتظار المزامنة عند عودة الاتصال',
              ),
            ),
          );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _operationError(
                error,
                'تعذر إرسال النموذج. ابدأ تنفيذ المهمة أولاً ثم راجع الحقول المطلوبة أو الاتصال.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _pdfValue(dynamic value) {
    if (value == null || '$value'.trim().isEmpty) return 'لا يوجد';
    if (reportPdfIsAttachment(value)) {
      return reportPdfAttachmentText(value);
    }
    if (value is List) return value.map(_pdfValue).join('، ');
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${_pdfValue(entry.value)}')
          .join('، ');
    }
    return '$value';
  }

  bool _pdfLooksLikeSignature(dynamic value) {
    if (value is! Map) return false;
    return value['strokes'] is List ||
        value['signature_attachment_id'] != null ||
        value['signed_at'] != null ||
        value['acknowledged'] != null;
  }

  String _pdfFieldLabel(Map<String, dynamic> field, int index) {
    final label = '${field['label'] ?? ''}'.trim();
    final key = '${field['key'] ?? ''}'.trim();
    final candidate = label.isNotEmpty ? label : key;
    final looksLikeCode = candidate.isEmpty ||
        candidate.contains(RegExp(r'dlef', caseSensitive: false)) ||
        RegExp(r'^[_:\-\d]+$').hasMatch(candidate);
    if (!looksLikeCode) return reportPdfSafeText(candidate);
    return switch ('${field['type'] ?? ''}') {
      'date' => 'التاريخ',
      'datetime' => 'التاريخ والوقت',
      'signature' => 'التوقيع',
      'calculated' => 'القيمة المحسوبة',
      'attachment' => 'المرفق',
      'select' => 'الحالة',
      'number' => 'القيمة',
      _ => 'الحقل ${index + 1}',
    };
  }

  Future<void> _shareSnapshotPdf({
    required String title,
    required String reportTitle,
    required List<Map<String, dynamic>> schema,
    required Map<String, dynamic> values,
    required String status,
  }) async {
    try {
      final reportTheme = await ReportPdfTheme.load();
      final document = pw.Document(
        theme: await ReportPdfTheme.pdfTheme(),
      );
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            reportTheme.header('تقرير المهمة', status: status),
            pw.Text(reportPdfSafeText('المهمة: $title'), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: reportTheme.fontSize)),
            pw.Text(reportPdfSafeText('النموذج: $reportTitle'), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: reportTheme.fontSize)),
            pw.SizedBox(height: 16),
            pw.Table(
                    border: reportTheme.tableBorder,
                    columnWidths: const {
                      0: pw.FlexColumnWidth(1),
                      1: pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration: reportTheme.tableHeaderDecoration,
                        children: [
                          _pdfTableCell('القيمة', bold: true),
                          _pdfTableCell('الحقل', bold: true),
                        ],
                      ),
                      for (var index = 0; index < schema.length; index++)
                        pw.TableRow(children: [
                          '${schema[index]['type'] ?? ''}' == 'signature' ||
                                  _pdfLooksLikeSignature(values[schema[index]['key']])
                              ? reportPdfSignatureWidget(values[schema[index]['key']])
                              : _pdfTableCell(_pdfValue(values[schema[index]['key']])),
                          _pdfTableCell(_pdfFieldLabel(schema[index], index)),
                        ]),
                    ],
            ),
          ],
          footer: (context) => reportTheme.footer(context),
        ),
      );
      await Printing.sharePdf(
        bytes: await document.save(),
        filename: 'nexora-task-report-${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم إرسال التقرير، وتعذر فتح تصدير PDF تلقائيًا. يمكنك المحاولة من زر تصدير PDF.',
            ),
          ),
        );
      }
    }
  }

  pw.Widget _pdfTableCell(String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(
          reportPdfSafeText(value.trim().isEmpty ? 'لا يوجد' : value),
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  List<Map<String, dynamic>> _attachmentList(TextEditingController? ctl) {
    try {
      final x = jsonDecode(ctl?.text ?? '[]');
      return x is List
          ? x.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _pickReportFiles(TextEditingController? ctl, String type) async {
    if (_saving || ctl == null) return;
    try {
      final multi = type == 'multi_image';
      final allowMultiple = multi || type == 'file' || type == 'attachment';
      final pickerType = multi ? FileType.image : FileType.any;
      final files = allowMultiple
          ? await FilePicker.pickFiles(type: pickerType)
          : [
              if (await FilePicker.pickFile(type: pickerType) case final file?)
                file,
            ];
      if (files.isEmpty) return;
      final db = Supabase.instance.client, user = db.auth.currentUser;
      if (user == null) throw Exception('سجّل الدخول مجددًا.');
      final current = _attachmentList(ctl);
      if (current.length + files.length > 20 ||
          (type == 'image' && current.length + files.length > 1))
        throw Exception('الحد 20 مرفقًا ويسمح بصورة واحدة لهذا الحقل.');
      for (final file in files) {
        final size = await file.length() ?? 0;
        if (size <= 0 || size > 20 * 1024 * 1024)
          throw Exception('الحد الأعلى لكل ملف 20 ميجابايت.');
        final mime = lookupMimeType(file.name) ?? 'application/octet-stream';
        if ((multi || type == 'image') && !mime.startsWith('image/'))
          throw Exception('اختر ملف صورة.');
        final bytes = await file.readAsBytes();
        final safe = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final path =
            '${widget.taskId}/${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}-$safe';
        try {
          await db.storage
              .from('task-attachments')
              .uploadBinary(
                path,
                bytes,
                fileOptions: FileOptions(contentType: mime, upsert: false),
              );
        } catch (error) {
          if (await OfflineQueue.isNetworkError(error)) {
            final localPath = await OfflineAttachmentStore.save(
              ownerUid: user.id,
              attachmentId: path.split('/').last,
              bytes: bytes,
            );
            current.add({
              'pendingUpload': true,
              'localPath': localPath,
              'name': file.name,
              'mimeType': mime,
              'size': size,
            });
            continue;
          }
          rethrow;
        }
        try {
          final row = await db
              .from('task_attachments')
              .insert({
                'task_id': widget.taskId,
                'execution_step_id': null,
                'uploaded_by': user.id,
                'file_name': file.name,
                'storage_path': path,
                'mime_type': mime,
                'size_bytes': size,
              })
              .select('id')
              .single();
          current.add({
            'id': '${row['id']}',
            'path': path,
            'name': file.name,
            'mimeType': mime,
            'size': size,
          });
        } catch (_) {
          await db.storage.from('task-attachments').remove([path]);
          rethrow;
        }
      }
      ctl.text = jsonEncode(current);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر رفع المرفق: $e')));
    }
  }

  Widget _snapshotField(Map<String, dynamic> field, String snapshotId) {
    final type = '${field['type'] ?? 'short_text'}';
    final title =
        '${field['label'] ?? field['key'] ?? 'حقل'}${field['required'] == true ? ' *' : ''}';
    final controller =
        _formInputs[_formInputKey(snapshotId, '${field['key'] ?? ''}')];
    if ((type == 'date' || type == 'datetime') &&
        controller != null &&
        controller.text.trim().isNotEmpty) {
      final display = _automaticDateLabel(controller.text, type);
      if (display != controller.text) controller.text = display;
    }
    final options = field['options'] is List
        ? (field['options'] as List).map((v) => '$v').toList()
        : <String>[];
    if (type == 'table') return _tableField(field, snapshotId, title);
    if (type == 'multiselect') {
      List<String> selected = [];
      try {
        final v = jsonDecode(controller?.text ?? '[]');
        if (v is List) selected = v.map((x) => '$x').toList();
      } catch (_) {}
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, textAlign: TextAlign.right),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            children: options
                .map(
                  (o) => FilterChip(
                    label: Text(o),
                    selected: selected.contains(o),
                    onSelected: (yes) {
                      if (yes) {
                        selected.add(o);
                      } else {
                        selected.remove(o);
                      }
                      controller?.text = jsonEncode(selected);
                      setState(() {});
                    },
                  ),
                )
                .toList(),
          ),
        ],
      );
    }
    if (['attachment', 'file', 'image', 'multi_image'].contains(type)) {
      final items = _attachmentList(controller);
      final max = type == 'image' ? 1 : 20;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, textAlign: TextAlign.right),
          for (var i = 0; i < items.length; i++)
            ListTile(
              title: Text(
                '${items[i]['name'] ?? items[i]['path']}',
                textAlign: TextAlign.right,
              ),
              trailing: IconButton(
                onPressed: _saving
                    ? null
                    : () {
                        items.removeAt(i);
                        controller?.text = jsonEncode(items);
                        setState(() {});
                      },
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _saving || items.length >= max
                ? null
                : () => _pickReportFiles(controller, type),
            icon: const Icon(Icons.upload_file),
            label: const Text('إضافة مرفق'),
          ),
        ],
      );
    }
    if (type == 'signature') {
      Map<String, dynamic> v = {};
      try {
        v = _obj(jsonDecode(controller?.text ?? '{}'));
      } catch (_) {}
      final consent = '${_obj(field['config'])['consent_text'] ?? ''}';
      final st = v['strokes'] is List
          ? (v['strokes'] as List).whereType<String>().toList()
          : <String>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, textAlign: TextAlign.right),
          if (consent.trim().isNotEmpty)
            Text(consent, textAlign: TextAlign.right),
          SignatureCapture(
            strokes: st,
            enabled: !_saving,
            onChanged: (paths) {
              v['strokes'] = paths;
              v.putIfAbsent('acknowledged', () => false);
              controller?.text = jsonEncode(v);
            },
          ),
          if (consent.trim().isNotEmpty)
            CheckboxListTile(
              value: v['acknowledged'] == true,
              title: const Text('أوافق على النص أعلاه'),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _saving
                  ? null
                  : (b) {
                      v['acknowledged'] = b == true;
                      controller?.text = jsonEncode(v);
                      setState(() {});
                    },
            ),
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    v = {'strokes': <String>[], 'acknowledged': false};
                    controller?.text = jsonEncode(v);
                    setState(() {});
                  },
            child: const Text('مسح التوقيع'),
          ),
        ],
      );
    }
    if (type == 'system_reference')
      return TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: title,
          helperText: 'أدخل معرّف السجل المرتبط يدويًا',
        ),
      );
    if (type == 'date_range') {
      Map<String, dynamic> r = {};
      try {
        r = _obj(jsonDecode(controller?.text ?? '{}'));
      } catch (_) {}
      return Column(
        children: [
          Text(title, textAlign: TextAlign.right),
          Row(
            children: ['from', 'to']
                .map(
                  (k) => Expanded(
                    child: TextField(
                      key: ValueKey('${snapshotId}_${field['key']}_$k'),
                      controller: TextEditingController(text: '${r[k] ?? ''}')
                        ..selection = TextSelection.collapsed(
                          offset: '${r[k] ?? ''}'.length,
                        ),
                      decoration: InputDecoration(
                        labelText: k == 'from'
                            ? 'من (YYYY-MM-DD)'
                            : 'إلى (YYYY-MM-DD)',
                      ),
                      onChanged: (v) {
                        r[k] = v;
                        controller?.text = jsonEncode(r);
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      );
    }
    if (type == 'calculated') {
      final formula = '${_obj(field['config'])['formula'] ?? ''}';
      String? error;
      double? result;
      try {
        final sum = RegExp(
          r'^sum_rows\(([a-z][a-z0-9_]*)\.([a-z][a-z0-9_]*)\)$',
        ).firstMatch(formula);
        if (sum != null) {
          final rows = _rows(
            _formInputs[_formInputKey(snapshotId, sum.group(1)!)]?.text ?? '[]',
          );
          result = rows.fold<double>(
            0,
            (a, r) => a + (num.tryParse('${r[sum.group(2)] ?? ''}') ?? 0),
          );
        } else {
          var expr = formula;
          for (final m in RegExp(
            r'\{([a-z][a-z0-9_]*)\}',
          ).allMatches(formula)) {
            final n = num.tryParse(
              _formInputs[_formInputKey(snapshotId, m.group(1)!)]?.text ?? '',
            );
            if (n == null) throw const FormatException();
            expr = expr.replaceAll(m.group(0)!, '$n');
          }
          result = _arithmetic(expr);
        }
      } catch (_) {
          error = 'تعذر حساب النتيجة. تأكد من إدخال الحقول المرتبطة بصورة صحيحة ثم حاول مرة أخرى.';
      }
      return ListTile(
        title: Text(title, textAlign: TextAlign.right),
        subtitle: Text(
          error ?? (result?.toString() ?? 'أكمل الحقول المرتبطة'),
          textAlign: TextAlign.right,
        ),
      );
    }
    if (type == 'select' && options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        value: options.contains(controller?.text) ? controller!.text : null,
        decoration: InputDecoration(labelText: title),
        items: options
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) {
          if (v != null) {
            controller?.text = v;
            setState(() {});
          }
        },
      );
    }
    if (type == 'rating') {
      const ratings = ['1', '2', '3', '4', '5'];
      return DropdownButtonFormField<String>(
        value: ratings.contains(controller?.text) ? controller!.text : null,
        decoration: InputDecoration(labelText: title),
        items: ratings
            .map((value) => DropdownMenuItem(value: value, child: Text('$value / 5')))
            .toList(),
        onChanged: (value) {
          if (value != null) {
            controller?.text = value;
            setState(() {});
          }
        },
      );
    }
    if (type == 'boolean' || type == 'checkbox')
      return CheckboxListTile(
        value: controller?.text == 'true',
        onChanged: (v) {
          controller?.text = '${v == true}';
          setState(() {});
        },
        title: Text(title),
        controlAffinity: ListTileControlAffinity.leading,
      );
    const supported = [
      'text',
      'short_text',
      'textarea',
      'long_text',
      'notes',
      'decision_notes',
      'number',
      'integer',
      'decimal',
      'percentage',
      'quantity',
      'money',
      'progress',
      'date',
      'datetime',
      'barcode',
      'status',
    ];
    if (!supported.contains(type))
      return ListTile(
        title: Text(title),
        subtitle: Text(
          'نوع الحقل «$type» غير مدعوم في Flutter؛ أكمل هذا النموذج من التطبيق المدعوم.',
        ),
      );
    if ((type == 'date' || type == 'datetime') &&
        (controller?.text.isEmpty ?? true))
      controller?.text = DateTime.now().toUtc().toIso8601String();
    return TextField(
      controller: controller,
      readOnly: type == 'date' || type == 'datetime',
      maxLines:
          ['textarea', 'long_text', 'notes', 'decision_notes'].contains(type)
          ? 4
          : 1,
      keyboardType:
          [
            'number',
            'integer',
            'decimal',
            'percentage',
            'quantity',
            'money',
            'progress',
          ].contains(type)
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: title,
        helperText: '${field['description'] ?? ''}',
      ),
    );
  }

  Future<void> _uploadEvidence(String stepId) async {
    PlatformFile? selectedFile;
    Uint8List? selectedBytes;
    String? ownerUid;
    String? storagePath;
    String? mime;
    try {
      selectedFile = await FilePicker.pickFile(type: FileType.any);
      if (selectedFile == null) return;
      final size = await selectedFile.length() ?? 0;
      if (size <= 0 || size > 20 * 1024 * 1024)
        throw Exception('الحد الأعلى لحجم المرفق 20 ميجابايت.');
      selectedBytes = await selectedFile.readAsBytes();
      final db = Supabase.instance.client;
      final user = db.auth.currentUser;
      if (user == null) throw Exception('سجّل الدخول مجددًا.');
      ownerUid = user.id;
      final safeName = selectedFile.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      storagePath =
          '${widget.taskId}/${DateTime.now().microsecondsSinceEpoch}-$safeName';
      mime = switch (selectedFile.extension?.toLowerCase()) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'txt' => 'text/plain',
        _ => 'application/octet-stream',
      };
      await db.storage
          .from('task-attachments')
          .uploadBinary(
            storagePath,
            selectedBytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      try {
        final metadata = await db
            .from('task_attachments')
            .insert({
              'task_id': widget.taskId,
              'execution_step_id': stepId,
              'uploaded_by': user.id,
              'file_name': selectedFile.name,
              'storage_path': storagePath,
              'mime_type': mime,
              'size_bytes': size,
            })
            .select('id')
            .single();
        _evidenceIds.putIfAbsent(stepId, () => []).add('${metadata['id']}');
        if (mounted) setState(() {});
      } catch (_) {
        await db.storage.from('task-attachments').remove([storagePath]);
        rethrow;
      }
    } catch (error) {
      if (ownerUid != null &&
          selectedFile != null &&
          selectedBytes != null &&
          storagePath != null &&
          mime != null &&
          await OfflineQueue.isNetworkError(error)) {
        try {
          final localPath = await OfflineAttachmentStore.save(
            ownerUid: ownerUid,
            attachmentId: storagePath.split('/').last,
            bytes: selectedBytes,
          );
          await OfflineQueue.enqueue(OfflineQueueKind.attachment, {
            'taskId': widget.taskId,
            'stepId': stepId,
            'idempotencyKey': 'evidence:$storagePath',
            'localPath': localPath,
            'storagePath': storagePath,
            'fileName': selectedFile.name,
            'mimeType': mime,
            'size': selectedBytes.length,
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم حفظ الدليل محليًا وسيُرفع تلقائيًا عند عودة الاتصال.')),
            );
          }
          return;
        } catch (_) {}
      }
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر رفع المرفق: $error')));
    }
  }

  Future<void> _completeStep(String id) async {
    final step = _steps.firstWhere(
      (row) => '${row['id']}' == id,
      orElse: () => <String, dynamic>{},
    );
    final evidenceRequired = step['evidence_required'] == true;
    final evidence = _evidenceIds[id] ?? const <String>[];
    if (evidenceRequired && evidence.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('هذه الخطوة تتطلب رفع إثبات قبل إكمالها.'),
          ),
        );
      }
      return;
    }
    try {
      await Supabase.instance.client.rpc(
        'mobile_complete_task_step',
        params: {
          'p_step_id': id,
          'p_evidence_attachment_ids': _evidenceIds[id] ?? <String>[],
        },
      );
      await _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر إكمال الخطوة. أضف الدليل المطلوب أو تحقق من الصلاحية.',
            ),
          ),
        );
    }
  }

  Widget _taskOverviewCard() {
    final status = '${_task?['status'] ?? ''}';
    final statusColor = status == 'completed_approved'
        ? AppColors.green
        : status == 'late'
        ? const Color(0xFFC2413A)
        : AppColors.navy;
    final priorityColor = '${_task?['priority'] ?? ''}' == 'high'
        ? const Color(0xFFC2413A)
        : const Color(0xFFB7791F);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E1EC)),
        boxShadow: const [
          BoxShadow(color: Color(0x0D17324D), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.task_alt_outlined, color: AppColors.navy, size: 25),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _taskTitle(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    height: 1.45,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            textDirection: TextDirection.rtl,
            spacing: 8,
            runSpacing: 8,
            children: [
              _detailBadge(
                icon: Icons.flag_outlined,
                label: 'الأولوية: ${_priorityLabel(_task?['priority'])}',
                color: priorityColor,
              ),
              _detailBadge(
                icon: Icons.timelapse_outlined,
                label: 'الحالة: ${_taskStatusLabel(_task?['status'])}',
                color: statusColor,
              ),
            ],
          ),
          if (_task?['due_at'] != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E8EF)),
              ),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  const Icon(Icons.event_outlined, size: 20, color: AppColors.navy),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'موعد الاستحقاق: ${_localDateTime(_task!['due_at'])}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: color.withValues(alpha: .28)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.rtl,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'تفاصيل المهمة',
    child: _busy
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                TextButton(
                  onPressed: _load,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
            children: [
              _taskOverviewCard(),
              _unifiedTable('${_task?['description'] ?? ''}'),
              if ('${_task?['task_instructions'] ?? ''}'.trim().isNotEmpty)
                SectionCard(
                  title: 'تعليمات التنفيذ',
                  child: Text(
                    '${_task!['task_instructions']}',
                    textAlign: TextAlign.right,
                  ),
                ),
              if (_steps.isNotEmpty)
                SectionCard(
                  title: 'خطوات التنفيذ',
                  child: Column(
                    children: [
                      for (final step in _steps)
                        Column(
                          children: [
                            CheckboxListTile(
                              value: step['completed_at'] != null,
                              onChanged: step['completed_at'] != null
                                  ? null
                                  : (_) => _completeStep('${step['id']}'),
                              title: Text(
                                '${step['title']}',
                                textAlign: TextAlign.right,
                              ),
                              subtitle: Text(
                                '${step['instructions'] ?? ''}',
                                textAlign: TextAlign.right,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            if (step['evidence_required'] == true &&
                                step['completed_at'] == null)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _uploadEvidence('${step['id']}'),
                                  icon: const Icon(Icons.attach_file),
                                  label: Text(
                                    'رفع دليل (${_evidenceIds['${step['id']}']?.length ?? 0})',
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              if (_task?['report_flow'] == 'multi_form')
                for (final form in _forms)
                  Builder(
                    builder: (context) {
                      final snapshotId = '${form['id']}';
                      final schema = List<Map<String, dynamic>>.from(
                        form['schema'] as List,
                      );
                      final status = form['status'];
                      final canSubmitTaskReport = [
                        'in_progress',
                        'on_hold',
                        'needs_revision',
                        'returned',
                      ].contains('${_task?['status']}');
                      final locked =
                          status == 'submitted' || status == 'approved';
                      final savedValues = Map<String, dynamic>.from(
                        (form['values'] as Map?) ?? {},
                      );
                      return SectionCard(
                        title: 'التقرير · ${form['title'] ?? 'نموذج تقرير'}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Chip(
                                avatar: Icon(
                                  status == 'approved'
                                      ? Icons.verified_outlined
                                      : status == 'submitted'
                                      ? Icons.schedule_outlined
                                      : Icons.edit_note_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  status == 'approved'
                                      ? 'معتمد'
                                      : status == 'submitted'
                                      ? 'مرسل للمراجعة'
                                      : 'مسودة قابلة للتعديل',
                                ),
                              ),
                            ),
                            if (form['review_note'] != null)
                              Text(
                                'ملاحظة المراجعة: ${form['review_note']}',
                                textAlign: TextAlign.right,
                              ),
                            if (schema.isEmpty)
                              const Text(
                                'لا يحتوي هذا النموذج على حقول.',
                                textAlign: TextAlign.right,
                              ),
                            for (final field in schema)
                              locked
                                  ? ListTile(
                                      title: Text(
                                        '${field['label'] ?? field['key']}',
                                        textAlign: TextAlign.right,
                                      ),
                                      subtitle: [
                                        'attachment',
                                        'file',
                                        'image',
                                        'multi_image',
                                      ].contains('${field['type'] ?? ''}')
                                          ? _snapshotAttachmentPreview(
                                              savedValues[field['key']],
                                            )
                                          : Text(
                                              _snapshotDisplayValue(
                                                field,
                                                savedValues[field['key']],
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: _snapshotField(field, snapshotId),
                                    ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: _saving
                                    ? null
                                    : () {
                                        final values = locked
                                            ? savedValues
                                            : <String, dynamic>{
                                                for (final field in schema)
                                                  '${field['key']}': _snapshotValue(
                                                    field,
                                                    snapshotId,
                                                  ),
                                              };
                                        _shareSnapshotPdf(
                                          title: _taskTitle(),
                                          reportTitle: '${form['title'] ?? 'نموذج تقرير'}',
                                          schema: schema,
                                          values: values,
                                          status: locked ? '${status == 'approved' ? 'معتمد' : 'مرسل للمراجعة'}' : 'مسودة',
                                        );
                                      },
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('تصدير PDF'),
                              ),
                            ),
                            if (!locked)
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _saveSnapshotDraft(
                                            snapshotId,
                                            schema,
                                          ),
                                    child: const Text('حفظ المسودة'),
                                  ),
                                  FilledButton(
                                    onPressed: _saving || !canSubmitTaskReport
                                        ? null
                                        : () => _submitSnapshot(
                                            snapshotId,
                                            schema,
                                          ),
                                    child: const Text('إرسال النموذج'),
                                  ),
                                ],
                              ),
                            if (!locked && !canSubmitTaskReport)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'ابدأ تنفيذ المهمة أولاً حتى تتمكن من إرسال التقرير للمراجعة.',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(color: Colors.deepOrange),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
              if (_task?['report_flow'] != 'multi_form' && _fields.isNotEmpty)
                SectionCard(
                  title: 'تقرير المهمة',
                  child: Column(
                    children: [
                      for (final field in _fields)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: _inputs['${field['field_key']}'],
                            maxLines: field['field_type'] == 'long_text'
                                ? 4
                                : 1,
                            keyboardType:
                                const [
                                  'integer',
                                  'number',
                                  'decimal',
                                  'money',
                                  'percentage',
                                ].contains(field['field_type'])
                                ? TextInputType.number
                                : TextInputType.text,
                            decoration: InputDecoration(
                              labelText:
                                  '${field['label']}${field['is_required'] == true ? ' *' : ''}',
                              hintText: '${field['field_type'] ?? ''}',
                            ),
                          ),
                        ),
                      FilledButton(
                        onPressed: _saving ||
                                ![
                                  'in_progress',
                                  'on_hold',
                                  'needs_revision',
                                  'returned',
                                ].contains('${_task?['status']}')
                            ? null
                            : _submitReport,
                        child: const Text('إرسال التقرير للمراجعة'),
                      ),
                      if (!["in_progress", "on_hold", "needs_revision", "returned"]
                          .contains('${_task?['status']}'))
                        const Text(
                          'ابدأ تنفيذ المهمة أولاً حتى تتمكن من إرسال التقرير للمراجعة.',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.deepOrange),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (_task != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'حالة المهمة: ${_taskStatusLabel(_task!['status'])}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (['pending', 'new', 'received', 'needs_revision', 'returned'].contains(_task?['status']))
                    FilledButton(
                      onPressed: _saving ? null : () => _status('in_progress'),
                      child: const Text('بدء التنفيذ'),
                    ),
                  if (['in_progress', 'on_hold'].contains(_task?['status']))
                    FilledButton(
                      onPressed: _saving ? null : _submitTaskForReview,
                      child: const Text('تم الإنجاز · إرسال للمراجعة'),
                    ),
                  if (['report_submitted', 'submitted'].contains(_task?['status']))
                    const Chip(
                      avatar: Icon(Icons.hourglass_top_outlined, size: 17),
                      label: Text('بانتظار مراجعة الإدارة'),
                    ),
                  if (['completed_approved', 'approved'].contains(_task?['status']))
                    const Chip(
                      avatar: Icon(Icons.verified_outlined, size: 17),
                      label: Text('مكتملة ومعتمدة'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _goBackFromDetails,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('رجوع'),
                  ),
                ],
              ),
            ],
          ),
  );
}

class SignatureCapture extends StatefulWidget {
  const SignatureCapture({
    super.key,
    required this.strokes,
    required this.enabled,
    required this.onChanged,
  });
  final List<String> strokes;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;
  @override
  State<SignatureCapture> createState() => _SignatureCaptureState();
}

class _SignatureCaptureState extends State<SignatureCapture> {
  late List<String> paths;
  List<Offset> active = [];
  @override
  void initState() {
    super.initState();
    paths = [...widget.strokes];
  }

  @override
  void didUpdateWidget(covariant SignatureCapture oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.strokes.length != widget.strokes.length ||
        oldWidget.strokes.asMap().entries.any(
          (entry) => entry.value != widget.strokes[entry.key],
        );
    if (changed) {
      paths = [...widget.strokes];
      active = [];
    }
  }

  String _encode(List<Offset> p) => p.isEmpty
      ? ''
      : 'M ${p.first.dx.toStringAsFixed(1)} ${p.first.dy.toStringAsFixed(1)}' +
            p
                .skip(1)
                .map(
                  (x) =>
                      ' L ${x.dx.toStringAsFixed(1)} ${x.dy.toStringAsFixed(1)}',
                )
                .join();
  @override
  Widget build(BuildContext c) => Container(
    height: 170,
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey),
      borderRadius: BorderRadius.circular(8),
    ),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: widget.enabled
          ? (d) => setState(() => active = [d.localPosition])
          : null,
      onPanUpdate: widget.enabled
          ? (d) => setState(() => active = [...active, d.localPosition])
          : null,
      onPanEnd: widget.enabled
          ? (_) {
              final p = _encode(active);
              if (p.isNotEmpty && paths.length < 200) {
                paths = [...paths, p];
                widget.onChanged(paths);
              }
              setState(() => active = []);
            }
          : null,
      child: CustomPaint(
        painter: _SignPainter([
          ...paths,
          if (active.isNotEmpty) _encode(active),
        ]),
        size: Size.infinite,
      ),
    ),
  );
}

class _SignPainter extends CustomPainter {
  _SignPainter(this.paths);
  final List<String> paths;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.black
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final x in paths) {
      final n = RegExp(r'\d+(?:\.\d+)?')
          .allMatches(x)
          .map((m) => double.parse(m.group(0)!))
          .toList();
      if (n.length < 2) continue;
      final q = Path()..moveTo(n[0], n[1]);
      for (var i = 2; i + 1 < n.length; i += 2) q.lineTo(n[i], n[i + 1]);
      c.drawPath(q, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SignPainter o) => true;
}
