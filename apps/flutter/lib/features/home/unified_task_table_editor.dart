import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme.dart';

class UnifiedTaskTableEditor extends StatefulWidget {
  const UnifiedTaskTableEditor({super.key, required this.onSend, this.employees = const [], this.branches = const [], this.reports = const []});
  final Future<void> Function(UnifiedTaskTableDraft draft) onSend;
  final List<UnifiedEmployeeOption> employees;
  final List<String> branches;
  final List<UnifiedReportOption> reports;

  @override
  State<UnifiedTaskTableEditor> createState() => _UnifiedTaskTableEditorState();
}

class _UnifiedTaskTableEditorState extends State<UnifiedTaskTableEditor> {
  final _purpose = TextEditingController();
  final _dailyReport = TextEditingController();
  final _employee = TextEditingController();
  final _role = TextEditingController();
  final _branch = TextEditingController();
  final _startDate = TextEditingController();
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
  String _template = 'فارغ';
  String _workType = 'دوام كامل';
  String _days = 'الأحد - الخميس';
  String _exception = 'الجمعة';
  String? _reportVersionId;
  String? _reportTemplateId;

  @override
  void dispose() {
    _purpose.dispose();
    _dailyReport.dispose();
    _employee.dispose();
    _role.dispose();
    _branch.dispose();
    _startDate.dispose();
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

  void _loadTemplate(String value) {
    setState(() {
      _template = value;
      final title = value == 'فارغ' ? '' : 'تنفيذ مهام $value';
      _purpose.text = title.isEmpty ? '' : 'تنظيم ومتابعة أعمال $value وفق خطة يومية واضحة.';
      _rows
        ..clear()
        ..addAll(value == 'فارغ'
            ? [_UnifiedRow('08:00', '', '')]
            : [
                _UnifiedRow('08:00', 'مراجعة خطة العمل اليومية', 'خطة تنفيذ معتمدة'),
                _UnifiedRow('10:00', 'تنفيذ البنود الأساسية للدور', 'مخرجات موثقة'),
                _UnifiedRow('14:00', 'تحديث الحالة وتجهيز التقرير اليومي', 'تقرير يومي'),
              ]);
    });
  }

  void _addTextRow(List<TextEditingController> list) =>
      setState(() => list.add(TextEditingController()));

  void _removeTextRow(List<TextEditingController> list, int index) {
    if (list.length == 1) return;
    final controller = list.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFD8E4E0)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              const Icon(Icons.table_chart_outlined, color: AppColors.green),
              const SizedBox(width: 8),
              const Expanded(child: Text('الجدول الموحد لإنشاء المهام', textAlign: TextAlign.right, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy))),
              IconButton(onPressed: () => setState(() => _expanded = !_expanded), icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more), tooltip: _expanded ? 'طي التفاصيل' : 'إظهار التفاصيل'),
            ],
          ),
          if (_expanded) ...[
            const Divider(height: 16),
            _toolbar(),
            const SizedBox(height: 12),
            _employeeCard(),
            const SizedBox(height: 10),
            _section('الهدف من الوظيفة', TextField(controller: _purpose, textAlign: TextAlign.right, maxLines: 2, decoration: const InputDecoration(hintText: 'اكتب الهدف العام من الوظيفة'))),
            const SizedBox(height: 10),
            _workHours(),
            const SizedBox(height: 10),
            _scheduleTable('الجدول الزمني اليومي', _rows),
            const SizedBox(height: 10),
            _scheduleTable('العمل الاستثنائي ($_exception)', _exceptionRows),
            const SizedBox(height: 10),
            _reportSelector(),
            const SizedBox(height: 10),
            _editableList('المسؤوليات الأساسية', _responsibilities),
            const SizedBox(height: 10),
            _editableList('الصلاحيات وحدود المسؤولية', _authorities),
            const SizedBox(height: 10),
            _editableList('التوصيات والتعليمات الإدارية', _instructions),
            const SizedBox(height: 10),
            _kpiTable(),
            const SizedBox(height: 10),
            _section('التقرير اليومي المطلوب', TextField(controller: _dailyReport, textAlign: TextAlign.right, maxLines: 3, decoration: const InputDecoration(hintText: 'حدد البنود التي يرفعها الموظف في نهاية الدوام'))),
            const SizedBox(height: 12),
            _approvalStatus(),
            const SizedBox(height: 12),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(child: FilledButton.icon(onPressed: _sending ? null : _submit, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined), label: Text(_sending ? 'جارٍ الإرسال...' : 'حفظ الجدول وإرساله'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('تصدير PDF'))),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _toolbar() => Wrap(
    textDirection: TextDirection.rtl,
    spacing: 7,
    runSpacing: 7,
    children: [
      SizedBox(width: 190, child: DropdownButtonFormField<String>(value: _template, decoration: const InputDecoration(labelText: 'تحميل من قالب جاهز'), items: const ['فارغ', 'محاسب', 'أمين مخزن', 'عامل تحميل وترتيب', 'مبيعات وحسابات', 'مهام مشتركة'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) { if (value != null) _loadTemplate(value); })),
      OutlinedButton.icon(onPressed: () => _loadTemplate(_template == 'فارغ' ? 'مهام مشتركة' : 'فارغ'), icon: const Icon(Icons.content_copy_outlined), label: const Text('نسخ من موظف سابق')),
      IconButton(onPressed: () => setState(() => _rows.add(_UnifiedRow('', '', ''))), icon: const Icon(Icons.add_box_outlined), tooltip: 'إضافة صف يومي'),
      IconButton(onPressed: () => setState(() => _exceptionRows.add(_UnifiedRow('', '', ''))), icon: const Icon(Icons.event_available_outlined), tooltip: 'إضافة صف استثنائي'),
    ],
  );

  Widget _employeeCard() => _section('بيانات الموظف والاعتماد', Column(children: [
    Row(children: [Expanded(child: _employeeField()), const SizedBox(width: 8), Expanded(child: _roleField())]),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: _branchField()), const SizedBox(width: 8), Expanded(child: _input(_startDate, 'تاريخ بدء التطبيق'))]),
  ]));

  Widget _employeeField() => widget.employees.isEmpty
      ? _input(_employee, 'الموظف أو مهام مشتركة')
      : DropdownButtonFormField<String>(
          value: widget.employees.any((item) => item.name == _employee.text) ? _employee.text : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'الموظف أو المجموعة', isDense: true),
          items: widget.employees.map((item) => DropdownMenuItem(value: item.name, child: Text(item.name, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (value) => setState(() => _employee.text = value ?? ''),
        );

  Widget _roleField() => DropdownButtonFormField<String>(
    value: const ['المحاسب', 'أمين مخزن', 'عامل تحميل', 'المدير التنفيذي', 'صاحب المؤسسة'].contains(_role.text) ? _role.text : null,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'المسمى الوظيفي', isDense: true),
    items: const ['المحاسب', 'أمين مخزن', 'عامل تحميل', 'المدير التنفيذي', 'صاحب المؤسسة'].map((value) => DropdownMenuItem(value: value, child: Text(value, overflow: TextOverflow.ellipsis))).toList(),
    onChanged: (value) => setState(() => _role.text = value ?? ''),
  );

  Widget _branchField() => widget.branches.isEmpty
      ? _input(_branch, 'الفرع')
      : DropdownButtonFormField<String>(
          value: widget.branches.contains(_branch.text) ? _branch.text : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'الفرع', isDense: true),
          items: widget.branches.map((value) => DropdownMenuItem(value: value, child: Text(value, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (value) => setState(() => _branch.text = value ?? ''),
        );

  Widget _reportSelector() => _section('قالب التقرير اليومي', widget.reports.isEmpty
      ? const Text('لا توجد قوالب تقارير معتمدة متاحة لهذا الحساب.', textAlign: TextAlign.right)
      : DropdownButtonFormField<String>(
          value: widget.reports.any((item) => item.versionId == _reportVersionId) ? _reportVersionId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'اختر قالب التقرير المعتمد', isDense: true),
          items: widget.reports.map((item) => DropdownMenuItem(value: item.versionId, child: Text(item.title, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (value) {
            final item = widget.reports.firstWhere((item) => item.versionId == value);
            setState(() { _reportVersionId = value; _reportTemplateId = item.templateId; });
          },
        ));

  Widget _workHours() => _section('ساعات الدوام الرسمية', Wrap(textDirection: TextDirection.rtl, spacing: 8, runSpacing: 8, children: [
    _drop('نوع الدوام', _workType, ['دوام كامل', 'دوام جزئي', 'مناوبة'], (v) => setState(() => _workType = v)),
    _drop('الأيام', _days, ['الأحد - الخميس', 'السبت - الخميس', 'حسب المناوبة'], (v) => setState(() => _days = v)),
    _drop('الاستثناء الأسبوعي', _exception, ['الجمعة', 'الأحد', 'لا يوجد'], (v) => setState(() => _exception = v)),
    const SizedBox(width: 110, child: TextField(textAlign: TextAlign.center, decoration: InputDecoration(labelText: 'الفترة الأولى', hintText: '08:00 - 12:00'))),
    const SizedBox(width: 110, child: TextField(textAlign: TextAlign.center, decoration: InputDecoration(labelText: 'الاستراحة', hintText: '12:00 - 13:00'))),
    const SizedBox(width: 110, child: TextField(textAlign: TextAlign.center, decoration: InputDecoration(labelText: 'الفترة الثانية', hintText: '13:00 - 17:00'))),
  ]));

  Widget _scheduleTable(String title, List<_UnifiedRow> source) {
    return _section(
      title,
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          columns: const [
            DataColumn(label: Text('الوقت')),
            DataColumn(label: Text('المهمة المحددة والمسؤولية')),
            DataColumn(label: Text('المخرج المطلوب')),
            DataColumn(label: Text('إجراء')),
          ],
          rows: source.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            return DataRow(cells: [
              DataCell(SizedBox(width: 75, child: TextField(controller: row.time, textAlign: TextAlign.right, decoration: const InputDecoration(isDense: true)))),
              DataCell(SizedBox(width: 220, child: TextField(controller: row.task, textAlign: TextAlign.right, decoration: const InputDecoration(isDense: true)))),
              DataCell(SizedBox(width: 180, child: TextField(controller: row.output, textAlign: TextAlign.right, decoration: const InputDecoration(isDense: true)))),
              DataCell(Row(children: [
                IconButton(onPressed: () => setState(() => source.insert(i + 1, _UnifiedRow('', '', ''))), icon: const Icon(Icons.add, size: 19)),
                IconButton(onPressed: source.isEmpty ? null : () { final removed = source.removeAt(i); removed.dispose(); setState(() {}); }, icon: const Icon(Icons.delete_outline, size: 19)),
              ])),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _editableList(String title, List<TextEditingController> list) => _section(title, Column(children: [for (var i = 0; i < list.length; i++) Row(children: [Expanded(child: TextField(controller: list[i], textAlign: TextAlign.right, decoration: InputDecoration(isDense: true, hintText: 'أضف بندًا'))), IconButton(onPressed: () => _removeTextRow(list, i), icon: const Icon(Icons.delete_outline))]), Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _addTextRow(list), icon: const Icon(Icons.add), label: const Text('إضافة بند')))]));

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
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'المؤشر', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _kpis[i][1],
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

  Widget _section(String title, Widget child) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF8FBFA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFD8E4E0))), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(title, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 8), child]));
  Widget _input(TextEditingController controller, String label) => TextField(controller: controller, textAlign: TextAlign.right, decoration: InputDecoration(labelText: label, isDense: true));
  Widget _drop(String label, String value, List<String> values, ValueChanged<String> onChanged) => SizedBox(width: 155, child: DropdownButtonFormField<String>(value: value, isExpanded: true, decoration: InputDecoration(labelText: label, isDense: true), items: values.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) { if (v != null) onChanged(v); }));

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final tasks = _rows
        .where((row) => row.task.text.trim().isNotEmpty)
        .map((row) => UnifiedTaskRowData(
              time: row.time.text.trim(),
              task: row.task.text.trim(),
              output: row.output.text.trim(),
            ))
        .toList();
    final exceptionTasks = _exceptionRows
        .where((row) => row.task.text.trim().isNotEmpty)
        .map((row) => UnifiedTaskRowData(
              time: '${_exception}: ${row.time.text.trim()}',
              task: row.task.text.trim(),
              output: row.output.text.trim(),
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
    if (_dailyReport.text.trim().isNotEmpty && _reportVersionId == null) {
      messenger.showSnackBar(const SnackBar(content: Text('لا يمكن إرسال التقرير اليومي دون قالب تقرير معتمد متاح ومختار.', textAlign: TextAlign.right)));
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(UnifiedTaskTableDraft(
        employee: _employee.text.trim(),
        role: _role.text.trim(),
        branch: _branch.text.trim(),
        startDate: _startDate.text.trim(),
        purpose: _purpose.text.trim(),
        dailyReport: _dailyReport.text.trim(),
        rows: tasks,
        responsibilities: _responsibilities.map((v) => v.text.trim()).where((v) => v.isNotEmpty).toList(),
        authorities: _authorities.map((v) => v.text.trim()).where((v) => v.isNotEmpty).toList(),
        instructions: _instructions.map((v) => v.text.trim()).where((v) => v.isNotEmpty).toList(),
        workType: _workType,
        workDays: _days,
        weeklyException: _exception,
        kpis: _kpis
            .where((row) => row.any((controller) => controller.text.trim().isNotEmpty))
            .map((row) => '${row[0].text.trim()}: ${row[1].text.trim()}')
            .toList(),
        reportTemplateId: _reportTemplateId,
        reportVersionId: _reportVersionId,
      ));
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text('تم إنشاء المهام وإرسالها للموظف بنجاح.', textAlign: TextAlign.right)));
    } catch (error) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('تعذر إرسال الجدول: $error', textAlign: TextAlign.right)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fontData = await rootBundle.load('assets/fonts/AlshaeriArabic-Regular.ttf');
      final font = pw.Font.ttf(fontData);
      final document = pw.Document(
        theme: pw.ThemeData.withFont(base: font, bold: font),
      );
      final rows = _rows
          .map((row) => [row.time.text.trim(), row.task.text.trim(), row.output.text.trim(), 'جديدة'])
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
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
          build: (context) => [
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#EAF4F0'),
                border: pw.Border.all(color: PdfColor.fromHex('#B8CEC5')),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(children: [
                pw.Text('مؤسسة الشاعري للتجارة العامة', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#123B5D'))),
                pw.SizedBox(height: 4),
                pw.Text('الجدول الموحد لإنشاء وتنفيذ المهام', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
            pw.SizedBox(height: 12),
            _pdfInfoTable(),
            pw.SizedBox(height: 12),
            _pdfHeading('الهدف من الوظيفة'),
            pw.Text(_purpose.text.trim().isEmpty ? '—' : _purpose.text.trim(), textDirection: pw.TextDirection.rtl),
            pw.SizedBox(height: 10),
            _pdfHeading('ساعات الدوام والاستثناء الأسبوعي'),
            pw.Text('نوع الدوام: $_workType   |   الأيام: $_days   |   الاستثناء: $_exception', textDirection: pw.TextDirection.rtl),
            pw.SizedBox(height: 12),
            _pdfHeading('الجدول الزمني اليومي'),
            _pdfScheduleTable(rows),
            pw.SizedBox(height: 12),
            listSection('المسؤوليات الأساسية', _responsibilities),
            listSection('الصلاحيات وحدود المسؤولية', _authorities),
            listSection('التوصيات والتعليمات الإدارية', _instructions),
            _pdfHeading('مؤشرات تقييم الأداء'),
            _pdfKpiTable(),
            pw.SizedBox(height: 12),
            _pdfHeading('التقرير اليومي المطلوب'),
            pw.Text(_dailyReport.text.trim().isEmpty ? '—' : _dailyReport.text.trim(), textDirection: pw.TextDirection.rtl),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromHex('#B8CEC5')),
              children: [pw.TableRow(children: [
                _pdfCell('إقرار الموظف\nالاسم والتوقيع: __________________'),
                _pdfCell('مراجعة المسؤول المباشر\nالاسم والتوقيع: __________________'),
                _pdfCell('اعتماد المدير\nالاسم والتوقيع: __________________'),
              ])],
            ),
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
    child: pw.Text(title, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#123B5D'))),
  );

  pw.Widget _pdfInfoTable() => pw.Table(
    border: pw.TableBorder.all(color: PdfColor.fromHex('#B8CEC5')),
    children: [
      pw.TableRow(children: [_pdfCell('الموظف / المجموعة\n${_employee.text.trim().isEmpty ? '—' : _employee.text.trim()}'), _pdfCell('المسمى الوظيفي\n${_role.text.trim().isEmpty ? '—' : _role.text.trim()}')]),
      pw.TableRow(children: [_pdfCell('الفرع\n${_branch.text.trim().isEmpty ? '—' : _branch.text.trim()}'), _pdfCell('تاريخ بدء التطبيق\n${_startDate.text.trim().isEmpty ? '—' : _startDate.text.trim()}')]),
    ],
  );

  pw.Widget _pdfScheduleTable(List<List<String>> rows) => pw.Table.fromTextArray(
    headers: const ['الحالة', 'المخرج المطلوب', 'المهمة والمسؤولية', 'الوقت'],
    data: rows.map((row) => row.reversed.toList()).toList(),
    border: pw.TableBorder.all(color: PdfColor.fromHex('#B8CEC5')),
    headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#EAF4F0')),
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellAlignment: pw.Alignment.centerRight,
    headerAlignment: pw.Alignment.centerRight,
  );

  pw.Widget _pdfKpiTable() => pw.Table.fromTextArray(
    headers: const ['معيار الإنجاز / القياس', 'المؤشر'],
    data: _kpis.map((row) => [row[1].text.trim(), row[0].text.trim()]).toList(),
    border: pw.TableBorder.all(color: PdfColor.fromHex('#B8CEC5')),
    headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#EAF4F0')),
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    cellAlignment: pw.Alignment.centerRight,
    headerAlignment: pw.Alignment.centerRight,
  );

  pw.Widget _pdfCell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.all(8),
    child: pw.Text(text, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right),
  );
}

class _UnifiedRow {
  _UnifiedRow(String time, String task, String output) : time = TextEditingController(text: time), task = TextEditingController(text: task), output = TextEditingController(text: output);
  final TextEditingController time, task, output;
  void dispose() { time.dispose(); task.dispose(); output.dispose(); }
}

class UnifiedTaskTableDraft {
  const UnifiedTaskTableDraft({
    required this.employee,
    required this.role,
    required this.branch,
    required this.startDate,
    required this.purpose,
    required this.dailyReport,
    required this.rows,
    required this.responsibilities,
    required this.authorities,
    required this.instructions,
    required this.workType,
    required this.workDays,
    required this.weeklyException,
    required this.kpis,
    this.reportTemplateId,
    this.reportVersionId,
  });
  final String employee, role, branch, startDate, purpose, dailyReport;
  final String workType, workDays, weeklyException;
  final List<UnifiedTaskRowData> rows;
  final List<String> responsibilities, authorities, instructions, kpis;
  final String? reportTemplateId, reportVersionId;
}

class UnifiedTaskRowData {
  const UnifiedTaskRowData({required this.time, required this.task, required this.output});
  final String time, task, output;
}

class UnifiedEmployeeOption {
  const UnifiedEmployeeOption({required this.name, required this.userId});
  final String name, userId;
}

class UnifiedReportOption {
  const UnifiedReportOption({required this.templateId, required this.versionId, required this.title});
  final String templateId, versionId, title;
}
