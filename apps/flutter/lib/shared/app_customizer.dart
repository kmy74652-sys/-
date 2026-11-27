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

  // إعدادات هوية وتصميم التقارير المصدرة، مع fallback إلى تصميم NEXORA.
  String reportCompanyName = 'مؤسسة الشاعري للتجارة العامة';
  String reportBranchName = '', reportPhone = '', reportEmail = '', reportAddress = '';
  String reportHeaderText = '', reportFooterText = 'NEXORA';
  String reportLogoPosition = 'right', reportHeaderStyle = 'band', reportTableStyle = 'full';
  int reportPrimaryColor = 0xFF0B3458, reportHeadingColor = 0xFF123B5D;
  double reportLogoSize = 54, reportFontSize = 10;
  bool reportShowExportDate = true, reportShowEmployee = true, reportShowBranch = true;
  bool reportShowStatus = true, reportShowNumber = true, reportShowSignature = true, reportShowFooter = true;
  String reportLogoUrl = '';
  List<String> reportHeaderOrder = [
    'company', 'branchName', 'phone', 'email', 'address', 'headerText',
    'title', 'employee', 'taskBranch', 'status', 'number', 'exportDate',
  ];
  Map<String, Map<String, dynamic>> reportHeaderLayouts = {};
  Map<String, Map<String, dynamic>> reportCustomElements = {};
  Map<String, Map<String, double>> reportElementPositions = {};

  List<String> unifiedSectionOrder = List<String>.from(UnifiedTableCustomization.defaultSectionOrder);
  Map<String, bool> unifiedVisibility = {};
  Map<String, bool> unifiedFieldVisibility = {};
  Map<String, Map<String, dynamic>> unifiedFieldLayouts = {};
  Map<String, String> unifiedLabels = {};
  String postSendPlacement = 'top', postSendVisibility = 'shared', postSendStyle = 'standard', postSendDetailStyle = 'official', postSendSort = 'newest';
  bool postSendShowEmployee = true, postSendShowBranch = true, postSendShowSummary = true, postSendShowStatus = true, postSendShowActions = true;
  double unifiedFontScale = 1, unifiedInputHeight = 52, unifiedRowHeight = 56, unifiedRadius = 12, unifiedSpacing = 10;
  bool unifiedTwoColumns = true;
  List<String> unifiedScheduleColumns = ['time', 'task', 'output'];
  int unifiedSchedulePreviewRows = 1;

  static const defaults = <String, String>{
    'appName': 'NEXORA', 'organizationName': 'مؤسسة الشاعري للتجارة العامة', 'tagline': 'Smart Business Management',
    'home': 'الرئيسية', 'tasks': 'المهام', 'independentTasks': 'المهام المستقلة', 'employees': 'الموظفون', 'activity': 'سجل النشاط', 'report-designer': 'مصمم التقارير', 'customizer': 'مصمم الواجهات والتحكم الشامل', 'hr': 'الموارد البشرية', 'workSection': 'العمل والمتابعة', 'unifiedTable': 'الجدول الموحد لإنشاء المهام', 'taskManagement': 'إدارة مهام الجداول الموحدة', 'reports': 'تقارير الموظفين', 'performance': 'إحصائيات ومقارنة الأداء', 'dailyReports': 'التقارير اليومية المصممة', 'employeeReports': 'تقارير الموظف', 'adminSections': 'أقسام الإدارة', 'settings': 'الإعدادات', 'totalTasks': 'إجمالي المهام', 'inProgress': 'قيد التنفيذ', 'submitted': 'بانتظار المراجعة', 'lateTasks': 'مهام متأخرة',
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
  void updateCustomCard(Map<String, dynamic> card, String field, String value) { card[field] = value; notifyListeners(); }
  void moveCard(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= customCards.length) return; newIndex = newIndex.clamp(0, customCards.length - 1).toInt(); final item = customCards.removeAt(oldIndex); customCards.insert(newIndex, item); notifyListeners(); }
  void setTheme({int? primary, int? accent, int? background, double? newRadius, String? newFontSize, String? newStatsStyle}) { if (primary != null) primaryColor = primary; if (accent != null) accentColor = accent; if (background != null) backgroundColor = background; if (newRadius != null) radius = newRadius; if (newFontSize != null) fontSize = newFontSize; if (newStatsStyle != null) statsStyle = newStatsStyle; notifyListeners(); }
  void setReportTheme({String? companyName, String? branchName, String? phone, String? email, String? address, String? headerText, String? footerText, String? logoPosition, String? headerStyle, String? tableStyle, int? primaryColor, int? headingColor, double? logoSize, double? fontSize, bool? showExportDate, bool? showEmployee, bool? showBranch, bool? showStatus, bool? showNumber, bool? showSignature, bool? showFooter, String? logoUrl}) {
    if (companyName != null) reportCompanyName = companyName; if (branchName != null) reportBranchName = branchName;
    if (phone != null) reportPhone = phone; if (email != null) reportEmail = email; if (address != null) reportAddress = address;
    if (headerText != null) reportHeaderText = headerText; if (footerText != null) reportFooterText = footerText;
    if (logoPosition != null && {'right', 'center', 'left'}.contains(logoPosition)) reportLogoPosition = logoPosition;
    if (headerStyle != null && {'band', 'minimal', 'boxed'}.contains(headerStyle)) reportHeaderStyle = headerStyle;
    if (tableStyle != null && {'simple', 'full', 'colored'}.contains(tableStyle)) reportTableStyle = tableStyle;
    if (primaryColor != null) reportPrimaryColor = primaryColor; if (headingColor != null) reportHeadingColor = headingColor;
    if (logoSize != null) reportLogoSize = logoSize.clamp(28, 110).toDouble(); if (fontSize != null) reportFontSize = fontSize.clamp(8, 16).toDouble();
    if (showExportDate != null) reportShowExportDate = showExportDate; if (showEmployee != null) reportShowEmployee = showEmployee; if (showBranch != null) reportShowBranch = showBranch;
    if (showStatus != null) reportShowStatus = showStatus; if (showNumber != null) reportShowNumber = showNumber; if (showSignature != null) reportShowSignature = showSignature; if (showFooter != null) reportShowFooter = showFooter; if (logoUrl != null) reportLogoUrl = logoUrl;
    notifyListeners();
  }
  void setFieldStyle({String? style, int? fillColor, double? newRadius, double? newSpacing, String? labelSize}) { if (style != null) fieldStyle = style; if (fillColor != null) fieldFillColor = fillColor; if (newRadius != null) fieldRadius = newRadius; if (newSpacing != null) fieldSpacing = newSpacing; if (labelSize != null) fieldLabelSize = labelSize; notifyListeners(); }
  void moveField(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= fieldOrder.length) return; newIndex = newIndex.clamp(0, fieldOrder.length - 1).toInt(); final item = fieldOrder.removeAt(oldIndex); fieldOrder.insert(newIndex, item); notifyListeners(); }
  void moveReportHeaderItem(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= reportHeaderOrder.length) return; newIndex = newIndex.clamp(0, reportHeaderOrder.length - 1).toInt(); final item = reportHeaderOrder.removeAt(oldIndex); reportHeaderOrder.insert(newIndex, item); notifyListeners(); }
  Map<String, dynamic> reportHeaderLayout(String key) {
    final raw = reportHeaderLayouts[key];
    final align = {'right', 'center', 'left'}.contains(raw?['align']) ? raw!['align'] : 'right';
    final size = raw?['size'] is num ? (raw!['size'] as num).toDouble() : 10.0;
    final x = raw?['x'] is num ? (raw!['x'] as num).toDouble() : 0.0;
    final y = raw?['y'] is num ? (raw!['y'] as num).toDouble() : 0.0;
    return {'align': align, 'size': size.clamp(7, 32).toDouble(), 'x': x.clamp(-40, 40).toDouble(), 'y': y.clamp(-20, 20).toDouble()};
  }
  void setReportHeaderLayout(String key, {String? align, double? size, double? x, double? y}) {
    final current = Map<String, dynamic>.from(reportHeaderLayout(key));
    if (align != null && {'right', 'center', 'left'}.contains(align)) current['align'] = align;
    if (size != null) current['size'] = size.clamp(7, 32).toDouble();
    if (x != null) current['x'] = x.clamp(-40, 40).toDouble();
    if (y != null) current['y'] = y.clamp(-20, 20).toDouble();
    reportHeaderLayouts[key] = current;
    notifyListeners();
  }
  void setReportElementPosition(String key, {double? left, double? top, double? width, double? height}) {
    final current = Map<String, double>.from(reportElementPositions[key] ?? const {});
    if (left != null) current['left'] = left.clamp(0, 1).toDouble();
    if (top != null) current['top'] = top.clamp(0, 1).toDouble();
    if (width != null) current['width'] = width.clamp(.08, .95).toDouble();
    if (height != null) current['height'] = height.clamp(.02, .35).toDouble();
    reportElementPositions[key] = current;
    notifyListeners();
  }
  Map<String, double> reportElementPosition(String key) {
    final raw = reportElementPositions[key] ?? const <String, double>{};
    return {'left': (raw['left'] ?? .08).clamp(0, 1).toDouble(), 'top': (raw['top'] ?? .06).clamp(0, 1).toDouble(), 'width': (raw['width'] ?? .84).clamp(.08, .95).toDouble(), 'height': (raw['height'] ?? .06).clamp(.02, .35).toDouble()};
  }
  String addReportCustomElement({String type = 'text', String text = 'عنصر جديد'}) {
    final key = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    reportCustomElements[key] = {'type': type, 'text': text, 'name': type == 'logo' ? 'الشعار' : text, 'size': 12.0, 'color': reportHeadingColor, 'shape': 'plain', 'visible': true};
    setReportElementPosition(key, left: .08, top: .30, width: .84, height: type == 'logo' ? .12 : .06);
    return key;
  }
  void updateReportCustomElement(String key, {String? name, String? text, double? size, int? color, String? shape, bool? visible}) {
    final current = reportCustomElements[key];
    if (current == null) return;
    if (name != null) current['name'] = name;
    if (text != null) current['text'] = text;
    if (size != null) current['size'] = size.clamp(7, 32).toDouble();
    if (color != null) current['color'] = color;
    if (shape != null) current['shape'] = shape;
    if (visible != null) current['visible'] = visible;
    notifyListeners();
  }
  void removeReportCustomElement(String key) { reportCustomElements.remove(key); reportElementPositions.remove(key); notifyListeners(); }

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
  String addUnifiedScheduleColumn() {
    final key = 'customColumn_${DateTime.now().microsecondsSinceEpoch}';
    unifiedScheduleColumns.add(key);
    unifiedLabels[key] = 'عمود جديد';
    notifyListeners();
    return key;
  }
  void removeUnifiedScheduleColumn(String key) {
    if (unifiedScheduleColumns.length <= 1) return;
    unifiedScheduleColumns.remove(key);
    notifyListeners();
  }
  void addUnifiedSchedulePreviewRow() { if (unifiedSchedulePreviewRows < 20) unifiedSchedulePreviewRows++; notifyListeners(); }
  void removeUnifiedSchedulePreviewRow() { if (unifiedSchedulePreviewRows > 1) unifiedSchedulePreviewRows--; notifyListeners(); }
  void moveUnifiedSection(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= unifiedSectionOrder.length) return; newIndex = newIndex.clamp(0, unifiedSectionOrder.length - 1).toInt(); final item = unifiedSectionOrder.removeAt(oldIndex); unifiedSectionOrder.insert(newIndex, item); notifyListeners(); }
  void setUnifiedLayout({double? fontScale, double? inputHeight, double? rowHeight, double? radius, double? spacing, bool? twoColumns}) { if (fontScale != null) unifiedFontScale = fontScale.clamp(.85, 1.35).toDouble(); if (inputHeight != null) unifiedInputHeight = inputHeight.clamp(40, 110).toDouble(); if (rowHeight != null) unifiedRowHeight = rowHeight.clamp(40, 120).toDouble(); if (radius != null) unifiedRadius = radius.clamp(6, 30).toDouble(); if (spacing != null) unifiedSpacing = spacing.clamp(4, 28).toDouble(); if (twoColumns != null) unifiedTwoColumns = twoColumns; notifyListeners(); }
  void setPostSend({String? placement, String? visibility, String? style, String? detailStyle, String? sort, bool? showEmployee, bool? showBranch, bool? showSummary, bool? showStatus, bool? showActions}) { if (placement != null) postSendPlacement = placement; if (visibility != null) postSendVisibility = visibility; if (style != null) postSendStyle = style; if (detailStyle != null) postSendDetailStyle = detailStyle; if (sort != null) postSendSort = sort; if (showEmployee != null) postSendShowEmployee = showEmployee; if (showBranch != null) postSendShowBranch = showBranch; if (showSummary != null) postSendShowSummary = showSummary; if (showStatus != null) postSendShowStatus = showStatus; if (showActions != null) postSendShowActions = showActions; notifyListeners(); }
  void resetUnified() { unifiedSectionOrder = List<String>.from(UnifiedTableCustomization.defaultSectionOrder); unifiedVisibility = {}; unifiedFieldVisibility = {}; unifiedFieldLayouts = {}; unifiedLabels = {}; unifiedScheduleColumns = ['time', 'task', 'output']; unifiedSchedulePreviewRows = 1; postSendPlacement = 'top'; postSendVisibility = 'shared'; postSendStyle = 'standard'; postSendDetailStyle = 'official'; postSendSort = 'newest'; postSendShowEmployee = true; postSendShowBranch = true; postSendShowSummary = true; postSendShowStatus = true; postSendShowActions = true; unifiedFontScale = 1; unifiedInputHeight = 52; unifiedRowHeight = 56; unifiedRadius = 12; unifiedSpacing = 10; unifiedTwoColumns = true; notifyListeners(); }

  Map<String, dynamic> toJsonMap() => {'version': 5, 'labels': labels, 'visibility': visibility, 'customCards': customCards, 'fieldOrder': fieldOrder, 'fieldStyle': fieldStyle, 'fieldFillColor': fieldFillColor, 'fieldRadius': fieldRadius, 'fieldSpacing': fieldSpacing, 'fieldLabelSize': fieldLabelSize, 'theme': {'primaryColor': primaryColor, 'accentColor': accentColor, 'backgroundColor': backgroundColor, 'radius': radius, 'fontSize': fontSize, 'statsStyle': statsStyle}, 'reportTheme': {'companyName': reportCompanyName, 'branchName': reportBranchName, 'phone': reportPhone, 'email': reportEmail, 'address': reportAddress, 'headerText': reportHeaderText, 'footerText': reportFooterText, 'logoPosition': reportLogoPosition, 'headerStyle': reportHeaderStyle, 'tableStyle': reportTableStyle, 'primaryColor': reportPrimaryColor, 'headingColor': reportHeadingColor, 'logoSize': reportLogoSize, 'fontSize': reportFontSize, 'showExportDate': reportShowExportDate, 'showEmployee': reportShowEmployee, 'showBranch': reportShowBranch, 'showStatus': reportShowStatus, 'showNumber': reportShowNumber, 'showSignature': reportShowSignature, 'showFooter': reportShowFooter, 'logoUrl': reportLogoUrl, 'headerOrder': reportHeaderOrder, 'elementLayouts': reportHeaderLayouts, 'customElements': reportCustomElements, 'elementPositions': reportElementPositions}, 'unifiedTable': {'sectionOrder': unifiedSectionOrder, 'visibility': unifiedVisibility, 'fieldVisibility': unifiedFieldVisibility, 'fieldLayouts': unifiedFieldLayouts, 'labels': unifiedLabels, 'scheduleColumns': unifiedScheduleColumns, 'previewRows': unifiedSchedulePreviewRows, 'layout': {'fontScale': unifiedFontScale, 'inputHeight': unifiedInputHeight, 'rowHeight': unifiedRowHeight, 'radius': unifiedRadius, 'spacing': unifiedSpacing, 'twoColumns': unifiedTwoColumns}, 'postSend': {'placement': postSendPlacement, 'visibility': postSendVisibility, 'style': postSendStyle, 'detailStyle': postSendDetailStyle, 'sort': postSendSort, 'showEmployee': postSendShowEmployee, 'showBranch': postSendShowBranch, 'showSummary': postSendShowSummary, 'showStatus': postSendShowStatus, 'showActions': postSendShowActions}}};
  Future<void> save() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString(_storageKey, jsonEncode(toJsonMap())); notifyListeners(); }
  Future<void> importJson(String source) async { final decoded = jsonDecode(source); if (decoded is! Map) throw const FormatException('ملف الإعدادات غير صالح.'); _apply(Map<String, dynamic>.from(decoded)); await save(); }
  Future<void> reset({bool notify = true}) async { _resetValues(); if (notify) { final prefs = await SharedPreferences.getInstance(); await prefs.remove(_storageKey); notifyListeners(); } }

  void _resetValues() { labels = {}; visibility = {}; customCards = []; fieldOrder = ['title', 'description', 'status', 'date', 'attachment']; fieldStyle = 'outlined'; fieldFillColor = 0xFFFFFFFF; fieldRadius = 14; fieldSpacing = 10; fieldLabelSize = 'medium'; primaryColor = 0xFF0B3458; accentColor = 0xFFDBA62A; backgroundColor = 0xFFF5F7FD; radius = 16; fontSize = 'medium'; statsStyle = 'pastel'; reportCompanyName = 'مؤسسة الشاعري للتجارة العامة'; reportBranchName = ''; reportPhone = ''; reportEmail = ''; reportAddress = ''; reportHeaderText = ''; reportFooterText = 'NEXORA'; reportLogoPosition = 'right'; reportHeaderStyle = 'band'; reportTableStyle = 'full'; reportPrimaryColor = 0xFF0B3458; reportHeadingColor = 0xFF123B5D; reportLogoSize = 54; reportFontSize = 10; reportShowExportDate = true; reportShowEmployee = true; reportShowBranch = true; reportShowStatus = true; reportShowNumber = true; reportShowSignature = true; reportShowFooter = true; reportLogoUrl = ''; reportHeaderOrder = ['company', 'branchName', 'phone', 'email', 'address', 'headerText', 'title', 'employee', 'taskBranch', 'status', 'number', 'exportDate']; reportHeaderLayouts = {}; reportCustomElements = {}; reportElementPositions = {}; unifiedSectionOrder = List<String>.from(UnifiedTableCustomization.defaultSectionOrder); unifiedVisibility = {}; unifiedFieldVisibility = {}; unifiedFieldLayouts = {}; unifiedLabels = {}; unifiedScheduleColumns = ['time', 'task', 'output']; unifiedSchedulePreviewRows = 1; postSendPlacement = 'top'; postSendVisibility = 'shared'; postSendStyle = 'standard'; postSendDetailStyle = 'official'; postSendSort = 'newest'; postSendShowEmployee = true; postSendShowBranch = true; postSendShowSummary = true; postSendShowStatus = true; postSendShowActions = true; unifiedFontScale = 1; unifiedInputHeight = 52; unifiedRowHeight = 56; unifiedRadius = 12; unifiedSpacing = 10; unifiedTwoColumns = true; }
  void _apply(Map<String, dynamic> value) { labels = _stringMap(value['labels']); visibility = _boolMap(value['visibility']); customCards = (value['customCards'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); final importedOrder = (value['fieldOrder'] as List? ?? []).map((item) => '$item').where((item) => {'title', 'description', 'status', 'date', 'attachment'}.contains(item)).toList(); if (importedOrder.length == 5 && importedOrder.toSet().length == 5) fieldOrder = importedOrder; fieldStyle = '${value['fieldStyle'] ?? fieldStyle}'; fieldFillColor = _int(value['fieldFillColor'], fieldFillColor); fieldRadius = _num(value['fieldRadius'], fieldRadius).clamp(6, 30).toDouble(); fieldSpacing = _num(value['fieldSpacing'], fieldSpacing).clamp(4, 28).toDouble(); fieldLabelSize = '${value['fieldLabelSize'] ?? fieldLabelSize}'; final theme = value['theme'] is Map ? Map<String, dynamic>.from(value['theme'] as Map) : <String, dynamic>{}; primaryColor = _int(theme['primaryColor'], primaryColor); accentColor = _int(theme['accentColor'], accentColor); backgroundColor = _int(theme['backgroundColor'], backgroundColor); radius = _num(theme['radius'], radius).clamp(8, 30).toDouble(); fontSize = '${theme['fontSize'] ?? fontSize}'; statsStyle = '${theme['statsStyle'] ?? statsStyle}'; final report = value['reportTheme'] is Map ? Map<String, dynamic>.from(value['reportTheme'] as Map) : <String, dynamic>{}; reportCompanyName = '${report['companyName'] ?? reportCompanyName}'; reportBranchName = '${report['branchName'] ?? reportBranchName}'; reportPhone = '${report['phone'] ?? reportPhone}'; reportEmail = '${report['email'] ?? reportEmail}'; reportAddress = '${report['address'] ?? reportAddress}'; reportHeaderText = '${report['headerText'] ?? reportHeaderText}'; reportFooterText = '${report['footerText'] ?? reportFooterText}'; reportLogoPosition = '${report['logoPosition'] ?? reportLogoPosition}'; reportHeaderStyle = '${report['headerStyle'] ?? reportHeaderStyle}'; reportTableStyle = '${report['tableStyle'] ?? reportTableStyle}'; reportPrimaryColor = _int(report['primaryColor'], reportPrimaryColor); reportHeadingColor = _int(report['headingColor'], reportHeadingColor); reportLogoSize = _num(report['logoSize'], reportLogoSize).clamp(28, 110).toDouble(); reportFontSize = _num(report['fontSize'], reportFontSize).clamp(8, 16).toDouble(); reportShowExportDate = report['showExportDate'] is bool ? report['showExportDate'] as bool : reportShowExportDate; reportShowEmployee = report['showEmployee'] is bool ? report['showEmployee'] as bool : reportShowEmployee; reportShowBranch = report['showBranch'] is bool ? report['showBranch'] as bool : reportShowBranch; reportShowStatus = report['showStatus'] is bool ? report['showStatus'] as bool : reportShowStatus; reportShowNumber = report['showNumber'] is bool ? report['showNumber'] as bool : reportShowNumber; reportShowSignature = report['showSignature'] is bool ? report['showSignature'] as bool : reportShowSignature; reportShowFooter = report['showFooter'] is bool ? report['showFooter'] as bool : reportShowFooter; reportLogoUrl = '${report['logoUrl'] ?? reportLogoUrl}'; final importedHeaderOrder = (report['headerOrder'] as List? ?? []).map((item) => '$item').where((item) => {'company', 'branchName', 'phone', 'email', 'address', 'headerText', 'title', 'employee', 'taskBranch', 'status', 'number', 'exportDate'}.contains(item)).toList(); if (importedHeaderOrder.length == 12 && importedHeaderOrder.toSet().length == 12) reportHeaderOrder = importedHeaderOrder; reportHeaderLayouts = _layoutMap(report['elementLayouts']); reportCustomElements = _layoutMap(report['customElements']); reportElementPositions = _positionMap(report['elementPositions']); final unified = value['unifiedTable'] is Map ? Map<String, dynamic>.from(value['unifiedTable'] as Map) : <String, dynamic>{}; final order = (unified['sectionOrder'] as List? ?? []).map((item) => '$item').where(UnifiedTableCustomization.defaultSectionOrder.contains).toList(); if (order.length == UnifiedTableCustomization.defaultSectionOrder.length && order.toSet().length == order.length) unifiedSectionOrder = order; unifiedVisibility = _boolMap(unified['visibility']); unifiedFieldVisibility = _boolMap(unified['fieldVisibility']); unifiedFieldLayouts = _layoutMap(unified['fieldLayouts']); unifiedLabels = _stringMap(unified['labels']); final importedColumns = (unified['scheduleColumns'] as List? ?? []).map((item) => '$item').where((item) => item.trim().isNotEmpty).toList(); if (importedColumns.isNotEmpty) unifiedScheduleColumns = importedColumns; unifiedSchedulePreviewRows = _int(unified['previewRows'], unifiedSchedulePreviewRows).clamp(1, 20).toInt(); final layout = unified['layout'] is Map ? Map<String, dynamic>.from(unified['layout'] as Map) : <String, dynamic>{}; unifiedFontScale = _num(layout['fontScale'], unifiedFontScale).clamp(.85, 1.35).toDouble(); unifiedInputHeight = _num(layout['inputHeight'], unifiedInputHeight).clamp(40, 110).toDouble(); unifiedRowHeight = _num(layout['rowHeight'], unifiedRowHeight).clamp(40, 120).toDouble(); unifiedRadius = _num(layout['radius'], unifiedRadius).clamp(6, 30).toDouble(); unifiedSpacing = _num(layout['spacing'], unifiedSpacing).clamp(4, 28).toDouble(); unifiedTwoColumns = layout['twoColumns'] is bool ? layout['twoColumns'] as bool : unifiedTwoColumns; final post = unified['postSend'] is Map ? Map<String, dynamic>.from(unified['postSend'] as Map) : <String, dynamic>{}; postSendPlacement = '${post['placement'] ?? postSendPlacement}'; postSendVisibility = '${post['visibility'] ?? postSendVisibility}'; postSendStyle = '${post['style'] ?? postSendStyle}'; postSendDetailStyle = '${post['detailStyle'] ?? postSendDetailStyle}'; postSendSort = '${post['sort'] ?? postSendSort}'; postSendShowEmployee = post['showEmployee'] is bool ? post['showEmployee'] as bool : postSendShowEmployee; postSendShowBranch = post['showBranch'] is bool ? post['showBranch'] as bool : postSendShowBranch; postSendShowSummary = post['showSummary'] is bool ? post['showSummary'] as bool : postSendShowSummary; postSendShowStatus = post['showStatus'] is bool ? post['showStatus'] as bool : postSendShowStatus; postSendShowActions = post['showActions'] is bool ? post['showActions'] as bool : postSendShowActions; }
  Map<String, String> _stringMap(dynamic value) => value is Map ? value.map((key, value) => MapEntry('$key', '$value')) : {};
  Map<String, bool> _boolMap(dynamic value) => value is Map ? value.map((key, value) => MapEntry('$key', value == true)) : {};
  Map<String, Map<String, dynamic>> _layoutMap(dynamic value) => value is Map ? value.map((key, value) => MapEntry('$key', value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{})) : {};
  Map<String, Map<String, double>> _positionMap(dynamic value) => value is Map ? value.map((key, value) => MapEntry('$key', value is Map ? value.map((k, v) => MapEntry('$k', v is num ? v.toDouble() : 0.0)) : <String, double>{})) : {};
  int _int(dynamic value, int fallback) => value is num ? value.toInt() : fallback;
  double _num(dynamic value, double fallback) => value is num ? value.toDouble() : fallback;
}

class UnifiedTableCustomization {
  static const defaultSectionOrder = ['sent', 'employee', 'purpose', 'hours', 'daily', 'exception', 'report', 'lists', 'kpi', 'notes', 'approval'];
  static const defaults = <String, String>{'screenTitle': 'الجدول الموحد لإنشاء المهام', 'screenSubtitle': 'إنشاء منظم وإرسال مباشر للموظف', 'sent': 'الجداول الموحدة المرسلة', 'back': 'العودة إلى الرئيسية', 'employee': 'بيانات الموظف والاعتماد', 'purpose': 'الهدف من الوظيفة', 'purposeHint': 'اكتب الهدف العام من الوظيفة', 'hours': 'ساعات الدوام الرسمية', 'daily': 'الجدول الزمني اليومي', 'exception': 'العمل الاستثنائي', 'report': 'قالب التقرير اليومي', 'lists': 'البنود التنظيمية', 'kpi': 'مؤشرات تقييم الأداء', 'notes': 'ملاحظات وتعليمات للإدارة أو الموظف', 'approval': 'حالة الاعتماد', 'time': 'الوقت', 'task': 'المهمة المحددة والمسؤولية', 'output': 'المخرج المطلوب', 'employeeField': 'الموظف أو المجموعة', 'roleField': 'المسمى الوظيفي', 'branchField': 'الفرع', 'startDate': 'تاريخ بدء التطبيق'};
}
