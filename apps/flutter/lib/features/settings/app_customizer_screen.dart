import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_customizer.dart';
import '../../shared/app_shell.dart';
import '../../shared/organization_branding.dart';
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
  bool _previewFullScreen = true;
  bool _tasksLoading = true;
  Uint8List? _pendingLogoBytes;
  String? _pendingLogoMime;
  bool _logoBusy = false;
  List<Map<String, dynamic>> _currentTasks = const [];
  late final TabController _tabs;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
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
                            Tab(text: 'هوية وتصميم التقارير'),
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
                            _reportThemeTab(),
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
              _homePreviewModule('independentTasks', Icons.assignment_outlined, 'عرض المهام اليومية المستقلة وتنفيذها ومتابعة حالتها'),
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
                  _store.updateCustomCard(card, 'title', value);
                },
                decoration: const InputDecoration(labelText: 'عنوان البطاقة'),
              ),
              TextField(
                textAlign: TextAlign.right,
                controller: _customCardController(card, 'description'),
                onChanged: (value) {
                  _store.updateCustomCard(card, 'description', value);
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
            'workSection', 'unifiedTable', 'taskManagement', 'independentTasks', 'reports',
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
                _toggle('المهام المستقلة', 'independentTasks'),
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

  TextEditingController _reportController(String key, String value) => _controllers.putIfAbsent('report:$key', () => TextEditingController(text: value));

  Widget _reportField(String key, String label, String value, void Function(String) onChanged, {int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(controller: _reportController(key, value), textAlign: TextAlign.right, maxLines: maxLines, onChanged: onChanged, decoration: InputDecoration(labelText: label)),
      );

  Widget _reportThemeTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _intro('هوية وتصميم التقارير', 'عدّل التقرير من المعاينة نفسها. تحفظ الإعدادات محليًا لهذا الجهاز، ويستخدم التصدير شعار المؤسسة المشترك من Supabase تلقائيًا عند توفره.'),
          _reportPreview(),
          const SizedBox(height: 12),
          SectionCard(title: 'بيانات المؤسسة', child: Column(children: [
            _reportField('companyName', 'اسم الشركة أو المؤسسة', _store.reportCompanyName, (v) => setState(() => _store.setReportTheme(companyName: v))),
            _reportField('branchName', 'اسم الفرع أو المؤسسة', _store.reportBranchName, (v) => setState(() => _store.setReportTheme(branchName: v))),
            _reportField('phone', 'الهاتف', _store.reportPhone, (v) => setState(() => _store.setReportTheme(phone: v))),
            _reportField('email', 'البريد الإلكتروني', _store.reportEmail, (v) => setState(() => _store.setReportTheme(email: v))),
            _reportField('address', 'العنوان', _store.reportAddress, (v) => setState(() => _store.setReportTheme(address: v))),
          ])),
          SectionCard(title: 'الشعار والترويسة', child: Column(children: [
            Row(children: [Expanded(child: Text(_store.reportLogoUrl.isEmpty ? 'سيظهر شعار المؤسسة المشترك تلقائيًا' : 'تم تحديد شعار التقرير', textAlign: TextAlign.right)), OutlinedButton.icon(onPressed: _logoBusy ? null : _pickReportLogo, icon: const Icon(Icons.upload_outlined), label: const Text('رفع شعار'))]),
            DropdownButtonFormField<String>(value: _store.reportLogoPosition, decoration: const InputDecoration(labelText: 'موضع الشعار'), items: const [DropdownMenuItem(value: 'right', child: Text('يمين الترويسة')), DropdownMenuItem(value: 'center', child: Text('وسط الترويسة')), DropdownMenuItem(value: 'left', child: Text('يسار الترويسة'))], onChanged: (v) => setState(() => _store.setReportTheme(logoPosition: v))),
            DropdownButtonFormField<String>(value: _store.reportHeaderStyle, decoration: const InputDecoration(labelText: 'شكل الترويسة'), items: const [DropdownMenuItem(value: 'band', child: Text('شريط ملون')), DropdownMenuItem(value: 'minimal', child: Text('بسيطة')), DropdownMenuItem(value: 'boxed', child: Text('إطار كامل'))], onChanged: (v) => setState(() => _store.setReportTheme(headerStyle: v))),
            Row(children: [const Text('حجم الشعار'), Expanded(child: Slider(value: _store.reportLogoSize, min: 28, max: 110, divisions: 16, label: _store.reportLogoSize.round().toString(), onChanged: (v) => setState(() => _store.setReportTheme(logoSize: v))))]),
            _reportField('headerText', 'نص الترويسة الإضافي', _store.reportHeaderText, (v) => setState(() => _store.setReportTheme(headerText: v))),
          ])),
          SectionCard(title: 'ألوان وشكل الجدول', child: Column(children: [
            DropdownButtonFormField<String>(value: _store.reportTableStyle, decoration: const InputDecoration(labelText: 'شكل الجداول'), items: const [DropdownMenuItem(value: 'simple', child: Text('بسيط')), DropdownMenuItem(value: 'full', child: Text('حدود كاملة')), DropdownMenuItem(value: 'colored', child: Text('تصميم ملون'))], onChanged: (v) => setState(() => _store.setReportTheme(tableStyle: v))),
            Wrap(spacing: 8, children: [_reportColor('كحلي', 0xFF0B3458), _reportColor('أخضر', 0xFF146B50), _reportColor('أزرق', 0xFF164C80), _reportColor('عنابي', 0xFF7A2430)]),
            Row(children: [const Text('حجم الخط'), Expanded(child: Slider(value: _store.reportFontSize, min: 8, max: 16, divisions: 8, label: _store.reportFontSize.toStringAsFixed(0), onChanged: (v) => setState(() => _store.setReportTheme(fontSize: v))))]),
          ])),
          SectionCard(title: 'العناصر الظاهرة', child: Column(children: [
            _reportSwitch('تاريخ التصدير', _store.reportShowExportDate, (v) => _store.setReportTheme(showExportDate: v)),
            _reportSwitch('اسم الموظف', _store.reportShowEmployee, (v) => _store.setReportTheme(showEmployee: v)),
            _reportSwitch('اسم الفرع', _store.reportShowBranch, (v) => _store.setReportTheme(showBranch: v)),
            _reportSwitch('حالة التقرير', _store.reportShowStatus, (v) => _store.setReportTheme(showStatus: v)),
            _reportSwitch('رقم التقرير', _store.reportShowNumber, (v) => _store.setReportTheme(showNumber: v)),
            _reportSwitch('التوقيع', _store.reportShowSignature, (v) => _store.setReportTheme(showSignature: v)),
            _reportSwitch('التذييل', _store.reportShowFooter, (v) => _store.setReportTheme(showFooter: v)),
            _reportField('footerText', 'نص التذييل', _store.reportFooterText, (v) => setState(() => _store.setReportTheme(footerText: v))),
          ])),
          FilledButton.icon(onPressed: _saveReportTheme, icon: const Icon(Icons.save_outlined), label: const Text('حفظ وتطبيق تصميم التقارير')),
        ],
      );

  Widget _reportSwitch(String title, bool value, void Function(bool) onChanged) => SwitchListTile(title: Text(title, textAlign: TextAlign.right), value: value, onChanged: (v) => setState(() => onChanged(v)));
  Widget _reportColor(String label, int color) => ActionChip(label: Text(label), avatar: CircleAvatar(backgroundColor: Color(color)), onPressed: () => setState(() => _store.setReportTheme(primaryColor: color, headingColor: color)));

  Widget _reportPreview() => AnimatedBuilder(animation: _store, builder: (_, __) {
    final primary = Color(_store.reportPrimaryColor);
    final tableColor = _store.reportTableStyle == 'colored' ? primary.withOpacity(.12) : Colors.white;
    return Card(child: Container(padding: const EdgeInsets.all(14), color: Colors.white, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(textDirection: TextDirection.rtl, mainAxisAlignment: _store.reportLogoPosition == 'center' ? MainAxisAlignment.center : _store.reportLogoPosition == 'left' ? MainAxisAlignment.start : MainAxisAlignment.end, children: [
        if (_store.reportLogoUrl.isNotEmpty) Image.network(_store.reportLogoUrl, width: _store.reportLogoSize.clamp(28, 70), height: _store.reportLogoSize.clamp(28, 70), errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined)),
        const SizedBox(width: 8), Text(_store.reportCompanyName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: primary)),
      ]),
      if (_store.reportHeaderText.isNotEmpty) Text(_store.reportHeaderText, textAlign: TextAlign.right),
      const Divider(), Text('تقرير المهمة', textAlign: TextAlign.right, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), Container(color: tableColor, padding: const EdgeInsets.all(8), child: Column(children: const [Text('الحقل                                      القيمة', textAlign: TextAlign.right), Divider(), Text('الحالة                                      مكتملة', textAlign: TextAlign.right), Text('التاريخ                                      26/11/2026', textAlign: TextAlign.right)])),
      if (_store.reportShowFooter) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_store.reportFooterText, textAlign: TextAlign.center, style: TextStyle(color: primary))),
    ])));
  });

  Future<void> _pickReportLogo() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() { _logoBusy = true; _pendingLogoBytes = bytes; _pendingLogoMime = file.extension == 'png' ? 'image/png' : file.extension == 'webp' ? 'image/webp' : 'image/jpeg'; });
    try {
      final profile = await Supabase.instance.client.rpc('mobile_my_profile');
      final employee = profile is Map ? profile['employee'] : null;
      final org = employee is Map ? (employee['institutionId'] ?? employee['institution_id'] ?? employee['organization_id'])?.toString() : null;
      if (org == null || org.isEmpty) throw Exception('تعذر تحديد المؤسسة');
      final path = '$org/report_logo_${DateTime.now().microsecondsSinceEpoch}';
      await Supabase.instance.client.storage.from('organization-branding').uploadBinary(path, _pendingLogoBytes!, fileOptions: FileOptions(contentType: _pendingLogoMime, cacheControl: 'no-cache', upsert: false));
      final url = '${Supabase.instance.client.storage.from('organization-branding').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      final organization = await Supabase.instance.client.from('organizations').select('name,settings').eq('id', org).maybeSingle();
      final settings = organization?['settings'] is Map ? Map<String, dynamic>.from(organization!['settings'] as Map) : <String, dynamic>{};
      final branding = settings['branding'] is Map ? Map<String, dynamic>.from(settings['branding'] as Map) : <String, dynamic>{};
      await Supabase.instance.client.rpc('save_organization_branding', params: {'p_organization_id': org, 'p_name': '${organization?['name'] ?? _store.reportCompanyName}', 'p_tagline': '${branding['tagline'] ?? ''}', 'p_logo_url': url});
      OrganizationBrandingStore.instance.invalidate();
      _store.setReportTheme(logoUrl: url); await _store.save();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع شعار التقرير وحفظه لهذا الجهاز.')));
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر رفع الشعار. تحقق من صلاحية مدير المؤسسة.'))); }
    finally { if (mounted) setState(() => _logoBusy = false); }
  }

  Future<void> _saveReportTheme() async { await _store.save(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تصميم التقارير وتطبيقه.'))); }

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
          ChoiceChip(label: const Text('ملء الشاشة'), selected: _previewFullScreen, onSelected: (value) => setState(() => _previewFullScreen = value)),
          ChoiceChip(label: const Text('هاتف'), selected: _previewDevice == 'phone', onSelected: (_) => setState(() => _previewDevice = 'phone')),
          ChoiceChip(label: const Text('جهاز لوحي'), selected: _previewDevice == 'tablet', onSelected: (_) => setState(() => _previewDevice = 'tablet')),
          ChoiceChip(label: const Text('عمودي'), selected: !_previewLandscape, onSelected: (_) => setState(() => _previewLandscape = false)),
          ChoiceChip(label: const Text('أفقي'), selected: _previewLandscape, onSelected: (_) => setState(() => _previewLandscape = true)),
        ],
      );

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
        builder: (_, __) => LayoutBuilder(
          builder: (context, constraints) {
            final portraitWidth = _previewDevice == 'phone' ? 230.0 : 390.0;
            final portraitHeight = _previewDevice == 'phone' ? 430.0 : 500.0;
            final width = _previewFullScreen
                ? constraints.maxWidth
                : (_previewLandscape ? portraitHeight : portraitWidth);
            final height = _previewFullScreen
                ? (MediaQuery.sizeOf(context).height * .68).clamp(500.0, 760.0).toDouble()
                : (_previewLandscape ? portraitWidth : portraitHeight);
            final framed = !_previewFullScreen;
            final content = Material(
              color: Color(_store.backgroundColor),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_previewFullScreen ? 18 : 12),
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
            );
            return Center(
              child: Container(
                width: width,
                height: height,
                padding: framed ? const EdgeInsets.all(12) : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: framed ? Colors.black : Color(_store.backgroundColor),
                  borderRadius: BorderRadius.circular(framed ? (_previewDevice == 'phone' ? 28 : 18) : _store.unifiedRadius),
                  boxShadow: framed ? const [BoxShadow(color: Colors.black26, blurRadius: 12)] : null,
                  border: framed ? null : Border.all(color: Color(_store.primaryColor).withOpacity(.2)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(framed ? (_previewDevice == 'phone' ? 20 : 12) : _store.unifiedRadius),
                  child: content,
                ),
              ),
            );
          },
        ),
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
            ? _unifiedPreviewSchedule(key)
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

  Widget _unifiedPreviewSchedule(String sectionKey) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(child: Text('صفوف وأعمدة $sectionKey', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
              IconButton(tooltip: 'إضافة صف', icon: const Icon(Icons.add_box_outlined), onPressed: () => setState(() => _store.addUnifiedSchedulePreviewRow())),
              IconButton(tooltip: 'حذف صف', icon: const Icon(Icons.remove_circle_outline), onPressed: _store.unifiedSchedulePreviewRows <= 1 ? null : () => setState(() => _store.removeUnifiedSchedulePreviewRow())),
              IconButton(tooltip: 'إضافة عمود', icon: const Icon(Icons.view_column_outlined), onPressed: () => setState(() => _store.addUnifiedScheduleColumn())),
            ],
          ),
          const Divider(height: 8),
          for (var rowIndex = 0; rowIndex < _store.unifiedSchedulePreviewRows; rowIndex++)
            Padding(
              padding: EdgeInsets.only(bottom: _store.unifiedSpacing),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  for (final column in _store.unifiedScheduleColumns)
                    Expanded(
                      flex: column == 'task' ? 2 : 1,
                      child: Padding(
                        padding: EdgeInsets.only(left: _store.unifiedSpacing / 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _editablePreviewLabel(column, bold: rowIndex == 0),
                            if (rowIndex > 0)
                              Text(
                                column == 'time' ? '08:00' : column == 'task' ? 'مهمة حالية أو معاينة' : column == 'output' ? 'مخرج' : 'قيمة جديدة',
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (rowIndex == 0 && _store.unifiedScheduleColumns.length > 1)
                    IconButton(
                      tooltip: 'حذف آخر عمود',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _store.removeUnifiedScheduleColumn(_store.unifiedScheduleColumns.last)),
                    ),
                ],
              ),
            ),
        ],
      );

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
