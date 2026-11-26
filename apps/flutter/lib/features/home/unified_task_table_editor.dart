import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme.dart';
import '../../shared/app_customizer.dart';
import '../../shared/report_pdf_theme.dart';

typedef AutomaticReportSchemaBuilder = List<Map<String, dynamic>> Function(
  UnifiedTaskRowData row,
  String purpose,
  List<String> instructions,
  List<String> kpis,
);

class UnifiedTaskTableEditor extends StatefulWidget {
  const UnifiedTaskTableEditor({super.key, required this.onSend, this.onSave, this.initialDraft, this.employees = const [], this.branches = const [], this.reports = const [], this.onChanged, this.reportSchemaBuilder});
  final Future<void> Function(UnifiedTaskTableDraft draft) onSend;
  final Future<void> Function(UnifiedTaskTableDraft draft)? onSave;
  final UnifiedTaskTableDraft? initialDraft;
  final List<UnifiedEmployeeOption> employees;
  final List<UnifiedBranchOption> branches;
  final List<UnifiedReportOption> reports;
  final VoidCallback? onChanged;
  final AutomaticReportSchemaBuilder? reportSchemaBuilder;

  @override
  State<UnifiedTaskTableEditor> createState() => _UnifiedTaskTableEditorState();
}

class _UnifiedTaskTableEditorState extends State<UnifiedTaskTableEditor> {
  final _purpose = TextEditingController();
  final _reportNotes = TextEditingController();
  final _employee = TextEditingController();
  final _role = TextEditingController();
  final _branch = TextEditingController();
  final _startDate = TextEditingController();
  final _firstPeriod = TextEditingController();
  final _breakPeriod = TextEditingController();
  final _secondPeriod = TextEditingController();
  final _responsibilities = <TextEditingController>[TextEditingController()];
  final _authorities = <TextEditingController>[TextEditingController()];
  final _instructions = <TextEditingController>[TextEditingController()];
  final _kpis = <List<TextEditingController>>[
    [TextEditingController(), TextEditingController()],
  ];
  final _rows = <_UnifiedRow>[_UnifiedRow('08:00', '', '')];
  final _exceptionRows = <_UnifiedRow>[];
  bool _expanded = true;
  bool _sending = false;
  bool _sent = false;
  String _workType = 'دوام كامل';
  String _days = 'الأحد - الخميس';
  String _exception = 'الجمعة';
  String? _reportVersionId;
  String? _reportTemplateId;
  final Map<String, List<Map<String, dynamic>>> _customReportSchemas = {};

  @override
  void initState() {
    super.initState();
    AppCustomizer.instance.load();
    _startDate.text = _formatDate(DateTime.now());
    _applyInitialDraft(widget.initialDraft);
  }

  void _applyInitialDraft(UnifiedTaskTableDraft? draft) {
    if (draft == null) return;
    _employee.text = draft.employee;
    _role.text = draft.role;
    _branch.text = draft.branch;
    _startDate.text = draft.startDate.isEmpty ? _startDate.text : draft.startDate;
    _purpose.text = draft.purpose;
    _reportNotes.text = draft.reportNotes;
    _workType = draft.workType.isEmpty ? _workType : draft.workType;
    _days = draft.workDays.isEmpty ? _days : draft.workDays;
    _exception = draft.weeklyException.isEmpty ? _exception : draft.weeklyException;
    _firstPeriod.text = draft.firstPeriod;
    _breakPeriod.text = draft.breakPeriod;
    _secondPeriod.text = draft.secondPeriod;
    _reportTemplateId = draft.reportTemplateId;
    _reportVersionId = draft.reportVersionId;
    _replaceRows(_rows, draft.rows);
    _replaceRows(_exceptionRows, const []);
    _replaceList(_responsibilities, draft.responsibilities);
    _replaceList(_authorities, draft.authorities);
    _replaceList(_instructions, draft.instructions);
    _replaceKpis(draft.kpis);
  }

  void _replaceRows(List<_UnifiedRow> target, List<UnifiedTaskRowData> source) {
    for (final row in target) row.dispose();
    target
      ..clear()
      ..addAll(source.isEmpty ? [_UnifiedRow('', '', '')] : source.map((row) => _UnifiedRow(row.time, row.task, row.output, row.extras)));
  }

  void _replaceList(List<TextEditingController> target, List<String> source) {
    for (final controller in target) controller.dispose();
    target
      ..clear()
      ..addAll((source.isEmpty ? [''] : source).map((value) => TextEditingController(text: value)));
  }

  void _replaceKpis(List<String> source) {
    for (final row in _kpis) {
      for (final controller in row) controller.dispose();
    }
    _kpis
      ..clear()
      ..addAll((source.isEmpty ? [''] : source).map((value) {
        final parts = value.split(':');
        return [TextEditingController(text: parts.first.trim()), TextEditingController(text: parts.length > 1 ? parts.sublist(1).join(':').trim() : '')];
      }));
  }

  @override
  void dispose() {
    _purpose.dispose();
    _reportNotes.dispose();
    _employee.dispose();
    _role.dispose();
    _branch.dispose();
    _startDate.dispose();
    _firstPeriod.dispose();
    _breakPeriod.dispose();
    _secondPeriod.dispose();
    for (final list in [_responsibilities, _authorities, _instructions]) {
      for (final controller in list) controller.dispose();
    }
    for (final row in _kpis) {
      for (final controller in row) controller.dispose();
    }
    for (final row in _rows) row.dispose();
    for (final row in _exceptionRows) row.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UnifiedTaskTableEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reports != widget.reports && _reportVersionId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _suggestReportForRole(_role.text);
      });
    }
  }

  void _addTextRow(List<TextEditingController> list) {
    widget.onChanged?.call();
    setState(() => list.add(TextEditingController()));
  }

  void _removeTextRow(List<TextEditingController> list, int index) {
    if (list.length == 1) return;
    widget.onChanged?.call();
    final controller = list.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildEditor(context);
    } catch (error) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 42),
              const SizedBox(height: 8),
              const Text('تعذر بناء محرر الجدول الموحد', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => AppCustomizer.instance.resetUnified()),
                icon: const Icon(Icons.restore),
                label: const Text('استعادة إعدادات الجدول'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildEditor(BuildContext context) => AnimatedBuilder(
    animation: AppCustomizer.instance,
    builder: (context, _) => Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppCustomizer.instance.unifiedRadius), side: const BorderSide(color: Color(0xFFD8E4E0))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(textDirection: TextDirection.rtl, children: [
            const Icon(Icons.table_chart_outlined, color: AppColors.green), const SizedBox(width: 8),
            Expanded(child: Text(AppCustomizer.instance.unifiedLabel('screenTitle'), textAlign: TextAlign.right, style: TextStyle(fontSize: 16 * AppCustomizer.instance.unifiedFontScale, fontWeight: FontWeight.w900, color: AppColors.navy))),
            IconButton(onPressed: () => setState(() => _expanded = !_expanded), icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more), tooltip: _expanded ? 'طي التفاصيل' : 'إظهار التفاصيل'),
          ]),
          if (_expanded) ...[
            const Divider(height: 16), _toolbar(),
            ..._unifiedSections(),
            const SizedBox(height: 12),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(textDirection: TextDirection.rtl, children: [
                  Expanded(child: FilledButton.icon(onPressed: _sending || (_sent && widget.onSave == null) ? null : _submit, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(widget.onSave != null ? Icons.save_outlined : _sent ? Icons.check_circle_outline : Icons.send_outlined), label: Text(_sending ? 'جارٍ الحفظ...' : widget.onSave != null ? 'حفظ التعديلات' : _sent ? 'تم الإرسال' : 'حفظ الجدول وإرساله'))),
                  const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('تصدير PDF'))),
                ]),
              ),
            ),
          ],
        ]),
      ),
    ),
  );

  List<Widget> _unifiedSections() {
    final store = AppCustomizer.instance;
    final sections = <String, Widget>{
      'employee': _employeeCard(),
      'purpose': _section(store.unifiedLabel('purpose'), TextField(controller: _purpose, onChanged: (_) => widget.onChanged?.call(), textAlign: TextAlign.right, maxLines: 2, decoration: InputDecoration(hintText: store.unifiedLabel('purposeHint')))),
      'hours': _workHours(),
      'daily': _scheduleTable(store.unifiedLabel('daily'), _rows),
      'exception': _scheduleTable('${store.unifiedLabel('exception')} ($_exception)', _exceptionRows),
      'report': _reportSelector(),
      'lists': Column(children: [_editableList('المسؤوليات الأساسية', _responsibilities), const SizedBox(height: 10), _editableList('الصلاحيات وحدود المسؤولية', _authorities), const SizedBox(height: 10), _editableList('التوصيات والتعليمات الإدارية', _instructions)]),
      'kpi': _kpiTable(),
      'notes': _section(store.unifiedLabel('notes'), TextField(controller: _reportNotes, onChanged: (_) => widget.onChanged?.call(), textAlign: TextAlign.right, maxLines: 3, decoration: const InputDecoration(hintText: 'تعليمات إضافية اختيارية؛ نموذج التقرير يحدده القالب المعتمد'))),
      'approval': _approvalStatus(),
    };
    final visibleKeys = store.unifiedSectionOrder
        .where((key) => store.isUnifiedVisible(key))
        .where(sections.containsKey)
        .toList();
    if (visibleKeys.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.only(top: store.unifiedSpacing),
          child: _section(
            'لا توجد أقسام ظاهرة',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'تم إخفاء جميع أقسام الجدول الموحد من مصمم الواجهات. أظهر قسمًا واحدًا على الأقل للمتابعة.',
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => setState(() => store.resetUnified()),
                    icon: const Icon(Icons.restore),
                    label: const Text('استعادة الأقسام الافتراضية'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return visibleKeys
        .map((key) => Padding(
              padding: EdgeInsets.only(top: store.unifiedSpacing),
              child: sections[key]!,
            ))
        .toList();
  }

  Widget _toolbar() => Wrap(
    textDirection: TextDirection.rtl,
    spacing: 7,
    runSpacing: 7,
    children: [
      IconButton(onPressed: () { widget.onChanged?.call(); setState(() => _rows.add(_UnifiedRow('', '', ''))); }, icon: const Icon(Icons.add_box_outlined), tooltip: 'إضافة صف يومي'),
      IconButton(onPressed: () { widget.onChanged?.call(); setState(() => _exceptionRows.add(_UnifiedRow('', '', ''))); }, icon: const Icon(Icons.event_available_outlined), tooltip: 'إضافة صف استثنائي'),
    ],
  );

  Widget _employeeCard() => _section(AppCustomizer.instance.unifiedLabel('employee'), LayoutBuilder(builder: (context, constraints) {
    final fields = <String, Widget>{'employeeField': _employeeField(), 'roleField': _roleField(), 'branchField': _branchField(), 'startDate': _dateField()};
    final keys = fields.keys.where(AppCustomizer.instance.isUnifiedFieldVisible).toList()..sort((a, b) { final la = AppCustomizer.instance.unifiedFieldLayout(a), lb = AppCustomizer.instance.unifiedFieldLayout(b); final row = ((la['row'] as num?)?.toInt() ?? 0).compareTo((lb['row'] as num?)?.toInt() ?? 0); return row != 0 ? row : ((la['column'] as num?)?.toInt() ?? 0).compareTo((lb['column'] as num?)?.toInt() ?? 0); });
    return Wrap(textDirection: TextDirection.rtl, spacing: AppCustomizer.instance.unifiedSpacing, runSpacing: AppCustomizer.instance.unifiedSpacing, children: keys.map((key) { final layout = AppCustomizer.instance.unifiedFieldLayout(key); final span = '${layout['span'] ?? 'half'}'; final width = span == 'full' ? constraints.maxWidth : span == 'third' ? (constraints.maxWidth - AppCustomizer.instance.unifiedSpacing * 2) / 3 : (constraints.maxWidth - AppCustomizer.instance.unifiedSpacing) / 2; return SizedBox(width: width, child: Align(alignment: _alignment('${layout['align'] ?? 'right'}'), child: fields[key])); }).toList());
  }));

  Alignment _alignment(String value) => value == 'left' ? Alignment.centerLeft : value == 'center' ? Alignment.center : Alignment.centerRight;

  Widget _employeeField() => widget.employees.isEmpty
      ? _input(_employee, AppCustomizer.instance.unifiedLabel('employeeField'))
      : DropdownButtonFormField<String>(
          value: widget.employees.any((item) => item.name == _employee.text) ? _employee.text : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: AppCustomizer.instance.unifiedLabel('employeeField'), isDense: true),
          items: widget.employees.map((item) => DropdownMenuItem(value: item.name, child: Text(item.name, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (value) {
            widget.onChanged?.call();
            setState(() => _employee.text = value ?? '');
            _suggestReportForRole(_role.text);
          },
        );

  Widget _roleField() => DropdownButtonFormField<String>(
    value: const ['المحاسب', 'أمين مخزن', 'عامل تحميل', 'المدير التنفيذي', 'صاحب المؤسسة'].contains(_role.text) ? _role.text : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: AppCustomizer.instance.unifiedLabel('roleField'), isDense: true),
    items: const ['المحاسب', 'أمين مخزن', 'عامل تحميل', 'المدير التنفيذي', 'صاحب المؤسسة'].map((value) => DropdownMenuItem(value: value, child: Text(value, overflow: TextOverflow.ellipsis))).toList(),
    onChanged: (value) {
      if (value == null) return;
      setState(() => _role.text = value);
      _suggestReportForRole(value);
    },
  );

  Widget _branchField() => widget.branches.isEmpty
      ? _input(_branch, AppCustomizer.instance.unifiedLabel('branchField'))
      : DropdownButtonFormField<String>(
          value: widget.branches.any((item) => item.name == _branch.text)
              ? _branch.text
              : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: AppCustomizer.instance.unifiedLabel('branchField'), isDense: true),
          items: widget.branches
              .map((item) => DropdownMenuItem(
                    value: item.name,
                    child: Text(item.name, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _branch.text = value ?? ''),
        );

  UnifiedReportOption? get _selectedReport {
    for (final item in widget.reports) {
      if (item.versionId == _reportVersionId) return item;
    }
    return null;
  }

  void _suggestReportForRole(String role) {
    if (widget.reports.isEmpty || role.trim().isEmpty) return;
    final roleMap = <String, String>{
      'المحاسب': 'accountant',
      'أمين المخزن': 'warehouse_keeper',
      'أمين مخزن': 'warehouse_keeper',
      'عامل تحميل': 'warehouse_worker',
      'المدير التنفيذي': 'admin_followup',
      'صاحب المؤسسة': 'owner',
    };
    final code = roleMap[role.trim()] ?? role.trim();
    final matches = widget.reports.where((item) => item.roleCode == code).toList();
    final match = matches.isEmpty ? null : matches.first;
    if (match == null || _reportVersionId == match.versionId) return;
    setState(() {
      _reportVersionId = match.versionId;
      _reportTemplateId = match.templateId;
    });
  }

  List<UnifiedTaskRowData> _currentTaskRows() {
    final rows = _rows
        .where((row) => row.task.text.trim().isNotEmpty)
        .map((row) => UnifiedTaskRowData(
              time: row.time.text.trim(),
              task: row.task.text.trim(),
              output: row.output.text.trim(),
              extras: row.extras,
            ))
        .toList();
    rows.addAll(_exceptionRows
        .where((row) => row.task.text.trim().isNotEmpty)
        .map((row) => UnifiedTaskRowData(
              time: '${_exception}: ${row.time.text.trim()}',
              task: row.task.text.trim(),
              output: row.output.text.trim(),
              extras: row.extras,
            )));
    return rows;
  }

  List<Map<String, dynamic>> _automaticSchemaFor(UnifiedTaskRowData row) =>
      _customReportSchemas[unifiedTaskReportKey(row)] ??
      widget.reportSchemaBuilder?.call(
            row,
            _purpose.text.trim(),
            _instructions
                .map((value) => value.text.trim())
                .where((value) => value.isNotEmpty)
                .toList(),
            _kpis
                .where((value) => value.any((controller) => controller.text.trim().isNotEmpty))
                .map((value) => '${value[0].text.trim()}: ${value[1].text.trim()}')
                .toList(),
          ) ??
      [
        {'key': 'actual_result', 'label': 'النتيجة الفعلية', 'type': 'textarea', 'required': true},
        {'key': 'execution_status', 'label': 'حالة التنفيذ', 'type': 'select', 'required': true, 'options': ['مكتملة', 'مكتملة جزئيًا', 'تعذر التنفيذ']},
      ];

  Widget _reportSelector() {
    final selected = _selectedReport;
    final tasks = _currentTaskRows();
    return _section(
      AppCustomizer.instance.unifiedLabel('report'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.reports.isEmpty)
            const Text('سيُنشئ النظام تقريرًا تلقائيًا مناسبًا لكل مهمة، ويمكنك معاينته وتعديله قبل الإرسال.', textAlign: TextAlign.right)
          else
            DropdownButtonFormField<String>(
              value: selected?.versionId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'قالب التقرير اليدوي (اختياري)', isDense: true),
              items: widget.reports.map((item) => DropdownMenuItem(value: item.versionId, child: Text(item.title, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (value) {
                if (value == null) return;
                final item = widget.reports.firstWhere((item) => item.versionId == value);
                setState(() { _reportVersionId = value; _reportTemplateId = item.templateId; });
              },
            ),
          if (selected != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFEAF4F0), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFB8CEC5))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(selected.title, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy)),
                  const SizedBox(height: 5),
                  Text('الإصدار ${selected.versionNumber} · ${selected.fieldCount} حقول · ${selected.requiredFieldCount} إلزامية', textAlign: TextAlign.right),
                  const SizedBox(height: 5),
                  const Text('يمكن معاينة التقرير الخاص بكل مهمة وتعديله قبل الإرسال.', textAlign: TextAlign.right, style: TextStyle(fontSize: 12)),
                  Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _previewSelectedReport, icon: const Icon(Icons.preview_outlined), label: const Text('معاينة التقرير'))),
                ],
              ),
            ),
          ],
          if (tasks.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _previewAutomaticReport(tasks),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('معاينة وتعديل تقرير المهمة قبل الإرسال'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _previewAutomaticReport(List<UnifiedTaskRowData> tasks) async {
    var selectedIndex = 0;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final row = tasks[selectedIndex];
          final schema = _automaticSchemaFor(row)
              .map((field) => <String, dynamic>{
                    ...field,
                    if (field['options'] is List) 'options': [...field['options'] as List],
                  })
              .toList();
          final schemaKey = unifiedTaskReportKey(row);
          void refresh() => setDialogState(() {});
          return AlertDialog(
            title: const Text('معاينة وتعديل تقرير المهمة', textAlign: TextAlign.right),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedIndex,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'المهمة', isDense: true),
                      items: tasks.asMap().entries.map((entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value.task, overflow: TextOverflow.ellipsis),
                          )).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedIndex = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text('حقول التقرير: ${schema.length}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...schema.asMap().entries.map((entry) {
                      final index = entry.key;
                      final field = entry.value;
                      final type = '${field['type'] ?? 'text'}';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              Row(children: [
                                Expanded(child: TextFormField(initialValue: '${field['label'] ?? ''}', textAlign: TextAlign.right, decoration: const InputDecoration(labelText: 'اسم الحقل', isDense: true), onChanged: (value) { field['label'] = value; _customReportSchemas[schemaKey] = schema; })),
                                IconButton(onPressed: () { schema.removeAt(index); _customReportSchemas[unifiedTaskReportKey(row)] = schema; refresh(); }, icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'حذف الحقل'),
                              ]),
                              Align(alignment: Alignment.centerRight, child: Text('المفتاح: ${field['key']}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.black54))),
                              const SizedBox(height: 6),
                              Row(children: [
                                Expanded(child: DropdownButtonFormField<String>(value: const ['text', 'textarea', 'number', 'money', 'percentage', 'date', 'select', 'checkbox', 'rating', 'attachment', 'calculated'].contains(type) ? type : 'text', decoration: const InputDecoration(labelText: 'نوع الحقل', isDense: true), items: const [
                                  DropdownMenuItem(value: 'text', child: Text('نص')), DropdownMenuItem(value: 'textarea', child: Text('نص طويل')), DropdownMenuItem(value: 'number', child: Text('رقم')), DropdownMenuItem(value: 'money', child: Text('مبلغ')), DropdownMenuItem(value: 'percentage', child: Text('نسبة')), DropdownMenuItem(value: 'date', child: Text('تاريخ')), DropdownMenuItem(value: 'select', child: Text('قائمة')), DropdownMenuItem(value: 'checkbox', child: Text('اختيار')), DropdownMenuItem(value: 'rating', child: Text('تقييم')), DropdownMenuItem(value: 'attachment', child: Text('مرفق')), DropdownMenuItem(value: 'calculated', child: Text('محسوب')),
                                ], onChanged: (value) { if (value != null) { field['type'] = value; _customReportSchemas[schemaKey] = schema; refresh(); } })),
                                Checkbox(value: field['required'] == true, onChanged: (value) { field['required'] = value == true; _customReportSchemas[schemaKey] = schema; refresh(); }),
                                const Text('إلزامي'),
                              ]),
                              if (field['type'] == 'select')
                                TextFormField(initialValue: (field['options'] as List? ?? const []).join('، '), textAlign: TextAlign.right, decoration: const InputDecoration(labelText: 'خيارات القائمة (افصل بينها بفاصلة)', isDense: true), onChanged: (value) { field['options'] = value.split(RegExp(r'[,،]')).map((item) => item.trim()).where((item) => item.isNotEmpty).toList(); _customReportSchemas[schemaKey] = schema; }),
                              if (field['type'] == 'calculated')
                                TextFormField(
                                  initialValue: '${(field['config'] as Map?)?['formula'] ?? ''}',
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    labelText: 'قاعدة الحساب / المعادلة',
                                    hintText: '{collected_amount} - {outstanding_amount}',
                                    helperText: 'استخدم مفاتيح الحقول بين { } والعمليات + - * / والأقواس.',
                                    isDense: true,
                                  ),
                                  onChanged: (value) {
                                    field['config'] = {'formula': value.trim()};
                                    _customReportSchemas[schemaKey] = schema;
                                  },
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    OutlinedButton.icon(onPressed: schema.length >= 30 ? null : () { schema.add({'key': 'custom_field_${schema.length + 1}', 'label': 'حقل جديد', 'type': 'text', 'required': false}); _customReportSchemas[unifiedTaskReportKey(row)] = schema; refresh(); }, icon: const Icon(Icons.add), label: Text(schema.length >= 30 ? 'بلغ الحد الأعلى للحقول' : 'إضافة حقل')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(onPressed: () { _customReportSchemas[unifiedTaskReportKey(row)] = schema; Navigator.pop(dialogContext, {'saved': true}); widget.onChanged?.call(); }, child: const Text('حفظ التعديلات')),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) setState(() {});
  }

  void _previewSelectedReport() {
    final selected = _selectedReport;
    if (selected == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(selected.title, textAlign: TextAlign.right),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('الإصدار ${selected.versionNumber}', textAlign: TextAlign.right),
          Text('عدد الحقول: ${selected.fieldCount}', textAlign: TextAlign.right),
          Text('الحقول الإلزامية: ${selected.requiredFieldCount}', textAlign: TextAlign.right),
          const SizedBox(height: 12),
          const Text('سيعبئ الموظف هذا النموذج ويحفظ مسودته أو يرسله للإدارة. إعداد الحقول وترتيبها وإلزاميتها من اختصاص الإدارة فقط.', textAlign: TextAlign.right),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
      ),
    );
  }

  Widget _workHours() => _section(AppCustomizer.instance.unifiedLabel('hours'), Wrap(textDirection: TextDirection.rtl, spacing: 8, runSpacing: 8, children: [
    _drop('نوع الدوام', _workType, ['دوام كامل', 'دوام جزئي', 'مناوبة'], (v) => setState(() => _workType = v)),
    _drop('الأيام', _days, ['الأحد - الخميس', 'السبت - الخميس', 'حسب المناوبة'], (v) => setState(() => _days = v)),
    _drop('الاستثناء الأسبوعي', _exception, ['الجمعة', 'الأحد', 'لا يوجد'], (v) => setState(() => _exception = v)),
    _periodField(_firstPeriod, 'الفترة الأولى', const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 12, minute: 0)),
    _periodField(_breakPeriod, 'الاستراحة', const TimeOfDay(hour: 12, minute: 0), const TimeOfDay(hour: 13, minute: 0)),
    _periodField(_secondPeriod, 'الفترة الثانية', const TimeOfDay(hour: 13, minute: 0), const TimeOfDay(hour: 17, minute: 0)),
  ]));

  Widget _scheduleTable(String title, List<_UnifiedRow> source) {
    final visible = AppCustomizer.instance.unifiedScheduleColumns
        .where((key) => !{'time', 'task', 'output'}.contains(key) || AppCustomizer.instance.isUnifiedFieldVisible(key))
        .toList();
    return _section(
      title,
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          columns: [...visible.map((key) => DataColumn(label: Text(AppCustomizer.instance.unifiedLabel(key)))), const DataColumn(label: Text('إجراء'))],
          rows: source.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            return DataRow(cells: [
              for (final key in visible) DataCell(SizedBox(width: _scheduleFieldWidth(key), child: _scheduleField(key, row))),
              DataCell(Row(children: [
                IconButton(onPressed: () { widget.onChanged?.call(); setState(() => source.insert(i + 1, _UnifiedRow('', '', ''))); }, icon: const Icon(Icons.add, size: 19)),
                IconButton(onPressed: source.isEmpty ? null : () { widget.onChanged?.call(); final removed = source.removeAt(i); removed.dispose(); setState(() {}); }, icon: const Icon(Icons.delete_outline, size: 19)),
              ])),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _scheduleField(String key, _UnifiedRow row) {
    if (key == 'time') return _timeField(row.time, 'الوقت');
    return TextField(
      controller: key == 'task'
          ? row.task
          : key == 'output'
              ? row.output
              : row.custom(key),
      onChanged: (_) => widget.onChanged?.call(),
      textAlign: _textAlign(key),
      decoration: const InputDecoration(isDense: true),
    );
  }

  Widget _dateField() => TextField(
        controller: _startDate,
        readOnly: true,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: AppCustomizer.instance.unifiedLabel('startDate'),
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'اختيار التاريخ',
            onPressed: () { widget.onChanged?.call(); _pickStartDate(); },
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ),
        onTap: () { widget.onChanged?.call(); _pickStartDate(); },
      );

  Widget _timeField(TextEditingController controller, String label) => TextField(
        controller: controller,
        readOnly: true,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: const Icon(Icons.schedule_outlined, size: 19),
        ),
        onTap: () { widget.onChanged?.call(); _pickTime(controller); },
      );

  Widget _periodField(
    TextEditingController controller,
    String label,
    TimeOfDay defaultStart,
    TimeOfDay defaultEnd,
  ) => SizedBox(
        width: 155,
        child: TextField(
          controller: controller,
          readOnly: true,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: label,
            hintText: '08:00 - 12:00',
            isDense: true,
            suffixIcon: const Icon(Icons.access_time_outlined, size: 19),
          ),
          onTap: () { widget.onChanged?.call(); _pickPeriod(controller, label, defaultStart, defaultEnd); },
        ),
      );

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parseTime(String value, TimeOfDay fallback) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    final hour = int.tryParse(match?.group(1) ?? '');
    final minute = int.tryParse(match?.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) return fallback;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _pickStartDate() async {
    final initial = DateTime.tryParse(_startDate.text) ?? DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'اختر تاريخ بدء التطبيق',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (value != null && mounted) setState(() => _startDate.text = _formatDate(value));
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final value = await showTimePicker(
      context: context,
      initialTime: _parseTime(controller.text, TimeOfDay.now()),
      helpText: 'اختر الوقت',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (value != null && mounted) setState(() => controller.text = _formatTime(value));
  }

  Future<void> _pickPeriod(
    TextEditingController controller,
    String label,
    TimeOfDay defaultStart,
    TimeOfDay defaultEnd,
  ) async {
    final parts = controller.text.split('-').map((part) => part.trim()).toList();
    final start = await showTimePicker(
      context: context,
      initialTime: _parseTime(parts.isNotEmpty ? parts.first : '', defaultStart),
      helpText: 'اختر بداية $label',
      cancelText: 'إلغاء',
      confirmText: 'التالي',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: _parseTime(parts.length > 1 ? parts.last : '', defaultEnd),
      helpText: 'اختر نهاية $label',
      cancelText: 'إلغاء',
      confirmText: 'حفظ',
    );
    if (end != null && mounted) setState(() => controller.text = '${_formatTime(start)} - ${_formatTime(end)}');
  }
  TextAlign _textAlign(String key) {
    final align = '${AppCustomizer.instance.unifiedFieldLayout(key)['align'] ?? 'right'}';
    return align == 'left' ? TextAlign.left : align == 'center' ? TextAlign.center : TextAlign.right;
  }
  double _scheduleFieldWidth(String key) {
    final span = '${AppCustomizer.instance.unifiedFieldLayout(key)['span'] ?? 'half'}';
    return span == 'full' ? 300 : span == 'third' ? 110 : key == 'time' ? 150 : 220;
  }

  Widget _editableList(String title, List<TextEditingController> list) => _section(title, Column(children: [for (var i = 0; i < list.length; i++) Row(children: [Expanded(child: TextField(controller: list[i], onChanged: (_) => widget.onChanged?.call(), textAlign: TextAlign.right, decoration: InputDecoration(isDense: true, hintText: 'أضف بندًا'))), IconButton(onPressed: () { widget.onChanged?.call(); _removeTextRow(list, i); }, icon: const Icon(Icons.delete_outline))]), Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () { widget.onChanged?.call(); _addTextRow(list); }, icon: const Icon(Icons.add), label: const Text('إضافة بند')))]));

  Widget _kpiTable() => _section(
    'مؤشرات تقييم الأداء',
    Column(
      children: [
        for (var i = 0; i < _kpis.length; i++)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kpis[i][0],
                  onChanged: (_) => widget.onChanged?.call(),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'المؤشر', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _kpis[i][1],
                  onChanged: (_) => widget.onChanged?.call(),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'معيار الإنجاز / القياس', isDense: true),
                ),
              ),
              IconButton(
                onPressed: _kpis.length == 1
                    ? null
                    : () {
                        final row = _kpis.removeAt(i);
                        for (final controller in row) controller.dispose();
                        setState(() {});
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _kpis.add([TextEditingController(), TextEditingController()])),
            icon: const Icon(Icons.add),
            label: const Text('إضافة مؤشر'),
          ),
        ),
      ],
    ),
  );

  Widget _approvalStatus() => _section('حالة الاعتماد', const Wrap(textDirection: TextDirection.rtl, spacing: 8, children: [Chip(avatar: Icon(Icons.hourglass_empty, size: 17), label: Text('إقرار الموظف: بانتظار الإقرار')), Chip(avatar: Icon(Icons.rate_review_outlined, size: 17), label: Text('مراجعة المسؤول: لم تبدأ')), Chip(avatar: Icon(Icons.verified_outlined, size: 17), label: Text('اعتماد المدير: مسودة'))]));

  Widget _section(String title, Widget child) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF8FBFA), borderRadius: BorderRadius.circular(AppCustomizer.instance.unifiedRadius), border: Border.all(color: const Color(0xFFD8E4E0))), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(title, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy, fontSize: 14 * AppCustomizer.instance.unifiedFontScale)), const SizedBox(height: 8), child]));
  Widget _input(TextEditingController controller, String label) => TextField(controller: controller, onChanged: (_) => widget.onChanged?.call(), textAlign: TextAlign.right, decoration: InputDecoration(labelText: label, isDense: true));
  Widget _drop(String label, String value, List<String> values, ValueChanged<String> onChanged) => SizedBox(width: 155, child: DropdownButtonFormField<String>(value: value, isExpanded: true, decoration: InputDecoration(labelText: label, isDense: true), items: values.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) { if (v != null) { widget.onChanged?.call(); onChanged(v); } }));

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_sent) {
      messenger.showSnackBar(const SnackBar(content: Text('تم إرسال هذا الجدول مسبقًا. افتح شاشة الجدول من جديد لإرسال جدول مستقل.', textAlign: TextAlign.right)));
      return;
    }
    final tasks = _rows
        .where((row) => row.task.text.trim().isNotEmpty)
        .map((row) => UnifiedTaskRowData(
              time: row.time.text.trim(),
              task: row.task.text.trim(),
              output: row.output.text.trim(),
              extras: row.extras,
            ))
        .toList();
    final exceptionTasks = _exceptionRows
        .where((row) => row.task.text.trim().isNotEmpty)
        .map((row) => UnifiedTaskRowData(
              time: '${_exception}: ${row.time.text.trim()}',
              task: row.task.text.trim(),
              output: row.output.text.trim(),
              extras: row.extras,
            ))
        .toList();
    tasks.addAll(exceptionTasks);
    if (_employee.text.trim().isEmpty || _role.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('اختر الموظف واكتب المسمى الوظيفي قبل الإرسال.', textAlign: TextAlign.right)));
      return;
    }
    if (tasks.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('أضف مهمة زمنية واحدة على الأقل قبل الإرسال.', textAlign: TextAlign.right)));
      return;
    }
    final reportSchemasByTask = <String, List<Map<String, dynamic>>>{
      for (final row in tasks) unifiedTaskReportKey(row): _automaticSchemaFor(row),
    };
    setState(() => _sending = true);
    try {
      final draft = UnifiedTaskTableDraft(
        employee: _employee.text.trim(),
        employeeUserId: widget.employees
            .where((item) => item.name == _employee.text.trim())
            .map((item) => item.userId)
            .firstWhere((id) => id.isNotEmpty, orElse: () => ''),
        role: _role.text.trim(),
        branch: _branch.text.trim(),
        branchId: widget.branches
            .where((item) => item.name == _branch.text.trim())
            .map((item) => item.id)
            .where((id) => id.isNotEmpty)
            .cast<String?>()
            .firstWhere((id) => true, orElse: () => null),
        startDate: _startDate.text.trim(),
        purpose: _purpose.text.trim(),
        reportNotes: _reportNotes.text.trim(),
        rows: tasks,
        responsibilities: _responsibilities.map((v) => v.text.trim()).where((v) => v.isNotEmpty).toList(),
        authorities: _authorities.map((v) => v.text.trim()).where((v) => v.isNotEmpty).toList(),
        instructions: _instructions.map((v) => v.text.trim()).where((v) => v.isNotEmpty).toList(),
        workType: _workType,
        workDays: _days,
        weeklyException: _exception,
        firstPeriod: _firstPeriod.text.trim(),
        breakPeriod: _breakPeriod.text.trim(),
        secondPeriod: _secondPeriod.text.trim(),
        kpis: _kpis
            .where((row) => row.any((controller) => controller.text.trim().isNotEmpty))
            .map((row) => '${row[0].text.trim()}: ${row[1].text.trim()}')
            .toList(),
        reportTemplateId: _reportTemplateId,
        reportVersionId: _reportVersionId,
        reportSchemasByTask: reportSchemasByTask,
      );
      if (widget.onSave != null) {
        await widget.onSave!(draft);
      } else {
        await widget.onSend(draft);
      }
      if (mounted) setState(() => _sent = true);
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text('تم حفظ الجدول الموحد وإرساله للموظف بنجاح.', textAlign: TextAlign.right)));
    } catch (error) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('تعذر إرسال الجدول: $error', textAlign: TextAlign.right)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final reportTheme = await ReportPdfTheme.load();
      final regularFontData = await rootBundle.load(
        'assets/fonts/NotoSansArabic-Regular.ttf',
      );
      final boldFontData = await rootBundle.load(
        'assets/fonts/NotoSansArabic-Bold.ttf',
      );
      final font = pw.Font.ttf(regularFontData);
      final boldFont = pw.Font.ttf(boldFontData);
      final document = pw.Document(
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
      );
      final rows = [..._rows, ..._exceptionRows]
          .map((row) => [_pdfSafeText(row.time.text), _pdfSafeText(row.task.text), _pdfSafeText(row.output.text), 'جديدة'])
          .toList();
      final listSection = (String title, List<TextEditingController> values) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _pdfHeading(title),
          ...values.asMap().entries.map((entry) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text('${entry.key + 1}. ${entry.value.text.trim().isEmpty ? '—' : entry.value.text.trim()}', textDirection: pw.TextDirection.rtl),
          )),
          pw.SizedBox(height: 8),
        ],
      );
      final store = AppCustomizer.instance;
      final sections = <String, pw.Widget>{
        'employee': _pdfInfoTable(),
        'purpose': pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _pdfHeading(store.unifiedLabel('purpose')),
          pw.Text(_pdfSafeText(_purpose.text.trim().isEmpty ? 'لا يوجد' : _purpose.text), textDirection: pw.TextDirection.rtl),
        ]),
        'hours': pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _pdfHeading(store.unifiedLabel('hours')),
          pw.Text(_pdfSafeText('نوع الدوام: $_workType   -   الأيام: $_days   -   الفترة الأولى: ${_firstPeriod.text.trim().isEmpty ? 'لا يوجد' : _firstPeriod.text}   -   الاستراحة: ${_breakPeriod.text.trim().isEmpty ? 'لا يوجد' : _breakPeriod.text}   -   الفترة الثانية: ${_secondPeriod.text.trim().isEmpty ? 'لا يوجد' : _secondPeriod.text}   -   الاستثناء: $_exception'), textDirection: pw.TextDirection.rtl),
        ]),
        'daily': pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _pdfHeading(store.unifiedLabel('daily')),
          _pdfScheduleTable(rows),
        ]),
        'exception': pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _pdfHeading(store.unifiedLabel('exception')),
          _pdfScheduleTable([..._exceptionRows].map((row) => [_pdfSafeText(row.time.text), _pdfSafeText(row.task.text), _pdfSafeText(row.output.text), 'جديدة']).toList()),
        ]),
        'lists': pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          listSection('المسؤوليات الأساسية', _responsibilities),
          listSection('الصلاحيات وحدود المسؤولية', _authorities),
          listSection('التوصيات والتعليمات الإدارية', _instructions),
        ]),
        'kpi': pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _pdfHeading(store.unifiedLabel('kpi')),
          _pdfKpiTable(),
        ]),
        'report': pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _pdfHeading(store.unifiedLabel('report')),
          pw.Text(_pdfSafeText(_selectedReport == null ? 'لا يوجد' : '${_selectedReport!.title} - الإصدار ${_selectedReport!.versionNumber} - ${_selectedReport!.fieldCount} حقول (${_selectedReport!.requiredFieldCount} إلزامية)'), textDirection: pw.TextDirection.rtl),
        ]),
        'notes': pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _pdfHeading(store.unifiedLabel('notes')),
          pw.Text(_pdfSafeText(_reportNotes.text.trim().isEmpty ? 'لا يوجد' : _reportNotes.text), textDirection: pw.TextDirection.rtl),
        ]),
        'approval': pw.Table(
          border: reportTheme.tableBorder,
          children: [pw.TableRow(children: [
            _pdfCell('إقرار الموظف\nالاسم والتوقيع: يترك للتوقيع'),
            _pdfCell('مراجعة المسؤول المباشر\nالاسم والتوقيع: يترك للتوقيع'),
            _pdfCell('اعتماد المدير\nالاسم والتوقيع: يترك للتوقيع'),
          ])],
        ),
      };
      final orderedSections = store.unifiedSectionOrder
          .where(store.isUnifiedVisible)
          .where(sections.containsKey)
          .map((key) => sections[key]!)
          .toList();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
          build: (context) => [
            reportTheme.header('الجدول الموحد لإنشاء وتنفيذ المهام', employee: _employee.text, branch: _branch.text),
            pw.SizedBox(height: 12),
            for (final section in orderedSections) ...[
              section,
              pw.SizedBox(height: 12),
            ],
            reportTheme.footer(),
          ],
        ),
      );
      final bytes = await document.save();
      await Printing.sharePdf(bytes: bytes, filename: 'unified-task-table.pdf');
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر تصدير PDF: $error', textAlign: TextAlign.right)));
    }
  }

  pw.Widget _pdfHeading(String title) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 6),
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    color: PdfColor.fromHex('#EAF4F0'),
    child: pw.Text(_pdfSafeText(title), textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#123B5D'))),
  );

  pw.Widget _pdfInfoTable() {
    final store = AppCustomizer.instance;
    final fields = <String, String>{
      'employeeField': '${store.unifiedLabel('employeeField')}\n${_employee.text.trim().isEmpty ? '—' : _employee.text.trim()}',
      'roleField': '${store.unifiedLabel('roleField')}\n${_role.text.trim().isEmpty ? '—' : _role.text.trim()}',
      'branchField': '${store.unifiedLabel('branchField')}\n${_branch.text.trim().isEmpty ? '—' : _branch.text.trim()}',
      'startDate': '${store.unifiedLabel('startDate')}\n${_startDate.text.trim().isEmpty ? '—' : _startDate.text.trim()}',
    };
    final visible = fields.keys.where(store.isUnifiedFieldVisible).toList()
      ..sort((a, b) {
        final left = store.unifiedFieldLayout(a);
        final right = store.unifiedFieldLayout(b);
        final row = (left['row'] as int).compareTo(right['row'] as int);
        return row == 0 ? (left['column'] as int).compareTo(right['column'] as int) : row;
      });
    if (visible.isEmpty) return pw.SizedBox();
    final rows = <pw.TableRow>[];
    for (var index = 0; index < visible.length; index += 2) {
      final right = _pdfCell(fields[visible[index]]!);
      final left = index + 1 < visible.length ? _pdfCell(fields[visible[index + 1]]!) : _pdfCell('');
      rows.add(pw.TableRow(children: [right, left]));
    }
    return pw.Table(border: pw.TableBorder.all(color: PdfColor.fromHex('#B8CEC5')), children: rows);
  }

  pw.Widget _pdfScheduleTable(List<List<String>> rows) {
    final header = ['الحالة', 'المخرج المطلوب', 'المهمة والمسؤولية', 'الوقت'];
    final tableRows = <List<pw.Widget>>[
      header.map((value) => _pdfTableCell(value, bold: true)).toList(),
      ...rows.map(
        (row) => row.reversed.map((value) => _pdfTableCell(value)).toList(),
      ),
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColor.fromHex('#B8CEC5')),
      children: tableRows
          .asMap()
          .entries
          .map(
            (entry) => pw.TableRow(
              decoration: entry.key == 0
                  ? pw.BoxDecoration(color: PdfColor.fromHex('#EAF4F0'))
                  : null,
              children: entry.value,
            ),
          )
          .toList(),
    );
  }

  pw.Widget _pdfKpiTable() {
    final rows = <List<pw.Widget>>[
      [
        _pdfTableCell('معيار الإنجاز / القياس', bold: true),
        _pdfTableCell('المؤشر', bold: true),
      ],
      ..._kpis.map(
        (row) => [
          _pdfTableCell(row[1].text.trim().isEmpty ? '—' : row[1].text.trim()),
          _pdfTableCell(row[0].text.trim().isEmpty ? '—' : row[0].text.trim()),
        ],
      ),
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColor.fromHex('#B8CEC5')),
      children: rows
          .asMap()
          .entries
          .map(
            (entry) => pw.TableRow(
              decoration: entry.key == 0
                  ? pw.BoxDecoration(color: PdfColor.fromHex('#EAF4F0'))
                  : null,
              children: entry.value,
            ),
          )
          .toList(),
    );
  }

  pw.Widget _pdfTableCell(String value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      _pdfSafeText(value.trim().isEmpty ? 'لا يوجد' : value),
      textDirection: pw.TextDirection.rtl,
      textAlign: pw.TextAlign.right,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  pw.Widget _pdfCell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.all(8),
    child: pw.Text(_pdfSafeText(text), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right),
  );

  String _pdfSafeText(String value) {
    final cleaned = value.replaceAllMapped(
      RegExp(r'[^\x20-\x7E\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u200C\u200D\n\r\t]'),
      (_) => ' ',
    );
    return cleaned.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }
}

class _UnifiedRow {
  _UnifiedRow(String time, String task, String output, [Map<String, String>? extras])
      : time = TextEditingController(text: time),
        task = TextEditingController(text: task),
        output = TextEditingController(text: output),
        _extras = (extras ?? {}).map((key, value) => MapEntry(key, TextEditingController(text: value)));
  final TextEditingController time, task, output;
  final Map<String, TextEditingController> _extras;
  TextEditingController custom(String key) => _extras.putIfAbsent(key, () => TextEditingController());
  Map<String, String> get extras => _extras.map((key, value) => MapEntry(key, value.text));
  void dispose() { time.dispose(); task.dispose(); output.dispose(); for (final controller in _extras.values) controller.dispose(); }
}

class UnifiedTaskTableDraft {
  const UnifiedTaskTableDraft({
    required this.employee,
    required this.employeeUserId,
    required this.role,
    required this.branch,
    required this.branchId,
    required this.startDate,
    required this.purpose,
    required this.reportNotes,
    required this.rows,
    required this.responsibilities,
    required this.authorities,
    required this.instructions,
    required this.workType,
    required this.workDays,
    required this.weeklyException,
    required this.firstPeriod,
    required this.breakPeriod,
    required this.secondPeriod,
    required this.kpis,
    required this.reportSchemasByTask,
    this.reportTemplateId,
    this.reportVersionId,
  });
  final String employee, employeeUserId, role, branch, startDate, purpose, reportNotes;
  final String? branchId;
  final String workType, workDays, weeklyException, firstPeriod, breakPeriod, secondPeriod;
  final List<UnifiedTaskRowData> rows;
  final List<String> responsibilities, authorities, instructions, kpis;
  final Map<String, List<Map<String, dynamic>>> reportSchemasByTask;
  final String? reportTemplateId, reportVersionId;
}

class UnifiedTaskRowData {
  const UnifiedTaskRowData({required this.time, required this.task, required this.output, this.extras = const {}});
  final String time, task, output;
  final Map<String, String> extras;
}

String unifiedTaskReportKey(UnifiedTaskRowData row) => [
      row.time,
      row.task,
      row.output,
      ...row.extras.entries.map((entry) => '${entry.key}=${entry.value}'),
    ].join('|');

class UnifiedEmployeeOption {
  const UnifiedEmployeeOption({required this.name, required this.userId});
  final String name, userId;
}

class UnifiedBranchOption {
  const UnifiedBranchOption({required this.id, required this.name});
  final String id;
  final String name;
}

class UnifiedReportOption {
  const UnifiedReportOption({required this.templateId, required this.versionId, required this.title, required this.roleCode, required this.versionNumber, required this.fieldCount, required this.requiredFieldCount});
  final String templateId, versionId, title, roleCode, versionNumber;
  final int fieldCount, requiredFieldCount;
}
