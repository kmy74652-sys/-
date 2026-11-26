import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_customizer.dart';
import '../../shared/app_shell.dart';
import '../../shared/ui_labels.dart';

class AppCustomizerScreen extends StatefulWidget {
  const AppCustomizerScreen({super.key});
  @override
  State<AppCustomizerScreen> createState() => _AppCustomizerScreenState();
}

class _AppCustomizerScreenState extends State<AppCustomizerScreen>
    with SingleTickerProviderStateMixin {
  final _store = AppCustomizer.instance;
  bool _loading = true;
  bool _allowed = false;
  String _previewDevice = 'phone';
  bool _previewLandscape = false;
  bool _tasksLoading = true;
  List<Map<String, dynamic>> _currentTasks = const [];
  late final TabController _tabs;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    await _store.load();
    await _loadCurrentTasks();
    try {
      final profile = await const _ProfileLoader().load();
      _allowed = profile;
    } catch (_) {
      _allowed = false;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCurrentTasks() async {
    try {
      final raw = await Supabase.instance.client.rpc('mobile_my_profile');
      final employee = raw is Map ? raw['employee'] : null;
      final organizationId = employee is Map
          ? (employee['institutionId'] ?? employee['institution_id'] ?? employee['organization_id'])?.toString()
          : null;
      if (organizationId == null || organizationId.isEmpty) return;
      final rows = await Supabase.instance.client
          .from('tasks')
          .select('id,title,status,priority,due_at,assigned_to')
          .eq('organization_id', organizationId)
          .isFilter('deleted_at', null)
          .order('due_at')
          .limit(8);
      if (mounted) {
        setState(() => _currentTasks = rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList());
      }
    } catch (_) {
      // The preview remains usable when current task data is unavailable.
    } finally {
      if (mounted) setState(() => _tasksLoading = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final controller in _controllers.values) controller.dispose();
    super.dispose();
  }

  TextEditingController _controller(String key) => _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: _store.label(key)),
      );

  TextEditingController _unifiedController(String key) => _controllers.putIfAbsent(
        'unified:$key',
        () => TextEditingController(text: _store.unifiedLabel(key)),
      );

  @override
  Widget build(BuildContext context) => AppShell(
        title: 'مصمم الواجهات والتحكم الشامل',
        subtitle: 'تخصيص التطبيق متاح لصلاحيات المدير فقط',
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !_allowed
                ? const Center(child: Text('هذا القسم متاح للمدير فقط.'))
                    : Column(
                        children: [
                      Material(
                        color: Colors.white,
                        child: TabBar(
                          controller: _tabs,
                          isScrollable: true,
                          tabs: const [
                            Tab(text: 'معاينة الرئيسية'),
                            Tab(text: 'التسميات'),
                            Tab(text: 'الترتيب والإظهار'),
                            Tab(text: 'المظهر والألوان'),
                            Tab(text: 'تخصيص الجدول الموحد'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          children: [
                            _homePreviewTab(),
                            _labelsTab(),
                            _layoutTab(),
                            _themeTab(),
                            _unifiedTableTab(),
                          ],
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _save,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('حفظ وتطبيق التغييرات'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      );

  Widget _homePreviewTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _intro('تخصيص الصفحة الرئيسية من المعاينة', 'عدّل العناوين والتفاصيل مباشرة داخل البطاقات، واختر ألوان الصفحة وخلفيتها وشكل البطاقات من نفس المعاينة.'),
          _homePreviewCanvas(),
          const SizedBox(height: 12),
          SectionCard(
            title: 'المظهر العام',
            child: Column(
              children: [
                _homeColorChoices(),
                _homeBackgroundChoices(),
                Row(children: [
                  const Text('استدارة البطاقات'),
                  Expanded(child: Slider(value: _store.radius, min: 8, max: 30, divisions: 11, label: _store.radius.round().toString(), onChanged: (value) => setState(() => _store.setTheme(newRadius: value)))),
                ]),
                DropdownButtonFormField<String>(
                  value: _store.fontSize,
                  decoration: const InputDecoration(labelText: 'حجم الخط'),
                  items: const [DropdownMenuItem(value: 'small', child: Text('صغير')), DropdownMenuItem(value: 'medium', child: Text('متوسط')), DropdownMenuItem(value: 'large', child: Text('كبير'))],
                  onChanged: (value) => setState(() => _store.setTheme(newFontSize: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ وتطبيق الصفحة الرئيسية')),
        ],
      );

  Widget _homePreviewCanvas() => AnimatedBuilder(
        animation: _store,
        builder: (_, __) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Color(_store.backgroundColor), borderRadius: BorderRadius.circular(_store.radius), border: Border.all(color: Color(_store.primaryColor).withOpacity(.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(textDirection: TextDirection.rtl, children: [
              Expanded(child: _editableHomeLabel('appName', bold: true)),
              Switch(value: _store.isVisible('appName'), onChanged: (value) => setState(() => _store.setVisibility('appName', value))),
            ]),
            _editableHomeLabel('organizationName'),
            const Divider(),
            _homePreviewCard('totalTasks', Icons.task_alt, '12', _store.primaryColor),
            _homePreviewCard('inProgress', Icons.timelapse, '5', _store.accentColor),
            _homePreviewCard('submitted', Icons.pending_actions_outlined, '3', 0xFF68419A),
            _homePreviewCard('lateTasks', Icons.schedule, '2', 0xFFAB2B37),
            _homePreviewSection('workSection', [
              _homePreviewModule('taskManagement', Icons.task_alt, 'متابعة المهام والتقارير الناتجة من الجداول الموحدة'),
              _homePreviewModule('reports', Icons.description_outlined, 'التقارير المرفوعة للمراجعة والاعتماد'),
              _homePreviewModule('performance', Icons.query_stats, 'ترتيب الموظفين ومقارنة الفروع'),
            ]),
            _homePreviewSection('unifiedTable', [
              _homePreviewModule('unifiedTable', Icons.table_chart_outlined, 'إنشاء المهام وإرسالها للموظفين'),
            ]),
            _homePreviewSection('adminSections', [
              _homePreviewModule('employees', Icons.people_outline, 'ملفات الموظفين وبياناتهم الأساسية'),
              _homePreviewModule('settings', Icons.settings_outlined, 'إعدادات الحساب والتطبيق'),
            ]),
            for (final card in _store.customCards) _homeCustomCardPreview(card),
          ]),
        ),
      );

  Widget _editableHomeLabel(String key, {bool bold = false}) => TextField(
        controller: _controller(key),
        onChanged: (value) => _store.setLabel(key, value),
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
      );

  Widget _homePreviewCard(String key, IconData icon, String value, int color) => Visibility(
        visible: _store.isVisible(key),
        replacement: _hiddenHomeItem(key),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_store.radius)),
          color: _store.statsStyle == 'white' ? Colors.white : Color(color).withOpacity(.12),
          child: Row(textDirection: TextDirection.rtl, children: [
            Icon(icon, color: Color(color)),
            const SizedBox(width: 8),
            Expanded(child: _editableHomeLabel(key, bold: true)),
            Text(value, style: TextStyle(fontSize: _store.fontSize == 'large' ? 24 : 18, fontWeight: FontWeight.bold, color: Color(color))),
            Switch(value: _store.isVisible(key), onChanged: (value) => setState(() => _store.setVisibility(key, value))),
          ]),
        ),
      );

  Widget _homePreviewSection(String key, List<Widget> children) => Visibility(
        visible: _store.isVisible(key),
        replacement: _hiddenHomeItem(key),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_store.radius)),
          child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(textDirection: TextDirection.rtl, children: [Expanded(child: _editableHomeLabel(key, bold: true)), Switch(value: _store.isVisible(key), onChanged: (value) => setState(() => _store.setVisibility(key, value)))]),
            ...children,
          ])),
        ),
      );

  Widget _homePreviewModule(String key, IconData icon, String description) => Visibility(
        visible: _store.isVisible(key),
        replacement: _hiddenHomeItem(key),
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: Color(_store.primaryColor)),
          title: _editableHomeLabel(key, bold: true),
          subtitle: Text(description, textAlign: TextAlign.right),
          trailing: Switch(value: _store.isVisible(key), onChanged: (value) => setState(() => _store.setVisibility(key, value))),
        ),
      );

  Widget _hiddenHomeItem(String key) => Card(
        color: Colors.grey.shade100,
        child: ListTile(
          title: Text('${_store.label(key)} (مخفي)', textAlign: TextAlign.right),
          trailing: IconButton(
            tooltip: 'إظهار',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => setState(() => _store.setVisibility(key, true)),
          ),
        ),
      );

  Widget _homeCustomCardPreview(Map<String, dynamic> card) => Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              TextField(
                textAlign: TextAlign.right,
                controller: _customCardController(card, 'title'),
                onChanged: (value) {
                  card['title'] = value;
                  _store.notifyListeners();
                },
                decoration: const InputDecoration(labelText: 'عنوان البطاقة'),
              ),
              TextField(
                textAlign: TextAlign.right,
                controller: _customCardController(card, 'description'),
                onChanged: (value) {
                  card['description'] = value;
                  _store.notifyListeners();
                },
                decoration: const InputDecoration(labelText: 'تفاصيل البطاقة'),
              ),
            ],
          ),
        ),
      );

  TextEditingController _customCardController(
    Map<String, dynamic> card,
    String field,
  ) {
    final key = 'custom:${identityHashCode(card)}:$field';
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: '${card[field] ?? ''}'),
    );
  }

  Widget _homeColorChoices() => Wrap(spacing: 8, runSpacing: 8, children: [
        _colorChoice('كحلي وذهبي', 0xFF0B3458, 0xFFDBA62A),
        _colorChoice('أخضر هادئ', 0xFF146B50, 0xFFDBA62A),
        _colorChoice('أزرق حديث', 0xFF164C80, 0xFF53A7D8),
      ]);

  Widget _homeBackgroundChoices() => Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, children: [
        ActionChip(label: const Text('خلفية فاتحة'), onPressed: () => setState(() => _store.setTheme(background: 0xFFF5F7FD))),
        ActionChip(label: const Text('خلفية بيضاء'), onPressed: () => setState(() => _store.setTheme(background: Colors.white.value))),
        ActionChip(label: const Text('خلفية هادئة'), onPressed: () => setState(() => _store.setTheme(background: 0xFFEAF4F0))),
      ]));

  Widget _labelsTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _intro('تعديل الأسماء والتسميات', 'غيّر النصوص ثم احفظ لتنعكس على الشاشات التي تدعم التخصيص.'),
          _labelGroup('الهيدر والهوية', ['appName', 'organizationName', 'tagline']),
          _labelGroup('الشريط السفلي', ['home', 'tasks', 'employees']),
          _labelGroup('الرئيسية والبطاقات', [
            'workSection', 'unifiedTable', 'taskManagement', 'reports',
            'dailyReports', 'employeeReports', 'totalTasks', 'inProgress',
            'submitted', 'lateTasks'
          ]),
          _labelGroup('لوحة الإدارة', ['adminSections']),
        ],
      );

  Widget _labelGroup(String title, List<String> keys) => SectionCard(
        title: title,
        child: Column(
          children: keys
              .map(
                (key) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller(key),
                          textDirection: TextDirection.rtl,
                          decoration: InputDecoration(
                            labelText: AppCustomizer.defaults[key] ?? key,
                            suffixIcon: IconButton(
                              tooltip: 'استعادة الافتراضي',
                              icon: const Icon(Icons.restore),
                              onPressed: () {
                                _controller(key).text =
                                    AppCustomizer.defaults[key] ?? key;
                                setState(() {});
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      );

  Widget _layoutTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _intro('الترتيب والإظهار/الإخفاء', 'تحكم في البطاقات الظاهرة، وأضف بطاقة مخصصة للرئيسية.'),
          SectionCard(
            title: 'بطاقات الرئيسية',
            child: Column(
              children: [
                _toggle('بطاقة الجدول الموحد', 'unifiedTable'),
                _toggle('قسم العمل والمتابعة', 'workSection'),
                _toggle('إدارة المهام', 'taskManagement'),
                _toggle('التقارير', 'reports'),
                _toggle('التقارير اليومية المصممة', 'dailyReports'),
                _toggle('تقارير الموظف', 'employeeReports'),
              ],
            ),
          ),
          SectionCard(
            title: 'أقسام الإدارة',
            child: Column(
              children: [
                _toggle('عرض أقسام الإدارة', 'adminSections'),
                _toggle('الموظفون', 'employees'),
                _toggle('سجل النشاط', 'activity'),
                _toggle('الأداء', 'performance'),
              ],
            ),
          ),
          SectionCard(
            title: 'بطاقات مخصصة',
            child: Column(
              children: [
                ..._store.customCards.asMap().entries.map(
                      (entry) => ListTile(
                        title: Text('${entry.value['title'] ?? ''}'),
                        subtitle: Text('${entry.value['description'] ?? ''}'),
                        leading: const Icon(Icons.drag_handle),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_up),
                              onPressed: entry.key == 0
                                  ? null
                                  : () => setState(() => _store.moveCard(entry.key, entry.key - 1)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down),
                              onPressed: entry.key == _store.customCards.length - 1
                                  ? null
                                  : () => setState(() => _store.moveCard(entry.key, entry.key + 1)),
                            ),
                          ],
                        ),
                      ),
                    ),
                OutlinedButton.icon(
                  onPressed: _addCard,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة بطاقة مخصصة'),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _toggle(String title, String key) => SwitchListTile(
        title: Text(title, textAlign: TextAlign.right),
        value: _store.isVisible(key),
        onChanged: (value) => setState(() => _store.setVisibility(key, value)),
      );

  Widget _unifiedTableTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _intro('تخصيص الجدول الموحد من المعاينة', 'اضغط على العناوين لتعديلها مباشرة، واستخدم أدوات كل قسم لإظهاره أو إخفائه وتحريكه دون مغادرة المعاينة.'),
          _previewControls(),
          const SizedBox(height: 10),
          _devicePreview(),
          const SizedBox(height: 12),
          _currentTasksCard(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: _saveUnified, icon: const Icon(Icons.save), label: const Text('حفظ وتطبيق الجدول'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => _store.resetUnified()), icon: const Icon(Icons.restore), label: const Text('استعادة الافتراضي'))),
          ]),
        ],
      );

  Widget _previewControls() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(label: const Text('هاتف'), selected: _previewDevice == 'phone', onSelected: (_) => setState(() => _previewDevice = 'phone')),
          ChoiceChip(label: const Text('جهاز لوحي'), selected: _previewDevice == 'tablet', onSelected: (_) => setState(() => _previewDevice = 'tablet')),
          ChoiceChip(label: const Text('عمودي'), selected: !_previewLandscape, onSelected: (_) => setState(() => _previewLandscape = false)),
          ChoiceChip(label: const Text('أفقي'), selected: _previewLandscape, onSelected: (_) => setState(() => _previewLandscape = true)),
        ],
      );

  Widget _slider(String title, double value, double min, double max, ValueChanged<double> onChanged) => Row(children: [SizedBox(width: 150, child: Text(title, textAlign: TextAlign.right)), Expanded(child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged))]);

  Widget _fieldPlacementEditor(String key) {
    final layout = _store.unifiedFieldLayout(key);
    final span = '${layout['span'] ?? 'half'}';
    final align = '${layout['align'] ?? 'right'}';
    return Column(children: [
      Row(children: [Expanded(child: Text(_store.unifiedLabel(key), textAlign: TextAlign.right)), IconButton(tooltip: 'يسار', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _store.moveUnifiedField(key, dx: -1))), IconButton(tooltip: 'يمين', icon: const Icon(Icons.arrow_forward), onPressed: () => setState(() => _store.moveUnifiedField(key, dx: 1))), IconButton(tooltip: 'أعلى', icon: const Icon(Icons.arrow_upward), onPressed: () => setState(() => _store.moveUnifiedField(key, dy: -1))), IconButton(tooltip: 'أسفل', icon: const Icon(Icons.arrow_downward), onPressed: () => setState(() => _store.moveUnifiedField(key, dy: 1)))]),
      Row(children: [Expanded(child: DropdownButtonFormField<String>(value: span, decoration: const InputDecoration(labelText: 'العرض'), items: const [DropdownMenuItem(value: 'full', child: Text('كامل')), DropdownMenuItem(value: 'half', child: Text('نصف')), DropdownMenuItem(value: 'third', child: Text('ثلث'))], onChanged: (v) => setState(() => _store.setUnifiedFieldLayout(key, span: v)))), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<String>(value: align, decoration: const InputDecoration(labelText: 'المحاذاة'), items: const [DropdownMenuItem(value: 'right', child: Text('يمين')), DropdownMenuItem(value: 'center', child: Text('وسط')), DropdownMenuItem(value: 'left', child: Text('يسار'))], onChanged: (v) => setState(() => _store.setUnifiedFieldLayout(key, align: v))))]),
      const Divider(),
    ]);
  }

  Future<void> _saveUnified() async {
    for (final key in UnifiedTableCustomization.defaults.keys) {
      final controller = _controllers['unified:$key'];
      if (controller != null) _store.setUnifiedLabel(key, controller.text);
    }
    await _store.save();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تخصيص الجدول الموحد وتطبيقه.')));
  }

  Widget _themeTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _intro('المظهر والألوان', 'اختر ألوان الهوية وحجم الخط واستدارة البطاقات.'),
          SectionCard(
            title: 'ألوان مقترحة',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _colorChoice('كحلي المؤسسة', 0xFF0B3458, 0xFFDBA62A),
                _colorChoice('أخضر هادئ', 0xFF146B50, 0xFFDBA62A),
                _colorChoice('أزرق حديث', 0xFF164C80, 0xFF53A7D8),
              ],
            ),
          ),
          SectionCard(
            title: 'خيارات العرض',
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _store.statsStyle,
                  decoration: const InputDecoration(labelText: 'نمط بطاقات الإحصائيات'),
                  items: const [
                    DropdownMenuItem(value: 'pastel', child: Text('ملون Pastel')),
                    DropdownMenuItem(value: 'white', child: Text('أبيض موحد Clean White')),
                  ],
                  onChanged: (value) => setState(() => _store.setTheme(newStatsStyle: value)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _store.fontSize,
                  decoration: const InputDecoration(labelText: 'حجم الخط'),
                  items: const [
                    DropdownMenuItem(value: 'small', child: Text('صغير')),
                    DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                    DropdownMenuItem(value: 'large', child: Text('كبير')),
                  ],
                  onChanged: (value) => setState(() => _store.setTheme(newFontSize: value)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('استدارة الحواف'),
                    Expanded(
                      child: Slider(
                        value: _store.radius,
                        min: 8,
                        max: 30,
                        divisions: 11,
                        label: _store.radius.round().toString(),
                        onChanged: (value) => setState(() => _store.setTheme(newRadius: value)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _fieldDesignCard(),
        ],
      );

  Widget _fieldDesignCard() => SectionCard(
        title: 'تصميم الحقول وموقعها',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _store.fieldStyle,
              decoration: const InputDecoration(labelText: 'شكل الحقل'),
              items: const [
                DropdownMenuItem(value: 'outlined', child: Text('إطار خارجي')),
                DropdownMenuItem(value: 'filled', child: Text('خلفية ممتلئة')),
                DropdownMenuItem(value: 'underlined', child: Text('خط سفلي')),
                DropdownMenuItem(value: 'plain', child: Text('بدون إطار')),
              ],
              onChanged: (value) => setState(() => _store.setFieldStyle(style: value)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _store.fieldLabelSize,
              decoration: const InputDecoration(labelText: 'حجم عنوان الحقل'),
              items: const [
                DropdownMenuItem(value: 'small', child: Text('صغير')),
                DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                DropdownMenuItem(value: 'large', child: Text('كبير')),
              ],
              onChanged: (value) => setState(() => _store.setFieldStyle(labelSize: value)),
            ),
            Row(children: [
              const Text('استدارة الحقل'),
              Expanded(child: Slider(value: _store.fieldRadius, min: 6, max: 30, divisions: 12, onChanged: (v) => setState(() => _store.setFieldStyle(newRadius: v)))),
            ]),
            Row(children: [
              const Text('المسافة بين الحقول'),
              Expanded(child: Slider(value: _store.fieldSpacing, min: 4, max: 28, divisions: 12, onChanged: (v) => setState(() => _store.setFieldStyle(newSpacing: v)))),
            ]),
            const Divider(),
            const Text('ترتيب الحقول وموقعها', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)),
            ..._store.fieldOrder.asMap().entries.map((entry) => ListTile(
                  dense: true,
                  title: Text(_fieldName(entry.value), textAlign: TextAlign.right),
                  leading: const Icon(Icons.drag_handle),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.keyboard_arrow_up), onPressed: entry.key == 0 ? null : () => setState(() => _store.moveField(entry.key, entry.key - 1))),
                    IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: entry.key == _store.fieldOrder.length - 1 ? null : () => setState(() => _store.moveField(entry.key, entry.key + 1))),
                  ]),
                )),
            const SizedBox(height: 6),
            _fieldPreview(),
          ],
        ),
      );

  String _fieldName(String key) => const {
        'title': 'العنوان',
        'description': 'الوصف والتفاصيل',
        'status': 'الحالة',
        'date': 'التاريخ',
        'attachment': 'المرفق',
      }[key] ?? key;

  Widget _fieldPreview() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF5F7FD), borderRadius: BorderRadius.circular(_store.fieldRadius)),
        child: Column(
          children: _store.fieldOrder.take(3).map((key) => Padding(
                padding: EdgeInsets.only(bottom: _store.fieldSpacing),
                child: TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: _fieldName(key),
                    filled: _store.fieldStyle == 'filled',
                    fillColor: Color(_store.fieldFillColor),
                    border: _store.fieldStyle == 'plain'
                        ? InputBorder.none
                        : _store.fieldStyle == 'underlined'
                            ? const UnderlineInputBorder()
                            : OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _store.fieldRadius,
                                ),
                              ),
                  ),
                ),
              )).toList(),
        ),
      );

  Widget _colorChoice(String title, int primary, int accent) => ActionChip(
        avatar: CircleAvatar(backgroundColor: Color(primary)),
        label: Text(title),
        onPressed: () => setState(() => _store.setTheme(primary: primary, accent: accent)),
      );

  Widget _devicePreview() => AnimatedBuilder(
        animation: _store,
        builder: (_, __) {
          final portraitWidth = _previewDevice == 'phone' ? 230.0 : 390.0;
          final portraitHeight = _previewDevice == 'phone' ? 430.0 : 500.0;
          final width = _previewLandscape ? portraitHeight : portraitWidth;
          final height = _previewLandscape ? portraitWidth : portraitHeight;
          return Center(
            child: Container(
              width: width,
              height: height,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(_previewDevice == 'phone' ? 28 : 18),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_previewDevice == 'phone' ? 20 : 12),
                child: Material(
                  color: Color(_store.backgroundColor),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _store.label('appName'),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: _store.fontSize == 'large' ? 20 : 16,
                            fontWeight: FontWeight.bold,
                            color: Color(_store.primaryColor),
                          ),
                        ),
                        Text(_store.label('organizationName'), textAlign: TextAlign.right),
                        const Divider(),
                        _unifiedPreviewContent(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _unifiedPreviewContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _editablePreviewLabel('screenTitle', bold: true),
          _editablePreviewLabel('screenSubtitle', fontSize: 11),
          const SizedBox(height: 8),
          ..._store.unifiedSectionOrder.asMap().entries
              .where((entry) => _store.isUnifiedVisible(entry.value))
              .map((entry) => _unifiedPreviewSection(entry.key, entry.value)),
        ],
      );

  Widget _unifiedPreviewSection(int index, String key) {
    final title = _store.unifiedLabel(key);
    final content = key == 'employee'
        ? _unifiedPreviewEmployee()
        : key == 'daily' || key == 'exception'
            ? _unifiedPreviewSchedule()
            : key == 'sent'
                ? const Text('لا توجد جداول مرسلة في المعاينة', textAlign: TextAlign.right)
                : key == 'approval'
                    ? const Wrap(textDirection: TextDirection.rtl, spacing: 4, children: [Chip(label: Text('إقرار الموظف')), Chip(label: Text('مراجعة المسؤول'))])
                    : Text('محتوى قسم $title', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12));
    return _unifiedPreviewBox(key, index, content);
  }

  Widget _unifiedPreviewEmployee() => LayoutBuilder(builder: (context, constraints) {
        final keys = ['employeeField', 'roleField', 'branchField', 'startDate'].where(_store.isUnifiedFieldVisible).toList()
          ..sort((a, b) {
            final left = _store.unifiedFieldLayout(a);
            final right = _store.unifiedFieldLayout(b);
            final row = ((left['row'] as num?)?.toInt() ?? 0).compareTo((right['row'] as num?)?.toInt() ?? 0);
            return row != 0 ? row : ((left['column'] as num?)?.toInt() ?? 0).compareTo((right['column'] as num?)?.toInt() ?? 0);
          });
        return Wrap(textDirection: TextDirection.rtl, spacing: _store.unifiedSpacing, runSpacing: _store.unifiedSpacing, children: keys.map((key) {
          final layout = _store.unifiedFieldLayout(key);
          final span = '${layout['span'] ?? 'half'}';
          final width = span == 'full' ? constraints.maxWidth : span == 'third' ? (constraints.maxWidth - _store.unifiedSpacing * 2) / 3 : (constraints.maxWidth - _store.unifiedSpacing) / 2;
          final align = '${layout['align'] ?? 'right'}';
          return SizedBox(width: width, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: _editablePreviewLabel(key)), Switch(value: _store.isUnifiedFieldVisible(key), onChanged: (v) => setState(() => _store.setUnifiedFieldVisibility(key, v))) ]),
            TextField(readOnly: true, textAlign: align == 'left' ? TextAlign.left : align == 'center' ? TextAlign.center : TextAlign.right, decoration: const InputDecoration(isDense: true, hintText: 'معاينة القيمة')),
          ]));
        }).toList());
      });

  Widget _unifiedPreviewSchedule() => Column(children: [
        Row(textDirection: TextDirection.rtl, children: [
          Expanded(child: _editablePreviewLabel('time')),
          Expanded(flex: 2, child: _editablePreviewLabel('task')),
          Expanded(child: _editablePreviewLabel('output')),
        ]),
        const Divider(height: 10),
        const Row(textDirection: TextDirection.rtl, children: [
          Expanded(child: Text('08:00', textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text('مهمة حالية أو معاينة', textAlign: TextAlign.right)),
          Expanded(child: Text('مخرج', textAlign: TextAlign.right)),
        ]),
      ]);

  Widget _editablePreviewLabel(String key, {bool bold = false, double? fontSize}) => TextField(
        controller: _unifiedController(key),
        onChanged: (value) => _store.setUnifiedLabel(key, value),
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: fontSize),
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 2)),
      );

  Widget _unifiedPreviewBox(String key, int index, Widget child) => Container(
        margin: EdgeInsets.only(bottom: _store.unifiedSpacing),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFF8FBFA), borderRadius: BorderRadius.circular(_store.unifiedRadius), border: Border.all(color: const Color(0xFFD8E4E0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(textDirection: TextDirection.rtl, children: [
            Expanded(child: _editablePreviewLabel(key, bold: true)),
            IconButton(tooltip: 'إخفاء القسم', icon: const Icon(Icons.visibility_outlined, size: 18), onPressed: () => setState(() => _store.setUnifiedVisibility(key, false))),
            IconButton(tooltip: 'تحريك لأعلى', icon: const Icon(Icons.keyboard_arrow_up, size: 18), onPressed: index == 0 ? null : () => setState(() => _store.moveUnifiedSection(index, index - 1))),
            IconButton(tooltip: 'تحريك لأسفل', icon: const Icon(Icons.keyboard_arrow_down, size: 18), onPressed: index == _store.unifiedSectionOrder.length - 1 ? null : () => setState(() => _store.moveUnifiedSection(index, index + 1))),
          ]),
          const SizedBox(height: 4),
          child,
        ]),
      );

  Widget _currentTasksCard() => SectionCard(
        title: 'المهام الحالية',
        child: _tasksLoading
            ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            : _currentTasks.isEmpty
                ? const Text('لا توجد مهام حالية لعرضها.', textAlign: TextAlign.right)
                : Column(children: _currentTasks.map((task) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${task['title'] ?? 'مهمة'}', textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('الحالة: ${uiStatusLabel('${task['status'] ?? ''}')} · الأولوية: ${uiPriorityLabel('${task['priority'] ?? ''}')} · الموعد: ${task['due_at'] ?? 'غير محدد'}', textAlign: TextAlign.right),
                    )).toList()),
      );

  Widget _intro(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SectionCard(
          title: title,
          child: Text(subtitle, textAlign: TextAlign.right),
        ),
      );

  Future<void> _addCard() async {
    final title = TextEditingController();
    final description = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة بطاقة مخصصة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم البطاقة')),
          TextField(controller: description, decoration: const InputDecoration(labelText: 'الوصف')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (result == true && title.text.trim().isNotEmpty) {
      setState(() => _store.addCard(title.text.trim(), description.text.trim(), Icons.dashboard_outlined.codePoint));
    }
    title.dispose();
    description.dispose();
  }

  Future<void> _save() async {
    for (final entry in _controllers.entries) {
      if (entry.key.startsWith('unified:')) {
        _store.setUnifiedLabel(
          entry.key.substring('unified:'.length),
          entry.value.text,
        );
      } else {
        _store.setLabel(entry.key, entry.value.text);
      }
    }
    await _store.save();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ وتطبيق التغييرات.')));
  }

  Future<void> _export() async {
    await _save();
    final path = await FilePicker.saveFile(
      dialogTitle: 'تصدير إعدادات الواجهة',
      fileName: 'nexora-ui-settings.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(_store.toJsonMap()))),
    );
    if (mounted && path != null) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصدير الإعدادات.')));
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty || files.first.path == null) return;
    try {
      final bytes = await File(files.first.path!).readAsBytes();
      await _store.importJson(utf8.decode(bytes));
      for (final entry in _controllers.entries) {
        entry.value.text = entry.key.startsWith('unified:')
            ? _store.unifiedLabel(entry.key.substring('unified:'.length))
            : _store.label(entry.key);
      }
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم استيراد الإعدادات.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ملف JSON غير صالح.')));
    }
  }

}

class _ProfileLoader {
  const _ProfileLoader();
  Future<bool> load() async {
    // The screen is protected again by the same manager permission used by
    // the existing administration surfaces.
    final raw = await Supabase.instance.client.rpc('mobile_my_profile');
    final employee = raw is Map ? raw['employee'] : null;
    if (employee is! Map) return false;
    final permissions = employee['permissions'];
    return permissions is List && permissions.map((e) => '$e').contains('tasks.manage');
  }
}
