import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCustomizer extends ChangeNotifier {
  AppCustomizer._();
  static final instance = AppCustomizer._();
  static const _storageKey = 'alshaeri_app_customizer_v1';
  bool _loaded = false;
  Future<void>? _loadFuture;
  Map<String, String> labels = {};
  Map<String, bool> visibility = {};
  List<Map<String, dynamic>> customCards = [];
  List<String> fieldOrder = ['title', 'description', 'status', 'date', 'attachment'];
  String fieldStyle = 'outlined';
  int fieldFillColor = 0xFFFFFFFF;
  double fieldRadius = 14, fieldSpacing = 10;
  String fieldLabelSize = 'medium';
  int primaryColor = 0xFF0B3458, accentColor = 0xFFDBA62A, backgroundColor = 0xFFF5F7FD;
  double radius = 16;
  String fontSize = 'medium', statsStyle = 'pastel';

  List<String> unifiedSectionOrder = List<String>.from(UnifiedTableCustomization.defaultSectionOrder);
  Map<String, bool> unifiedVisibility = {};
  Map<String, bool> unifiedFieldVisibility = {};
  Map<String, Map<String, dynamic>> unifiedFieldLayouts = {};
  Map<String, String> unifiedLabels = {};
  String postSendPlacement = 'top', postSendVisibility = 'shared', postSendStyle = 'standard', postSendDetailStyle = 'official', postSendSort = 'newest';
  bool postSendShowEmployee = true, postSendShowBranch = true, postSendShowSummary = true, postSendShowStatus = true, postSendShowActions = true;
  double unifiedFontScale = 1, unifiedInputHeight = 52, unifiedRowHeight = 56, unifiedRadius = 12, unifiedSpacing = 10;
  bool unifiedTwoColumns = true;

  static const defaults = <String, String>{
    'appName': 'NEXORA', 'organizationName': 'مؤسسة الشاعري للتجارة العامة', 'tagline': 'Smart Business Management',
    'home': 'الرئيسية', 'tasks': 'المهام', 'employees': 'الموظفون', 'workSection': 'العمل والمتابعة', 'unifiedTable': 'الجدول الموحد لإنشاء المهام', 'taskManagement': 'إدارة المهام', 'reports': 'التقارير', 'dailyReports': 'التقارير اليومية المصممة', 'employeeReports': 'تقارير الموظف', 'adminSections': 'أقسام الإدارة', 'totalTasks': 'إجمالي المهام', 'inProgress': 'قيد التنفيذ', 'submitted': 'بانتظار المراجعة', 'lateTasks': 'مهام متأخرة',
  };

  Future<void> load() => _loaded ? Future<void>.value() : (_loadFuture ??= _loadOnce());
  Future<void> _loadOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _resetValues();
    } else {
      try { _apply(Map<String, dynamic>.from(jsonDecode(raw) as Map)); } catch (_) { _resetValues(); }
    }
    _migrateBranding();
    _repairUnifiedVisibility();
    _loaded = true;
    notifyListeners();
  }

  void _repairUnifiedVisibility() {
    if (unifiedSectionOrder.where(isUnifiedVisible).isEmpty) {
      unifiedVisibility = {'employee': true};
    }
    if (unifiedFieldVisibility.values.every((visible) => !visible)) {
      unifiedFieldVisibility = {'employeeField': true, 'roleField': true};
    }
  }

  void _migrateBranding() {
    if (labels['appName'] == 'مانجمنت' || labels['appName'] == 'برنامج الشاعري') {
      labels['appName'] = defaults['appName']!;
    }
    if (labels['tagline'] == 'معًا .. نحو إدارة أفضل') {
      labels['tagline'] = defaults['tagline']!;
    }
  }

  String label(String key) => labels[key] ?? defaults[key] ?? key;
  void setLabel(String key, String value) { labels[key] = value.trim().isEmpty ? (defaults[key] ?? key) : value.trim(); notifyListeners(); }
  void setVisibility(String key, bool value) { visibility[key] = value; notifyListeners(); }
  bool isVisible(String key) => visibility[key] ?? true;
  void addCard(String title, String description, int iconCode) { customCards.add({'title': title, 'description': description, 'icon': iconCode}); notifyListeners(); }
  void moveCard(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= customCards.length) return; newIndex = newIndex.clamp(0, customCards.length - 1).toInt(); final item = customCards.removeAt(oldIndex); customCards.insert(newIndex, item); notifyListeners(); }
  void setTheme({int? primary, int? accent, int? background, double? newRadius, String? newFontSize, String? newStatsStyle}) { if (primary != null) primaryColor = primary; if (accent != null) accentColor = accent; if (background != null) backgroundColor = background; if (newRadius != null) radius = newRadius; if (newFontSize != null) fontSize = newFontSize; if (newStatsStyle != null) statsStyle = newStatsStyle; notifyListeners(); }
  void setFieldStyle({String? style, int? fillColor, double? newRadius, double? newSpacing, String? labelSize}) { if (style != null) fieldStyle = style; if (fillColor != null) fieldFillColor = fillColor; if (newRadius != null) fieldRadius = newRadius; if (newSpacing != null) fieldSpacing = newSpacing; if (labelSize != null) fieldLabelSize = labelSize; notifyListeners(); }
  void moveField(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= fieldOrder.length) return; newIndex = newIndex.clamp(0, fieldOrder.length - 1).toInt(); final item = fieldOrder.removeAt(oldIndex); fieldOrder.insert(newIndex, item); notifyListeners(); }

  bool isUnifiedVisible(String key) => unifiedVisibility[key] ?? true;
  bool isUnifiedFieldVisible(String key) => unifiedFieldVisibility[key] ?? true;
  Map<String, dynamic> unifiedFieldLayout(String key) {
    final raw = unifiedFieldLayouts[key];
    final row = raw?['row'] is num ? (raw!['row'] as num).toInt() : int.tryParse('${raw?['row'] ?? 0}') ?? 0;
    final column = raw?['column'] is num ? (raw!['column'] as num).toInt() : int.tryParse('${raw?['column'] ?? 0}') ?? 0;
    final span = {'full', 'half', 'third'}.contains(raw?['span']) ? raw!['span'] : 'half';
    final align = {'right', 'center', 'left'}.contains(raw?['align']) ? raw!['align'] : 'right';
    return {'row': row.clamp(0, 99), 'column': column.clamp(0, 2), 'span': span, 'align': align};
  }
  void moveUnifiedField(String key, {int dx = 0, int dy = 0}) {
    final current = Map<String, dynamic>.from(unifiedFieldLayout(key));
    current['row'] = ((current['row'] as num?)?.toInt() ?? 0) + dy;
    current['column'] = ((current['column'] as num?)?.toInt() ?? 0) + dx;
    current['row'] = (current['row'] as int).clamp(0, 99);
    current['column'] = (current['column'] as int).clamp(0, 2);
    unifiedFieldLayouts[key] = current; notifyListeners();
  }
  void setUnifiedFieldLayout(String key, {String? span, String? align}) {
    final current = Map<String, dynamic>.from(unifiedFieldLayout(key));
    if (span != null && {'full', 'half', 'third'}.contains(span)) current['span'] = span;
    if (align != null && {'right', 'center', 'left'}.contains(align)) current['align'] = align;
    unifiedFieldLayouts[key] = current; notifyListeners();
  }
  String unifiedLabel(String key) => unifiedLabels[key] ?? UnifiedTableCustomization.defaults[key] ?? key;
  void setUnifiedVisibility(String key, bool value) {
    if (!value && isUnifiedVisible(key)) {
      final visibleCount = unifiedSectionOrder.where(isUnifiedVisible).length;
      if (visibleCount <= 1) return;
    }
    unifiedVisibility[key] = value;
    notifyListeners();
  }
  void setUnifiedFieldVisibility(String key, bool value) { unifiedFieldVisibility[key] = value; notifyListeners(); }
  void setUnifiedLabel(String key, String value) { unifiedLabels[key] = value.trim().isEmpty ? (UnifiedTableCustomization.defaults[key] ?? key) : value.trim(); notifyListeners(); }
  void moveUnifiedSection(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= unifiedSectionOrder.length) return; newIndex = newIndex.clamp(0, unifiedSectionOrder.length - 1).toInt(); final item = unifiedSectionOrder.removeAt(oldIndex); unifiedSectionOrder.insert(newIndex, item); notifyListeners(); }
  void setUnifiedLayout({double? fontScale, double? inputHeight, double? rowHeight, double? radius, double? spacing, bool? twoColumns}) { if (fontScale != null) unifiedFontScale = fontScale.clamp(.85, 1.35).toDouble(); if (inputHeight != null) unifiedInputHeight = inputHeight.clamp(40, 110).toDouble(); if (rowHeight != null) unifiedRowHeight = rowHeight.clamp(40, 120).toDouble(); if (radius != null) unifiedRadius = radius.clamp(6, 30).toDouble(); if (spacing != null) unifiedSpacing = spacing.clamp(4, 28).toDouble(); if (twoColumns != null) unifiedTwoColumns = twoColumns; notifyListeners(); }
  void setPostSend({String? placement, String? visibility, String? style, String? detailStyle, String? sort, bool? showEmployee, bool? showBranch, bool? showSummary, bool? showStatus, bool? showActions}) { if (placement != null) postSendPlacement = placement; if (visibility != null) postSendVisibility = visibility; if (style != null) postSendStyle = style; if (detailStyle != null) postSendDetailStyle = detailStyle; if (sort != null) postSendSort = sort; if (showEmployee != null) postSendShowEmployee = showEmployee; if (showBranch != null) postSendShowBranch = showBranch; if (showSummary != null) postSendShowSummary = showSummary; if (showStatus != null) postSendShowStatus = showStatus; if (showActions != null) postSendShowActions = showActions; notifyListeners(); }
  void resetUnified() { unifiedSectionOrder = List<String>.from(UnifiedTableCustomization.defaultSectionOrder); unifiedVisibility = {}; unifiedFieldVisibility = {}; unifiedFieldLayouts = {}; unifiedLabels = {}; postSendPlacement = 'top'; postSendVisibility = 'shared'; postSendStyle = 'standard'; postSendDetailStyle = 'official'; postSendSort = 'newest'; postSendShowEmployee = true; postSendShowBranch = true; postSendShowSummary = true; postSendShowStatus = true; postSendShowActions = true; unifiedFontScale = 1; unifiedInputHeight = 52; unifiedRowHeight = 56; unifiedRadius = 12; unifiedSpacing = 10; unifiedTwoColumns = true; notifyListeners(); }

  Map<String, dynamic> toJsonMap() => {'version': 2, 'labels': labels, 'visibility': visibility, 'customCards': customCards, 'fieldOrder': fieldOrder, 'fieldStyle': fieldStyle, 'fieldFillColor': fieldFillColor, 'fieldRadius': fieldRadius, 'fieldSpacing': fieldSpacing, 'fieldLabelSize': fieldLabelSize, 'theme': {'primaryColor': primaryColor, 'accentColor': accentColor, 'backgroundColor': backgroundColor, 'radius': radius, 'fontSize': fontSize, 'statsStyle': statsStyle}, 'unifiedTable': {'sectionOrder': unifiedSectionOrder, 'visibility': unifiedVisibility, 'fieldVisibility': unifiedFieldVisibility, 'fieldLayouts': unifiedFieldLayouts, 'labels': unifiedLabels, 'layout': {'fontScale': unifiedFontScale, 'inputHeight': unifiedInputHeight, 'rowHeight': unifiedRowHeight, 'radius': unifiedRadius, 'spacing': unifiedSpacing, 'twoColumns': unifiedTwoColumns}, 'postSend': {'placement': postSendPlacement, 'visibility': postSendVisibility, 'style': postSendStyle, 'detailStyle': postSendDetailStyle, 'sort': postSendSort, 'showEmployee': postSendShowEmployee, 'showBranch': postSendShowBranch, 'showSummary': postSendShowSummary, 'showStatus': postSendShowStatus, 'showActions': postSendShowActions}}};
  Future<void> save() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString(_storageKey, jsonEncode(toJsonMap())); notifyListeners(); }
  Future<void> importJson(String source) async { final decoded = jsonDecode(source); if (decoded is! Map) throw const FormatException('ملف الإعدادات غير صالح.'); _apply(Map<String, dynamic>.from(decoded)); await save(); }
  Future<void> reset({bool notify = true}) async { _resetValues(); if (notify) { final prefs = await SharedPreferences.getInstance(); await prefs.remove(_storageKey); notifyListeners(); } }

  void _resetValues() { labels = {}; visibility = {}; customCards = []; fieldOrder = ['title', 'description', 'status', 'date', 'attachment']; fieldStyle = 'outlined'; fieldFillColor = 0xFFFFFFFF; fieldRadius = 14; fieldSpacing = 10; fieldLabelSize = 'medium'; primaryColor = 0xFF0B3458; accentColor = 0xFFDBA62A; backgroundColor = 0xFFF5F7FD; radius = 16; fontSize = 'medium'; statsStyle = 'pastel'; unifiedSectionOrder = List<String>.from(UnifiedTableCustomization.defaultSectionOrder); unifiedVisibility = {}; unifiedFieldVisibility = {}; unifiedFieldLayouts = {}; unifiedLabels = {}; postSendPlacement = 'top'; postSendVisibility = 'shared'; postSendStyle = 'standard'; postSendDetailStyle = 'official'; postSendSort = 'newest'; postSendShowEmployee = true; postSendShowBranch = true; postSendShowSummary = true; postSendShowStatus = true; postSendShowActions = true; unifiedFontScale = 1; unifiedInputHeight = 52; unifiedRowHeight = 56; unifiedRadius = 12; unifiedSpacing = 10; unifiedTwoColumns = true; }
  void _apply(Map<String, dynamic> value) { labels = _stringMap(value['labels']); visibility = _boolMap(value['visibility']); customCards = (value['customCards'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); final importedOrder = (value['fieldOrder'] as List? ?? []).map((item) => '$item').where((item) => {'title', 'description', 'status', 'date', 'attachment'}.contains(item)).toList(); if (importedOrder.length == 5 && importedOrder.toSet().length == 5) fieldOrder = importedOrder; fieldStyle = '${value['fieldStyle'] ?? fieldStyle}'; fieldFillColor = _int(value['fieldFillColor'], fieldFillColor); fieldRadius = _num(value['fieldRadius'], fieldRadius).clamp(6, 30).toDouble(); fieldSpacing = _num(value['fieldSpacing'], fieldSpacing).clamp(4, 28).toDouble(); fieldLabelSize = '${value['fieldLabelSize'] ?? fieldLabelSize}'; final theme = value['theme'] is Map ? Map<String, dynamic>.from(value['theme'] as Map) : <String, dynamic>{}; primaryColor = _int(theme['primaryColor'], primaryColor); accentColor = _int(theme['accentColor'], accentColor); backgroundColor = _int(theme['backgroundColor'], backgroundColor); radius = _num(theme['radius'], radius).clamp(8, 30).toDouble(); fontSize = '${theme['fontSize'] ?? fontSize}'; statsStyle = '${theme['statsStyle'] ?? statsStyle}'; final unified = value['unifiedTable'] is Map ? Map<String, dynamic>.from(value['unifiedTable'] as Map) : <String, dynamic>{}; final order = (unified['sectionOrder'] as List? ?? []).map((item) => '$item').where(UnifiedTableCustomization.defaultSectionOrder.contains).toList(); if (order.length == UnifiedTableCustomization.defaultSectionOrder.length && order.toSet().length == order.length) unifiedSectionOrder = order; unifiedVisibility = _boolMap(unified['visibility']); unifiedFieldVisibility = _boolMap(unified['fieldVisibility']); unifiedFieldLayouts = _layoutMap(unified['fieldLayouts']); unifiedLabels = _stringMap(unified['labels']); final layout = unified['layout'] is Map ? Map<String, dynamic>.from(unified['layout'] as Map) : <String, dynamic>{}; unifiedFontScale = _num(layout['fontScale'], unifiedFontScale).clamp(.85, 1.35).toDouble(); unifiedInputHeight = _num(layout['inputHeight'], unifiedInputHeight).clamp(40, 110).toDouble(); unifiedRowHeight = _num(layout['rowHeight'], unifiedRowHeight).clamp(40, 120).toDouble(); unifiedRadius = _num(layout['radius'], unifiedRadius).clamp(6, 30).toDouble(); unifiedSpacing = _num(layout['spacing'], unifiedSpacing).clamp(4, 28).toDouble(); unifiedTwoColumns = layout['twoColumns'] is bool ? layout['twoColumns'] as bool : unifiedTwoColumns; final post = unified['postSend'] is Map ? Map<String, dynamic>.from(unified['postSend'] as Map) : <String, dynamic>{}; postSendPlacement = '${post['placement'] ?? postSendPlacement}'; postSendVisibility = '${post['visibility'] ?? postSendVisibility}'; postSendStyle = '${post['style'] ?? postSendStyle}'; postSendDetailStyle = '${post['detailStyle'] ?? postSendDetailStyle}'; postSendSort = '${post['sort'] ?? postSendSort}'; postSendShowEmployee = post['showEmployee'] is bool ? post['showEmployee'] as bool : postSendShowEmployee; postSendShowBranch = post['showBranch'] is bool ? post['showBranch'] as bool : postSendShowBranch; postSendShowSummary = post['showSummary'] is bool ? post['showSummary'] as bool : postSendShowSummary; postSendShowStatus = post['showStatus'] is bool ? post['showStatus'] as bool : postSendShowStatus; postSendShowActions = post['showActions'] is bool ? post['showActions'] as bool : postSendShowActions; }
  Map<String, String> _stringMap(dynamic value) => value is Map ? value.map((key, value) => MapEntry('$key', '$value')) : {};
  Map<String, bool> _boolMap(dynamic value) => value is Map ? value.map((key, value) => MapEntry('$key', value == true)) : {};
  Map<String, Map<String, dynamic>> _layoutMap(dynamic value) => value is Map ? value.map((key, value) => MapEntry('$key', value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{})) : {};
  int _int(dynamic value, int fallback) => value is num ? value.toInt() : fallback;
  double _num(dynamic value, double fallback) => value is num ? value.toDouble() : fallback;
}

class UnifiedTableCustomization {
  static const defaultSectionOrder = ['sent', 'employee', 'purpose', 'hours', 'daily', 'exception', 'report', 'lists', 'kpi', 'notes', 'approval'];
  static const defaults = <String, String>{'screenTitle': 'الجدول الموحد لإنشاء المهام', 'screenSubtitle': 'إنشاء منظم وإرسال مباشر للموظف', 'sent': 'الجداول الموحدة المرسلة', 'back': 'العودة إلى الرئيسية', 'employee': 'بيانات الموظف والاعتماد', 'purpose': 'الهدف من الوظيفة', 'purposeHint': 'اكتب الهدف العام من الوظيفة', 'hours': 'ساعات الدوام الرسمية', 'daily': 'الجدول الزمني اليومي', 'exception': 'العمل الاستثنائي', 'report': 'قالب التقرير اليومي', 'lists': 'البنود التنظيمية', 'kpi': 'مؤشرات تقييم الأداء', 'notes': 'ملاحظات وتعليمات للإدارة أو الموظف', 'approval': 'حالة الاعتماد', 'time': 'الوقت', 'task': 'المهمة المحددة والمسؤولية', 'output': 'المخرج المطلوب', 'employeeField': 'الموظف أو المجموعة', 'roleField': 'المسمى الوظيفي', 'branchField': 'الفرع', 'startDate': 'تاريخ بدء التطبيق'};
}
