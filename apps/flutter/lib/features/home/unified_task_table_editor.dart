import 'package:flutter/material.dart';

import '../../core/theme.dart';

class UnifiedTaskTableEditor extends StatefulWidget {
  const UnifiedTaskTableEditor({super.key, required this.onSend});
  final VoidCallback onSend;

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
  bool _expanded = true;
  String _template = 'فارغ';
  String _workType = 'دوام كامل';
  String _days = 'الأحد - الخميس';
  String _exception = 'الجمعة';

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
            _scheduleTable('الجدول الزمني اليومي'),
            const SizedBox(height: 10),
            _scheduleTable('العمل الاستثنائي ($_exception)'),
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
            FilledButton.icon(onPressed: widget.onSend, icon: const Icon(Icons.send_outlined), label: const Text('حفظ الجدول وإرساله للموظف')),
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
      IconButton(onPressed: () => setState(() => _rows.add(_UnifiedRow('', '', ''))), icon: const Icon(Icons.add_box_outlined), tooltip: 'إضافة صف'),
    ],
  );

  Widget _employeeCard() => _section('بيانات الموظف والاعتماد', Column(children: [
    Row(children: [Expanded(child: _input(_employee, 'الموظف أو مهام مشتركة')), const SizedBox(width: 8), Expanded(child: _input(_role, 'المسمى الوظيفي'))]),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: _input(_branch, 'الفرع')), const SizedBox(width: 8), Expanded(child: _input(_startDate, 'تاريخ بدء التطبيق'))]),
  ]));

  Widget _workHours() => _section('ساعات الدوام الرسمية', Wrap(textDirection: TextDirection.rtl, spacing: 8, runSpacing: 8, children: [
    _drop('نوع الدوام', _workType, ['دوام كامل', 'دوام جزئي', 'مناوبة'], (v) => setState(() => _workType = v)),
    _drop('الأيام', _days, ['الأحد - الخميس', 'السبت - الخميس', 'حسب المناوبة'], (v) => setState(() => _days = v)),
    _drop('الاستثناء الأسبوعي', _exception, ['الجمعة', 'الأحد', 'لا يوجد'], (v) => setState(() => _exception = v)),
    const SizedBox(width: 110, child: TextField(textAlign: TextAlign.center, decoration: InputDecoration(labelText: 'الفترة الأولى', hintText: '08:00 - 12:00'))),
    const SizedBox(width: 110, child: TextField(textAlign: TextAlign.center, decoration: InputDecoration(labelText: 'الاستراحة', hintText: '12:00 - 13:00'))),
    const SizedBox(width: 110, child: TextField(textAlign: TextAlign.center, decoration: InputDecoration(labelText: 'الفترة الثانية', hintText: '13:00 - 17:00'))),
  ]));

  Widget _scheduleTable(String title) => _section(title, SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columnSpacing: 18, columns: const [DataColumn(label: Text('الوقت')), DataColumn(label: Text('المهمة المحددة والمسؤولية')), DataColumn(label: Text('المخرج المطلوب')), DataColumn(label: Text('إجراء'))], rows: _rows.asMap().entries.map((entry) { final i = entry.key; final row = entry.value; return DataRow(cells: [DataCell(SizedBox(width: 75, child: TextField(controller: row.time, textAlign: TextAlign.right, decoration: const InputDecoration(isDense: true)))), DataCell(SizedBox(width: 220, child: TextField(controller: row.task, textAlign: TextAlign.right, decoration: const InputDecoration(isDense: true)))), DataCell(SizedBox(width: 180, child: TextField(controller: row.output, textAlign: TextAlign.right, decoration: const InputDecoration(isDense: true)))), DataCell(Row(children: [IconButton(onPressed: () => setState(() => _rows.insert(i + 1, _UnifiedRow('', '', ''))), icon: const Icon(Icons.add, size: 19)), IconButton(onPressed: _rows.length == 1 ? null : () { final removed = _rows.removeAt(i); removed.dispose(); setState(() {}); }, icon: const Icon(Icons.delete_outline, size: 19))]))]); }).toList()));

  Widget _editableList(String title, List<TextEditingController> list) => _section(title, Column(children: [for (var i = 0; i < list.length; i++) Row(children: [Expanded(child: TextField(controller: list[i], textAlign: TextAlign.right, decoration: InputDecoration(isDense: true, hintText: 'أضف بندًا'))), IconButton(onPressed: () => _removeTextRow(list, i), icon: const Icon(Icons.delete_outline))]), Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _addTextRow(list), icon: const Icon(Icons.add), label: const Text('إضافة بند')))]));

  Widget _kpiTable() => _section('مؤشرات تقييم الأداء', Column(children: [for (var i = 0; i < _kpis.length; i++) Row(children: [Expanded(child: TextField(controller: _kpis[i][0], textAlign: TextAlign.right, decoration: const InputDecoration(labelText: 'المؤشر', isDense: true))), const SizedBox(width: 8), Expanded(child: TextField(controller: _kpis[i][1], textAlign: TextAlign.right, decoration: const InputDecoration(labelText: 'معيار الإنجاز / القياس', isDense: true))), IconButton(onPressed: _kpis.length == 1 ? null : () { final row = _kpis.removeAt(i); for (final c in row) c.dispose(); setState(() {}); }, icon: const Icon(Icons.delete_outline))]), Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => setState(() => _kpis.add([TextEditingController(), TextEditingController()])), icon: const Icon(Icons.add), label: const Text('إضافة مؤشر'))]));

  Widget _approvalStatus() => _section('حالة الاعتماد', const Wrap(textDirection: TextDirection.rtl, spacing: 8, children: [Chip(avatar: Icon(Icons.hourglass_empty, size: 17), label: Text('إقرار الموظف: بانتظار الإقرار')), Chip(avatar: Icon(Icons.rate_review_outlined, size: 17), label: Text('مراجعة المسؤول: لم تبدأ')), Chip(avatar: Icon(Icons.verified_outlined, size: 17), label: Text('اعتماد المدير: مسودة'))]));

  Widget _section(String title, Widget child) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF8FBFA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFD8E4E0))), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(title, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 8), child]));
  Widget _input(TextEditingController controller, String label) => TextField(controller: controller, textAlign: TextAlign.right, decoration: InputDecoration(labelText: label, isDense: true));
  Widget _drop(String label, String value, List<String> values, ValueChanged<String> onChanged) => SizedBox(width: 155, child: DropdownButtonFormField<String>(value: value, isExpanded: true, decoration: InputDecoration(labelText: label, isDense: true), items: values.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) { if (v != null) onChanged(v); }));
}

class _UnifiedRow {
  _UnifiedRow(String time, String task, String output) : time = TextEditingController(text: time), task = TextEditingController(text: task), output = TextEditingController(text: output);
  final TextEditingController time, task, output;
  void dispose() { time.dispose(); task.dispose(); output.dispose(); }
}
