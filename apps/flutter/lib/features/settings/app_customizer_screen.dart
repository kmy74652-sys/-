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
  String _selectedHeaderElement = 'company';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
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
                            Tab(text: 'المعاينة المباشرة'),
                            Tab(text: 'معاينة PDF'),
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
                            _livePreviewTab(),
                            _documentPreviewTab(),
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

  Widget _livePreviewTab() => AnimatedBuilder(
        animation: _store,
        builder: (context, _) => ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _intro(
                  'المعاينة المباشرة',
                  'شاهد شكل التطبيق بعد التخصيص قبل الحفظ. أي تعديل على الاسم أو الألوان أو الإظهار ينعكس هنا مباشرة.',
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: Color(_store.primaryColor).withOpacity(.22)),
                  ),
                  child: Container(
                    color: Color(_store.backgroundColor),
                    child: Column(
                      children: [
                        const IgnorePointer(
                          child: _PreviewHeader(),
                        ),
                        const _PreviewDivider(),
                        const IgnorePointer(
                          child: _PreviewTitleBar(),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _liveStatCard('إجمالي المهام', '12', Icons.task_alt, _store.primaryColor)),
                                  const SizedBox(width: 8),
                                  Expanded(child: _liveStatCard('قيد التنفيذ', '5', Icons.timelapse, _store.accentColor)),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(child: _liveStatCard('بانتظار المراجعة', '3', Icons.pending_actions_outlined, 0xFF68419A)),
                                  const SizedBox(width: 8),
                                  Expanded(child: _liveStatCard('مهام متأخرة', '2', Icons.schedule, 0xFFAB2B37)),
                                ],
                              ),
                              _livePreviewSection('العمل والمتابعة', [
                                _liveActionTile('إدارة مهام الجداول الموحدة', Icons.task_alt_outlined),
                                _liveActionTile('المهام المستقلة', Icons.assignment_outlined),
                                _liveActionTile('تقارير الموظفين', Icons.description_outlined),
                              ]),
                            ],
                          ),
                        ),
                        const _PreviewBottomBar(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هذه معاينة تفاعلية للتصميم. الأزرار فيها للعرض فقط، والتغييرات الفعلية تُحفظ من زر الحفظ أسفل المصمم.',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
      );

  Widget _liveStatCard(String title, String value, IconData icon, int color) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_store.radius)),
        color: Color(color).withOpacity(.12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Icon(icon, color: Color(color)),
              Text(value, style: TextStyle(fontSize: _store.fontSize == 'large' ? 24 : 19, fontWeight: FontWeight.w900, color: Color(color))),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _livePreviewSection(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(top: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_store.radius)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, textAlign: TextAlign.right, style: TextStyle(fontSize: _store.fontSize == 'large' ? 19 : 16, fontWeight: FontWeight.w900, color: Color(_store.primaryColor))),
              const Divider(),
              ...children,
            ],
          ),
        ),
      );

  Widget _liveActionTile(String title, IconData icon) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Color(_store.primaryColor)),
        title: Text(title, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Icon(Icons.chevron_left, color: Color(_store.primaryColor)),
      );

  Widget _documentPreviewTab() => FutureBuilder<OrganizationBranding>(
        future: OrganizationBrandingStore.instance.forSession(),
        builder: (context, snapshot) {
          final branding = snapshot.data ?? OrganizationBranding.fallback;
          final company = _store.reportCompanyName.trim().isEmpty ? branding.name : _store.reportCompanyName;
          final logoUrl = _store.reportLogoUrl.trim().isNotEmpty ? _store.reportLogoUrl.trim() : branding.logoUrl;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _intro('معاينة PDF للتقارير والمهام', 'هذه المعاينة تعرض ترتيب الشعار واسم المؤسسة وعنوان المستند كما سيظهر في ملف PDF، وتُحدّث نفسها عند تغيير أي إعداد.'),
              _documentPreviewCard(
                title: 'تقرير المهمة',
                subtitle: 'النتيجة الفعلية والملاحظات الخاصة بالمهمة',
                company: company,
                logoUrl: logoUrl,
              ),
              const SizedBox(height: 14),
              _documentPreviewCard(
                title: 'الجدول الموحد لإنشاء وتنفيذ المهام',
                subtitle: 'معاينة تقرير المهمة الموحدة وحقولها الأساسية',
                company: company,
                logoUrl: logoUrl,
                unified: true,
              ),
              const SizedBox(height: 10),
              const Text('استخدم تبويب «هوية وتصميم التقارير» لتعديل ترتيب العناصر والمحاذاة والحجم والألوان، ثم راجع النتيجة هنا قبل الحفظ.', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          );
        },
      );

  Widget _documentPreviewCard({required String title, required String subtitle, required String company, required String? logoUrl, bool unified = false}) {
    final primary = Color(_store.reportPrimaryColor);
    final headerColor = _store.reportHeaderStyle == 'minimal' ? Colors.white : const Color(0xFFEAF4F0);
    final logo = logoUrl == null || logoUrl.isEmpty
        ? const Icon(Icons.business_outlined, size: 46, color: Color(0xFF0B3458))
        : Image.network(logoUrl, width: _store.reportLogoSize.clamp(38, 72), height: _store.reportLogoSize.clamp(38, 72), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.business_outlined, size: 46, color: Color(0xFF0B3458)));
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: primary.withOpacity(.24))),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: headerColor, border: _store.reportHeaderStyle == 'boxed' ? Border.all(color: primary) : null),
            child: Row(textDirection: TextDirection.rtl, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(company, textAlign: TextAlign.right, style: TextStyle(color: primary, fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(title, textAlign: TextAlign.right, style: TextStyle(color: Color(_store.reportHeadingColor), fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(subtitle, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                if (_store.reportShowExportDate) const Text('تاريخ التصدير: 27-11-2026 01:10', textAlign: TextAlign.right, style: TextStyle(fontSize: 9, color: Colors.black54)),
              ])),
              const SizedBox(width: 10),
              logo,
            ]),
          ),
          const SizedBox(height: 10),
          if (!unified) ...[
            _pdfPreviewMeta('الحالة', 'مكتملة'),
            _pdfPreviewMeta('الموظف', 'أحمد محمد'),
            _pdfPreviewMeta('الفرع', 'الفرع الرئيسي'),
            _pdfPreviewTable(const [['الحقل', 'القيمة'], ['النتيجة الفعلية', 'لا يوجد'], ['حالة التنفيذ', 'لا يوجد'], ['الملاحظات والنتائج', 'لا يوجد']], primary),
          ] else ...[
            _pdfPreviewMeta('المسمى الوظيفي', 'الموظف أو المجموعة'),
            _pdfPreviewMeta('تاريخ بدء التطبيق', '2026-11-27'),
            _pdfPreviewTable(const [['الوقت', 'المهمة والمسؤولية', 'المخرج المطلوب', 'الحالة'], ['08:00', 'مهمة حالية', 'لا يوجد', 'جديدة'], ['—', 'مهمة استثنائية', 'لا يوجد', 'جديدة']], primary),
          ],
        ]),
      ),
    );
  }

  Widget _pdfPreviewMeta(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD8E4E0))),
        child: Row(textDirection: TextDirection.rtl, children: [Expanded(child: Text(label, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))), Text(value, style: const TextStyle(color: Colors.black54))]),
      );

  Widget _pdfPreviewTable(List<List<String>> rows, Color primary) => Table(
        border: TableBorder.all(color: primary.withOpacity(.45)),
        children: rows.map((row) => TableRow(children: row.map((cell) => Padding(padding: const EdgeInsets.all(7), child: Text(cell, textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: row == rows.first ? FontWeight.w900 : FontWeight.normal))).toList())).toList(),
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

  String _reportOrderLabel(String key) => const {
        'company': 'اسم الشركة / المؤسسة',
        'branchName': 'اسم الفرع الثابت',
        'phone': 'الهاتف',
        'email': 'البريد الإلكتروني',
        'address': 'العنوان',
        'headerText': 'نص الترويسة الإضافي',
        'title': 'عنوان التقرير',
        'employee': 'اسم الموظف',
        'taskBranch': 'فرع المهمة',
        'status': 'الحالة',
        'number': 'رقم التقرير',
        'exportDate': 'تاريخ التصدير',
      }[key] ?? key;

  Widget _reportHeaderOrderEditor() => SectionCard(
        title: 'ترتيب عناصر الترويسة وموقعها',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('اسحب العناصر للأعلى أو للأسفل لتحديد ترتيب ظهورها في ملف PDF.', textAlign: TextAlign.right),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _store.reportHeaderOrder.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                setState(() => _store.moveReportHeaderItem(oldIndex, newIndex));
              },
              itemBuilder: (_, index) {
                final key = _store.reportHeaderOrder[index];
                return ListTile(
                  key: ValueKey(key),
                  dense: true,
                  leading: const Icon(Icons.drag_handle),
                  title: Text(_reportOrderLabel(key), textAlign: TextAlign.right),
                  trailing: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              },
            ),
          ],
        ),
      );

  Widget _reportHeaderLayoutEditor() {
    final key = _selectedHeaderElement;
    final layout = _store.reportHeaderLayout(key);
    final align = '${layout['align']}';
    final size = (layout['size'] as num).toDouble();
    final x = (layout['x'] as num).toDouble();
    final y = (layout['y'] as num).toDouble();
    void update({String? nextAlign, double? nextSize, double? nextX, double? nextY}) {
      setState(() => _store.setReportHeaderLayout(key, align: nextAlign, size: nextSize, x: nextX, y: nextY));
    }
    return SectionCard(title: 'تحكم تفصيلي في الترويسة', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('اختر عنصرًا ثم عدّل مكانه وحجمه. ستظهر النتيجة في المعاينة وتُستخدم نفسها عند تصدير PDF.', textAlign: TextAlign.right),
      DropdownButtonFormField<String>(value: key, decoration: const InputDecoration(labelText: 'العنصر المراد تعديله'), items: _store.reportHeaderOrder.map((item) => DropdownMenuItem(value: item, child: Text(_reportOrderLabel(item), textAlign: TextAlign.right))).toList(), onChanged: (value) => setState(() => _selectedHeaderElement = value ?? key)),
      DropdownButtonFormField<String>(value: align, decoration: const InputDecoration(labelText: 'المحاذاة'), items: const [DropdownMenuItem(value: 'right', child: Text('يمين')), DropdownMenuItem(value: 'center', child: Text('وسط')), DropdownMenuItem(value: 'left', child: Text('يسار'))], onChanged: (value) => update(nextAlign: value)),
      Row(children: [const SizedBox(width: 72, child: Text('حجم الخط')), Expanded(child: Slider(value: size, min: 7, max: 32, divisions: 25, label: size.round().toString(), onChanged: (value) => update(nextSize: value)))]),
      Row(children: [const SizedBox(width: 72, child: Text('يمين / يسار')), Expanded(child: Slider(value: x, min: -40, max: 40, divisions: 80, label: x.round().toString(), onChanged: (value) => update(nextX: value)))]),
      Row(children: [const SizedBox(width: 72, child: Text('أعلى / أسفل')), Expanded(child: Slider(value: y, min: -20, max: 20, divisions: 40, label: y.round().toString(), onChanged: (value) => update(nextY: value)))]),
    ]));
  }

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
          _reportHeaderOrderEditor(),
          _reportHeaderLayoutEditor(),
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

  List<Widget> _reportPreviewOrderedContent(Color primary) {
    final widgets = <Widget>[];
    for (final key in _store.reportHeaderOrder) {
      final layout = _store.reportHeaderLayout(key);
      final alignment = layout['align'] == 'left' ? TextAlign.left : layout['align'] == 'center' ? TextAlign.center : TextAlign.right;
      final size = (layout['size'] as num).toDouble();
      final x = (layout['x'] as num).toDouble();
      final y = (layout['y'] as num).toDouble();
      Widget text(String value, {bool bold = false, Color? color}) => Container(
        margin: EdgeInsets.only(left: x > 0 ? x : 0, right: x < 0 ? -x : 0, top: y > 0 ? y : 0, bottom: y < 0 ? -y : 0),
        child: Text(value, textAlign: alignment, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
      );
      switch (key) {
        case 'company': widgets.add(text(_store.reportCompanyName, bold: true, color: primary));
        case 'branchName': if (_store.reportBranchName.isNotEmpty) widgets.add(text(_store.reportBranchName));
        case 'phone': if (_store.reportPhone.isNotEmpty) widgets.add(text('الهاتف: ${_store.reportPhone}'));
        case 'email': if (_store.reportEmail.isNotEmpty) widgets.add(text('البريد الإلكتروني: ${_store.reportEmail}'));
        case 'address': if (_store.reportAddress.isNotEmpty) widgets.add(text('العنوان: ${_store.reportAddress}'));
        case 'headerText': if (_store.reportHeaderText.isNotEmpty) widgets.add(text(_store.reportHeaderText));
        case 'title': widgets.add(text('تقرير المهمة', bold: true));
        case 'employee': if (_store.reportShowEmployee) widgets.add(text('الموظف: أحمد'));
        case 'taskBranch': if (_store.reportShowBranch) widgets.add(text('الفرع: الفرع الرئيسي'));
        case 'status': if (_store.reportShowStatus) widgets.add(text('الحالة: مكتملة'));
        case 'number': if (_store.reportShowNumber) widgets.add(text('رقم التقرير: 0001'));
        case 'exportDate': if (_store.reportShowExportDate) widgets.add(text('تاريخ التصدير: 26/11/2026'));
      }
    }
    return widgets;
  }

  Widget _reportPreview() => AnimatedBuilder(animation: _store, builder: (_, __) {
    final primary = Color(_store.reportPrimaryColor);
    final tableColor = _store.reportTableStyle == 'colored' ? primary.withOpacity(.12) : Colors.white;
    return Card(child: Container(padding: const EdgeInsets.all(14), color: Colors.white, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(textDirection: TextDirection.rtl, mainAxisAlignment: _store.reportLogoPosition == 'center' ? MainAxisAlignment.center : _store.reportLogoPosition == 'left' ? MainAxisAlignment.start : MainAxisAlignment.end, children: [
        if (_store.reportLogoUrl.isNotEmpty) Image.network(_store.reportLogoUrl, width: _store.reportLogoSize.clamp(28, 70), height: _store.reportLogoSize.clamp(28, 70), errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined)),
        const SizedBox(width: 8), const Text('شعار التقرير'),
      ]),
      ..._reportPreviewOrderedContent(primary),
      const Divider(),
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
          _intro('تخصيص الجدول الموحد من المعاينة', 'اضغط على العناوين لتعديلها مباشرة، واستخدم أدوات كل قسم لإظهاره أو إخفائه وتحريكه دون مغادرة المعاينة. سيُستخدم نفس الترتيب والمحتوى عند تصدير PDF الجدول الموحد.'),
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

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader();

  @override
  Widget build(BuildContext context) {
    final store = AppCustomizer.instance;
    return FutureBuilder<OrganizationBranding>(
      future: OrganizationBrandingStore.instance.forSession(),
      builder: (context, snapshot) {
        final logoUrl = snapshot.data?.logoUrl;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              if (logoUrl != null && logoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(logoUrl, width: 48, height: 48, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const _PreviewLogoFallback()),
                )
              else
                const _PreviewLogoFallback(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Text(store.label('appName'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF0B3458), fontSize: 19, fontWeight: FontWeight.w900)),
                Text(store.label('organizationName'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF0B3458), fontSize: 11, fontWeight: FontWeight.w700)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 14, height: 1, color: const Color(0xFFDBA62A)),
                  const SizedBox(width: 5),
                  Flexible(child: Text(store.label('tagline'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9A6814), fontSize: 10, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 5),
                  Container(width: 14, height: 1, color: const Color(0xFFDBA62A)),
                ]),
              ],
            ),
          ),
              const Icon(Icons.notifications_none, color: Color(0xFF0B3458)),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewLogoFallback extends StatelessWidget {
  const _PreviewLogoFallback();

  @override
  Widget build(BuildContext context) => const CircleAvatar(
        radius: 24,
        backgroundColor: Color(0xFF0B3458),
        child: Icon(Icons.business_outlined, color: Color(0xFFDBA62A)),
      );
}

class _PreviewTitleBar extends StatelessWidget {
  const _PreviewTitleBar();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(
          children: [
            const Expanded(child: Text('الرئيسية', textAlign: TextAlign.right, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0B3458)))),
            Text(DateTime.now().toString().substring(0, 16), style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      );
}

class _PreviewDivider extends StatelessWidget {
  const _PreviewDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: 1);
}

class _PreviewBottomBar extends StatelessWidget {
  const _PreviewBottomBar();

  @override
  Widget build(BuildContext context) => Container(
        height: 58,
        decoration: const BoxDecoration(
          color: Color(0xFF0B3458),
          border: Border(top: BorderSide(color: Color(0xFFDBA62A), width: 2)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _PreviewNavItem(Icons.settings_outlined, 'الإعدادات'),
            _PreviewNavItem(Icons.task_alt_outlined, 'المهام'),
            _PreviewNavItem(Icons.home_outlined, 'الرئيسية', selected: true),
          ],
        ),
      );
}

class _PreviewNavItem extends StatelessWidget {
  const _PreviewNavItem(this.icon, this.label, {this.selected = false});

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: selected ? const Color(0xFFDBA62A) : Colors.white70, size: 21),
          Text(label, style: TextStyle(color: selected ? const Color(0xFFDBA62A) : Colors.white70, fontSize: 10)),
        ],
      );
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
