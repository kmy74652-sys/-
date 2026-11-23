import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_customizer.dart';
import '../../shared/app_shell.dart';

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
  late final TabController _tabs;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    await _store.load();
    try {
      final profile = await const _ProfileLoader().load();
      _allowed = profile;
    } catch (_) {
      _allowed = false;
    }
    if (mounted) setState(() => _loading = false);
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
                            Tab(text: 'التسميات'),
                            Tab(text: 'الترتيب والإظهار'),
                            Tab(text: 'المظهر والألوان'),
                            Tab(text: 'المعاينة والحفظ'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          children: [
                            _labelsTab(),
                            _layoutTab(),
                            _themeTab(),
                            _storageTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
      );

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
                _toggle('الموظفون', 'adminEmployees'),
                _toggle('سجل النشاط', 'adminActivity'),
                _toggle('الأداء', 'adminPerformance'),
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
                  decoration: InputDecoration(labelText: _fieldName(key), filled: _store.fieldStyle == 'filled', fillColor: Color(_store.fieldFillColor), border: _store.fieldStyle == 'plain' ? InputBorder.none : _store.fieldStyle == 'underlined' ? const UnderlineInputBorder() : OutlineInputBorder(borderRadius: BorderRadius.circular(_store.fieldRadius)),
                ),
              )).toList(),
        ),
      );

  Widget _colorChoice(String title, int primary, int accent) => ActionChip(
        avatar: CircleAvatar(backgroundColor: Color(primary)),
        label: Text(title),
        onPressed: () => setState(() => _store.setTheme(primary: primary, accent: accent)),
      );

  Widget _storageTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _intro('المعاينة والحفظ والنسخ الاحتياطي', 'التغييرات المؤقتة تظهر مباشرة، والحفظ يجعلها دائمة بعد إغلاق التطبيق.'),
          SectionCard(
            title: 'معاينة',
            child: AnimatedBuilder(
              animation: _store,
              builder: (_, __) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(_store.backgroundColor),
                  borderRadius: BorderRadius.circular(_store.radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_store.label('appName'), style: TextStyle(fontSize: _store.fontSize == 'large' ? 24 : 19, fontWeight: FontWeight.bold, color: Color(_store.primaryColor))),
                    Text(_store.label('organizationName')),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: null, child: Text(_store.label('unifiedTable'))),
                  ],
                ),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ وتطبيق التغييرات'),
          ),
          OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('تصدير الإعدادات JSON'),
          ),
          OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('استيراد الإعدادات JSON'),
          ),
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restore, color: Colors.red),
            label: const Text('إعادة ضبط المصنع', style: TextStyle(color: Colors.red)),
          ),
        ],
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
    for (final entry in _controllers.entries) _store.setLabel(entry.key, entry.value.text);
    await _store.save();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ وتطبيق التغييرات.')));
  }

  Future<void> _export() async {
    await _save();
    final path = await FilePicker.saveFile(
      dialogTitle: 'تصدير إعدادات الواجهة',
      fileName: 'alshaeri-ui-settings.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(_store.toJsonMap()))),
    );
    if (mounted && path != null) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصدير الإعدادات.')));
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (result == null || result.files.single.bytes == null) return;
    try {
      await _store.importJson(utf8.decode(result.files.single.bytes!));
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم استيراد الإعدادات.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ملف JSON غير صالح.')));
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إعادة ضبط المصنع'),
        content: const Text('سيتم حذف تخصيصات الواجهة وإرجاع القيم الافتراضية. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إعادة الضبط')),
        ],
      ),
    );
    if (confirmed == true) {
      await _store.reset();
      for (final entry in _controllers.entries) entry.value.text = _store.label(entry.key);
      if (mounted) setState(() {});
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
