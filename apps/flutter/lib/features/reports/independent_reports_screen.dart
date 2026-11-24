import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import 'independent_signature_capture.dart';

class IndependentReportsScreen extends StatefulWidget {
  const IndependentReportsScreen({super.key});

  @override
  State<IndependentReportsScreen> createState() =>
      _IndependentReportsScreenState();
}

class _IndependentReportsScreenState extends State<IndependentReportsScreen> {
  final _client = Supabase.instance.client;
  final _values = <String, Map<String, TextEditingController>>{};
  List<_ReportForm> _forms = [];
  Map<String, Map<String, dynamic>> _submissions = {};
  String? _branchId;
  bool _loading = true;
  String? _error;
  String? _notice;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final fields in _values.values) {
      for (final controller in fields.values) controller.dispose();
    }
    super.dispose();
  }

  String get _today {
    final date = DateTime.now().toUtc().add(const Duration(hours: 3));
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final profileRaw = await _client.rpc('mobile_my_profile');
      final root = profileRaw is Map
          ? Map<String, dynamic>.from(profileRaw)
          : <String, dynamic>{};
      final employee = root['employee'];
      if (employee is! Map)
        throw Exception('لا يوجد ملف موظف نشط مرتبط بالحساب.');
      final profile = Map<String, dynamic>.from(employee);
      _branchId = _defaultBranch(profile);
      if (_branchId == null)
        throw Exception(
          'لا يوجد فرع افتراضي مرتبط بحسابك. اطلب من الإدارة تحديد فرعك.',
        );
      final rawForms = await _client.rpc('list_my_dynamic_report_forms');
      final formRows = (rawForms is List ? rawForms : const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _forms = formRows.map(_ReportForm.fromMap).toList();
      _submissions = {
        for (final row in formRows)
          if (row['status'] != null)
            row['template_id'].toString(): {
              'template_id': row['template_id'],
              'version_id': row['version_id'],
              'status': row['status'],
              'review_note': row['review_note'],
              'created_at': row['created_at'],
              'submitted_at': row['submitted_at'],
              'answers': row['values'] is Map ? row['values'] : <String, dynamic>{},
            },
      };
      if (_forms.isNotEmpty) {
        final ids = _forms.map((form) => form.id).toList();
        final rows = await _client
            .from('report_submissions')
            .select(
              'id,form_id,answers,status,review_note,reviewed_by_name,approved_by_name,created_at,submitted_at',
            )
            .eq('employee_id', _client.auth.currentUser!.id)
            .eq('branch_id', _branchId!)
            .eq('report_date', _today)
            .inFilter('form_id', ids);
        for (final row in (rows as List).whereType<Map>()) {
          final formId = row['form_id'].toString();
          final existing = _submissions[formId];
          if (existing == null || existing['status'] == 'draft') {
            _submissions[formId] = Map<String, dynamic>.from(row);
          }
        }
      }
      for (final form in _forms) {
        final controllers = _values.putIfAbsent(
          form.id,
          () => <String, TextEditingController>{},
        );
        final answers = _submissions[form.id]?['answers'];
        final answerMap = answers is Map ? answers : const <dynamic, dynamic>{};
        for (final field in form.fields) {
          final existing = answerMap[field.key];
          final value =
              existing == null && field.config['default_value'] != null
              ? field.config['default_value']
              : existing;
          controllers.putIfAbsent(field.key, TextEditingController.new).text =
              _raw(value);
        }
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _defaultBranch(Map<String, dynamic> profile) {
    final branches = profile['branches'];
    if (branches is! List) return null;
    for (final branch in branches.whereType<Map>()) {
      if (branch['isDefault'] == true || branch['is_default'] == true) {
        final id = branch['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    for (final branch in branches.whereType<Map>()) {
      final id = branch['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  String _raw(Object? value) {
    if (value == null) return '';
    return value is String ? value : jsonEncode(value);
  }

  bool _editable(String formId) {
    final status = _submissions[formId]?['status']?.toString();
    return status == null || status == 'draft' || status == 'returned';
  }

  Future<void> _save(_ReportForm form, {required bool submit}) async {
    if (!_editable(form.id) || _busy != null || _branchId == null) return;
    final controllers = _values[form.id] ?? {};
    final answers = <String, dynamic>{};
    for (final field in form.fields) {
      final raw = controllers[field.key]?.text.trim() ?? '';
      if (submit) {
        final validationError = _validateField(field, raw);
        if (validationError != null) {
          setState(() => _error = validationError);
          return;
        }
      }
      if (raw.isEmpty) continue;
      answers[field.key] = _parse(field.type, raw);
    }
    setState(() {
      _busy = form.id;
      _error = null;
      _notice = null;
    });
    try {
      final current = _submissions[form.id];
      if (!submit && form.versionId != null) {
        await _client.rpc('save_my_dynamic_report_draft', params: {
          'p_template_id': form.id,
          'p_version_id': form.versionId,
          'p_report_date': _today,
          'p_values': answers,
          'p_branch_id': _branchId,
        });
      } else if (submit && form.versionId != null) {
        await _client.rpc('submit_my_dynamic_report', params: {
          'p_template_id': form.id,
          'p_version_id': form.versionId,
          'p_report_date': _today,
          'p_values': answers,
          'p_branch_id': _branchId,
        });
      } else if (current == null) {
        await _client.from('report_submissions').insert({
          'form_id': form.id,
          'employee_id': _client.auth.currentUser!.id,
          'branch_id': _branchId,
          'report_date': _today,
          'answers': answers,
          'status': submit ? 'submitted' : 'draft',
        });
      } else {
        await _client
            .from('report_submissions')
            .update({'answers': answers, if (submit) 'status': 'submitted'})
            .eq('id', current['id']);
      }
      if (mounted)
        setState(
          () => _notice = submit
              ? 'تم ترحيل التقرير نهائيًا وإرساله للمراجعة.'
              : 'تم الترحيل غير النهائي. يمكنك مواصلة التعديل قبل الترحيل النهائي.',
        );
      await _load();
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'تعذر حفظ التقرير. تحقق من الاتصال وصلاحية النموذج ثم حاول مجددًا.',
        );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  dynamic _parse(String type, String raw) {
    if (const {
      'table',
      'multiselect',
      'signature',
      'date_range',
      'attachment',
      'file',
      'image',
      'multi_image',
    }.contains(type)) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }
    if (const {
      'number',
      'integer',
      'decimal',
      'percentage',
      'quantity',
      'money',
      'progress',
    }.contains(type)) {
      return num.tryParse(raw) ?? raw;
    }
    if (type == 'boolean' || type == 'checkbox')
      return raw == 'true'
          ? true
          : raw == 'false'
          ? false
          : raw;
    return raw;
  }

  String? _validateField(_ReportField field, String raw) {
    if (raw.isEmpty)
      return field.required ? 'الحقل «${field.label}» مطلوب.' : null;
    final config = field.config;
    final min = num.tryParse('${config['min'] ?? config['min_value'] ?? ''}');
    final max = num.tryParse('${config['max'] ?? config['max_value'] ?? ''}');
    final minLength = int.tryParse('${config['min_length'] ?? ''}');
    final maxLength = int.tryParse('${config['max_length'] ?? ''}');
    if (minLength != null && raw.length < minLength) {
      return 'الحقل «${field.label}» أقصر من الحد المسموح.';
    }
    if (maxLength != null && raw.length > maxLength) {
      return 'الحقل «${field.label}» أطول من الحد المسموح.';
    }
    if (const {
      'number',
      'integer',
      'decimal',
      'percentage',
      'quantity',
      'money',
      'progress',
    }.contains(field.type)) {
      final value = num.tryParse(raw);
      if (value == null) return 'أدخل رقمًا صحيحًا في الحقل «${field.label}».';
      if (field.type == 'integer' && value % 1 != 0) {
        return 'الحقل «${field.label}» يقبل أعدادًا صحيحة فقط.';
      }
      if (min != null && value < min)
        return 'قيمة «${field.label}» أقل من الحد الأدنى.';
      if (max != null && value > max)
        return 'قيمة «${field.label}» أكبر من الحد الأعلى.';
    }
    if (field.type == 'select' &&
        field.options.isNotEmpty &&
        !field.options.contains(raw)) {
      return 'اختر قيمة صحيحة للحقل «${field.label}».';
    }
    if (field.type == 'multiselect') {
      try {
        final values = jsonDecode(raw);
        if (values is! List ||
            values.any((value) => !field.options.contains(value.toString()))) {
          return 'توجد قيمة غير مسموحة في «${field.label}».';
        }
      } catch (_) {
        return 'أدخل الاختيارات المتعددة للحقل «${field.label}» بصيغة صحيحة.';
      }
    }
    if (field.type == 'date' && DateTime.tryParse(raw) == null) {
      return 'استخدم تاريخًا صحيحًا في الحقل «${field.label}».';
    }
    if (field.type == 'date_range' || field.type == 'table') {
      try {
        if (jsonDecode(raw) is! List)
          return 'قيمة «${field.label}» يجب أن تكون قائمة.';
      } catch (_) {
        return 'أدخل قيمة «${field.label}» بصيغة JSON صحيحة.';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'تقارير الموظف',
    subtitle: 'نماذج التقارير المستقلة اليومية',
    child: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'تقارير الموظف المستقلة',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'رحّل التقرير غير نهائيًا أثناء الإكمال، ثم رحّله نهائيًا عند الجاهزية للمراجعة.',
                  textAlign: TextAlign.right,
                ),
                if (_error != null) _message(_error!, warning: true),
                if (_notice != null) _message(_notice!),
                if (_forms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'لا توجد نماذج تقارير معتمدة لدورك اليوم.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final form in _forms) _formCard(form),
              ],
            ),
    ),
  );

  Widget _formCard(_ReportForm form) {
    final current = _submissions[form.id];
    final status = current?['status']?.toString() ?? 'draft';
    final locked = !_editable(form.id);
    final controllers = _values[form.id] ?? {};
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              form.title,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (form.description.isNotEmpty)
              Text(form.description, textAlign: TextAlign.right),
            Text(
              'التاريخ: $_today · الحالة: ${_status(status)}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            if ((current?['review_note'] ?? '').toString().trim().isNotEmpty)
              _message(
                'ملاحظة الإدارة: ${current?['review_note']}',
                warning: true,
              ),
            for (final field in form.fields) ...[
              const SizedBox(height: 10),
              Text(
                '${field.label}${field.required ? ' *' : ''}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              _fieldEditor(field, controllers[field.key]!, locked),
            ],
            if (!locked) ...[
              const SizedBox(height: 12),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy == form.id
                          ? null
                          : () => _save(form, submit: false),
                      child: Text(
                        _busy == form.id ? 'جارٍ الحفظ…' : 'ترحيل غير نهائي',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy == form.id
                          ? null
                          : () => _save(form, submit: true),
                      child: Text(
                        _busy == form.id
                            ? 'جارٍ الإرسال…'
                            : status == 'returned'
                            ? 'إعادة الترحيل النهائي'
                            : 'ترحيل نهائي',
                      ),
                    ),
                  ),
                ],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'تم قفل الإجابات أثناء المراجعة والاعتماد.',
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fieldEditor(
    _ReportField field,
    TextEditingController controller,
    bool locked,
  ) {
    if (field.type == 'boolean' || field.type == 'checkbox') {
      final selected = controller.text;
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('نعم'),
            selected: selected == 'true',
            onSelected: locked
                ? null
                : (_) => setState(() => controller.text = 'true'),
          ),
          ChoiceChip(
            label: const Text('لا'),
            selected: selected == 'false',
            onSelected: locked
                ? null
                : (_) => setState(() => controller.text = 'false'),
          ),
        ],
      );
    }
    if (field.type == 'select' && field.options.isNotEmpty) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: field.options
            .map(
              (option) => ChoiceChip(
                label: Text(option),
                selected: controller.text == option,
                onSelected: locked
                    ? null
                    : (_) => setState(() => controller.text = option),
              ),
            )
            .toList(),
      );
    }
    if (field.type == 'multiselect' && field.options.isNotEmpty) {
      List<String> selected = [];
      try {
        final decoded = jsonDecode(controller.text);
        if (decoded is List)
          selected = decoded.map((value) => value.toString()).toList();
      } catch (_) {}
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: field.options.map((option) {
          final active = selected.contains(option);
          return FilterChip(
            label: Text(option),
            selected: active,
            onSelected: locked
                ? null
                : (value) {
                    final next = [...selected];
                    value ? next.add(option) : next.remove(option);
                    setState(() => controller.text = jsonEncode(next));
                  },
          );
        }).toList(),
      );
    }
    if (field.type == 'table') {
      return _tableEditor(field, controller, locked);
    }
    if (field.type == 'signature') {
      return _signatureEditor(field, controller, locked);
    }
    if (const {
      'attachment',
      'file',
      'image',
      'multi_image',
    }.contains(field.type)) {
      return _attachmentEditor(field, controller, locked);
    }
    return TextField(
      controller: controller,
      enabled: !locked,
      textAlign: TextAlign.right,
      maxLines: field.longText ? 4 : 1,
      keyboardType:
          const {
            'number',
            'integer',
            'decimal',
            'percentage',
            'quantity',
            'money',
            'progress',
          }.contains(field.type)
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: _hint(field.type),
        border: const OutlineInputBorder(),
      ),
    );
  }

  List<Map<String, dynamic>> _tableRows(TextEditingController controller) {
    try {
      final value = jsonDecode(controller.text);
      if (value is List) {
        return value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  List<Map<String, dynamic>> _tableColumns(_ReportField field) {
    final raw = field.config['columns'];
    if (raw is! List)
      return [
        {'key': 'value', 'label': 'القيمة', 'type': 'short_text'},
      ];
    final columns = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is String) {
        columns.add({'key': item, 'label': item, 'type': 'short_text'});
      } else if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        columns.add({
          'key': (map['key'] ?? 'column_${i + 1}').toString(),
          'label': (map['label'] ?? map['name'] ?? map['key'] ?? 'عمود')
              .toString(),
          'type': (map['type'] ?? map['field_type'] ?? 'short_text').toString(),
          'options': map['options'] is List
              ? (map['options'] as List).map((e) => e.toString()).toList()
              : <String>[],
        });
      }
    }
    return columns.isEmpty
        ? [
            {'key': 'value', 'label': 'القيمة', 'type': 'short_text'},
          ]
        : columns;
  }

  Widget _tableEditor(
    _ReportField field,
    TextEditingController controller,
    bool locked,
  ) {
    final columns = _tableColumns(field);
    final rows = _tableRows(controller);
    void saveRows(List<Map<String, dynamic>> next) =>
        setState(() => controller.text = jsonEncode(next));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: const Color(0xFFF7FAFB),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        child: Text(
                          'الصف ${rowIndex + 1}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف الصف',
                        onPressed: locked
                            ? null
                            : () {
                                final next = [...rows]..removeAt(rowIndex);
                                saveRows(next);
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  for (final column in columns)
                    _tableCell(
                      column,
                      row: rows[rowIndex],
                      locked: locked,
                      onChanged: (value) {
                        final next = [...rows];
                        next[rowIndex] = {
                          ...next[rowIndex],
                          column['key'].toString(): value,
                        };
                        saveRows(next);
                      },
                    ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: locked
              ? null
              : () {
                  final row = <String, dynamic>{
                    for (final column in columns) column['key'].toString(): '',
                  };
                  saveRows([...rows, row]);
                },
          icon: const Icon(Icons.add),
          label: const Text('إضافة صف'),
        ),
      ],
    );
  }

  Widget _tableCell(
    Map<String, dynamic> column, {
    required Map<String, dynamic> row,
    required bool locked,
    required ValueChanged<String> onChanged,
  }) {
    final key = column['key'].toString();
    final type = column['type'].toString();
    final value = row[key]?.toString() ?? '';
    final options = column['options'] is List
        ? (column['options'] as List).map((e) => e.toString()).toList()
        : <String>[];
    if (type == 'select' && options.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          children: [
            Text('${column['label']}:', textAlign: TextAlign.right),
            ...options.map(
              (option) => ChoiceChip(
                label: Text(option),
                selected: value == option,
                onSelected: locked ? null : (_) => onChanged(option),
              ),
            ),
          ],
        ),
      );
    }
    if (type == 'boolean') {
      return CheckboxListTile(
        value: value == 'true',
        title: Text(column['label'].toString(), textAlign: TextAlign.right),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: locked
            ? null
            : (checked) => onChanged(checked == true ? 'true' : 'false'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        enabled: !locked,
        textAlign: TextAlign.right,
        initialValue: value,
        keyboardType:
            const {'integer', 'decimal', 'quantity', 'money'}.contains(type)
            ? TextInputType.number
            : TextInputType.text,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: column['label'].toString(),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _signatureEditor(
    _ReportField field,
    TextEditingController controller,
    bool locked,
  ) {
    Map<String, dynamic> value = {};
    try {
      final decoded = jsonDecode(controller.text);
      if (decoded is Map) value = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final strokes = value['strokes'] is List
        ? (value['strokes'] as List).whereType<String>().toList()
        : <String>[];
    final consent = (field.config['consent_text'] ?? '').toString().trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (consent.isNotEmpty) Text(consent, textAlign: TextAlign.right),
        IndependentSignatureCapture(
          strokes: strokes,
          enabled: !locked,
          onChanged: (next) => setState(
            () => controller.text = jsonEncode({...value, 'strokes': next}),
          ),
        ),
        if (consent.isNotEmpty)
          CheckboxListTile(
            value: value['acknowledged'] == true,
            title: const Text('أوافق على نص الإقرار'),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: locked
                ? null
                : (checked) => setState(
                    () => controller.text = jsonEncode({
                      ...value,
                      'strokes': strokes,
                      'acknowledged': checked == true,
                    }),
                  ),
          ),
        TextButton.icon(
          onPressed: locked
              ? null
              : () => setState(
                  () => controller.text = jsonEncode({
                    'strokes': <String>[],
                    'acknowledged': false,
                  }),
                ),
          icon: const Icon(Icons.delete_outline),
          label: const Text('مسح التوقيع'),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _attachments(TextEditingController controller) {
    try {
      final value = jsonDecode(controller.text);
      if (value is List)
        return value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    } catch (_) {}
    return [];
  }

  Future<void> _pickAttachments(
    _ReportField field,
    TextEditingController controller,
  ) async {
    try {
      final existing = _attachments(controller);
      final allowMultiple =
          field.type == 'attachment' ||
          field.type == 'file' ||
          field.type == 'multi_image';
      final pickerType = field.type == 'image' || field.type == 'multi_image'
          ? FileType.image
          : FileType.any;
      final files = allowMultiple
          ? await FilePicker.pickFiles(type: pickerType)
          : [
              if (await FilePicker.pickFile(type: pickerType) case final file?)
                file,
            ];
      if (files.isEmpty) return;
      final max = field.type == 'image' ? 1 : 5;
      if (existing.length + files.length > max)
        throw Exception('الحد الأقصى $max مرفقات لهذا الحقل.');
      final next = [...existing];
      for (final file in files) {
        final size = await file.length() ?? 0;
        if (size <= 0 || size > 2 * 1024 * 1024) {
          throw Exception('حجم المرفق يجب ألا يتجاوز 2 ميجابايت.');
        }
        final bytes = await file.readAsBytes();
        final mime = lookupMimeType(file.name) ?? 'application/octet-stream';
        if ((field.type == 'image' || field.type == 'multi_image') &&
            !mime.startsWith('image/')) {
          throw Exception('اختر ملف صورة فقط.');
        }
        next.add({
          'name': file.name,
          'mimeType': mime,
          'size': size,
          'contentBase64': base64Encode(bytes),
        });
      }
      setState(() => controller.text = jsonEncode(next));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر إضافة المرفق: $error')));
    }
  }

  Widget _attachmentEditor(
    _ReportField field,
    TextEditingController controller,
    bool locked,
  ) {
    final items = _attachments(controller);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${items[index]['name'] ?? 'مرفق'}',
              textAlign: TextAlign.right,
            ),
            subtitle: Text(
              '${items[index]['mimeType'] ?? ''} · ${items[index]['size'] ?? 0} بايت',
              textAlign: TextAlign.right,
            ),
            trailing: IconButton(
              tooltip: 'حذف المرفق',
              onPressed: locked
                  ? null
                  : () {
                      final next = [...items]..removeAt(index);
                      setState(() => controller.text = jsonEncode(next));
                    },
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        OutlinedButton.icon(
          onPressed: locked ? null : () => _pickAttachments(field, controller),
          icon: const Icon(Icons.attach_file),
          label: Text(items.isEmpty ? 'إضافة مرفق' : 'إضافة مرفق آخر'),
        ),
        const Text(
          'يُحفظ المرفق حاليًا داخل إجابة التقرير بحجم أقصى 2 ميجابايت لكل ملف؛ عقد التخزين المنفصل للتقارير غير موجود بعد.',
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }

  String _status(String status) => switch (status) {
    'draft' => 'مسودة',
    'submitted' => 'بانتظار المراجعة',
    'reviewed' => 'بانتظار الاعتماد',
    'approved' => 'معتمد نهائيًا',
    'returned' => 'معاد للتعديل',
    _ => status,
  };

  String _hint(String type) =>
      const {
        'table',
        'multiselect',
        'signature',
        'date_range',
        'attachment',
        'file',
        'image',
        'multi_image',
      }.contains(type)
      ? 'أدخل القيمة بصيغة JSON'
      : type == 'datetime'
      ? 'يُسجل الوقت عند إدخال الإجابة'
      : 'اكتب الإجابة هنا';

  Widget _message(String text, {bool warning = false}) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF1DC) : const Color(0xFFE8F5EB),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(text, textAlign: TextAlign.right),
  );
}

class _ReportForm {
  const _ReportForm({
    required this.id,
    required this.title,
    required this.description,
    required this.versionId,
    required this.fields,
  });
  final String id;
  final String title;
  final String description;
  final String? versionId;
  final List<_ReportField> fields;

  factory _ReportForm.fromMap(Map<String, dynamic> map) => _ReportForm(
    id: map['template_id'].toString(),
    title: (map['title'] ?? 'نموذج تقرير').toString(),
    description: (map['description'] ?? '').toString(),
    versionId: map['version_id']?.toString(),
    fields: (map['fields'] is List ? map['fields'] as List : const [])
        .whereType<Map>()
        .map((field) => _ReportField.fromMap(Map<String, dynamic>.from(field)))
        .toList(),
  );
}

class _ReportField {
  const _ReportField({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    required this.longText,
    required this.options,
    required this.config,
  });
  final String key;
  final String label;
  final String type;
  final bool required;
  final bool longText;
  final List<String> options;
  final Map<String, dynamic> config;

  factory _ReportField.fromMap(Map<String, dynamic> map) => _ReportField(
    key: (map['key'] ?? '').toString(),
    label: (map['label'] ?? map['key'] ?? 'حقل').toString(),
    type: (map['type'] ?? 'short_text').toString(),
    required: map['required'] == true,
    longText: const {
      'long_text',
      'textarea',
      'notes',
      'decision_notes',
      'table',
      'multiselect',
      'date_range',
      'signature',
    }.contains(map['type']),
    options: (map['options'] is List ? map['options'] as List : const [])
        .map((value) => value.toString())
        .toList(),
    config: map['config'] is Map
        ? Map<String, dynamic>.from(map['config'] as Map)
        : <String, dynamic>{},
  );
}
