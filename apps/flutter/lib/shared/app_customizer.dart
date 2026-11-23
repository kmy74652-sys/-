import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCustomizer extends ChangeNotifier {
  AppCustomizer._();
  static final instance = AppCustomizer._();

  static const _storageKey = 'alshaeri_app_customizer_v1';
  bool _loaded = false;
  Map<String, String> labels = {};
  Map<String, bool> visibility = {};
  List<Map<String, dynamic>> customCards = [];
  int primaryColor = 0xFF0B3458;
  int accentColor = 0xFFDBA62A;
  int backgroundColor = 0xFFF5F7FD;
  double radius = 16;
  String fontSize = 'medium';
  String statsStyle = 'pastel';

  static const defaults = <String, String>{
    'appName': 'مانجمنت',
    'organizationName': 'مؤسسة الشاعري للتجارة العامة',
    'tagline': 'معًا .. نحو إدارة أفضل',
    'home': 'الرئيسية',
    'tasks': 'المهام',
    'employees': 'الموظفون',
    'workSection': 'العمل والمتابعة',
    'unifiedTable': 'الجدول الموحد لإنشاء المهام',
    'taskManagement': 'إدارة المهام',
    'reports': 'التقارير',
    'dailyReports': 'التقارير اليومية المصممة',
    'employeeReports': 'تقارير الموظف',
    'adminSections': 'أقسام الإدارة',
    'totalTasks': 'إجمالي المهام',
    'inProgress': 'قيد التنفيذ',
    'submitted': 'بانتظار المراجعة',
    'lateTasks': 'مهام متأخرة',
  };

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _apply(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        reset(notify: false);
      }
    } else {
      reset(notify: false);
    }
    notifyListeners();
  }

  String label(String key) => labels[key] ?? defaults[key] ?? key;

  void setLabel(String key, String value) {
    labels[key] = value.trim().isEmpty ? (defaults[key] ?? key) : value.trim();
    notifyListeners();
  }

  void setVisibility(String key, bool value) {
    visibility[key] = value;
    notifyListeners();
  }

  bool isVisible(String key) => visibility[key] ?? true;

  void setTheme({int? primary, int? accent, int? background, double? newRadius,
      String? newFontSize, String? newStatsStyle}) {
    if (primary != null) primaryColor = primary;
    if (accent != null) accentColor = accent;
    if (background != null) backgroundColor = background;
    if (newRadius != null) radius = newRadius;
    if (newFontSize != null) fontSize = newFontSize;
    if (newStatsStyle != null) statsStyle = newStatsStyle;
    notifyListeners();
  }

  void addCard(String title, String description, int iconCode) {
    customCards.add({'title': title, 'description': description, 'icon': iconCode});
    notifyListeners();
  }

  void moveCard(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= customCards.length) return;
    if (newIndex > oldIndex) newIndex--;
    newIndex = newIndex.clamp(0, customCards.length - 1).toInt();
    final item = customCards.removeAt(oldIndex);
    customCards.insert(newIndex, item);
    notifyListeners();
  }

  Map<String, dynamic> toJsonMap() => {
        'version': 1,
        'labels': labels,
        'visibility': visibility,
        'customCards': customCards,
        'theme': {
          'primaryColor': primaryColor,
          'accentColor': accentColor,
          'backgroundColor': backgroundColor,
          'radius': radius,
          'fontSize': fontSize,
          'statsStyle': statsStyle,
        },
      };

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(toJsonMap()));
    notifyListeners();
  }

  Future<void> importJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('ملف الإعدادات غير صالح.');
    _apply(Map<String, dynamic>.from(decoded));
    await save();
  }

  Future<void> reset({bool notify = true}) async {
    labels = {};
    visibility = {};
    customCards = [];
    primaryColor = 0xFF0B3458;
    accentColor = 0xFFDBA62A;
    backgroundColor = 0xFFF5F7FD;
    radius = 16;
    fontSize = 'medium';
    statsStyle = 'pastel';
    if (notify) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      notifyListeners();
    }
  }

  void _apply(Map<String, dynamic> value) {
    labels = _stringMap(value['labels']);
    visibility = _boolMap(value['visibility']);
    customCards = (value['customCards'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final theme = value['theme'] is Map
        ? Map<String, dynamic>.from(value['theme'] as Map)
        : <String, dynamic>{};
    primaryColor = _int(theme['primaryColor'], primaryColor);
    accentColor = _int(theme['accentColor'], accentColor);
    backgroundColor = _int(theme['backgroundColor'], backgroundColor);
    radius = (theme['radius'] is num ? (theme['radius'] as num).toDouble() : radius)
        .clamp(8, 30);
    fontSize = '${theme['fontSize'] ?? fontSize}';
    statsStyle = '${theme['statsStyle'] ?? statsStyle}';
  }

  Map<String, String> _stringMap(dynamic value) => value is Map
      ? value.map((key, value) => MapEntry('$key', '$value'))
      : {};
  Map<String, bool> _boolMap(dynamic value) => value is Map
      ? value.map((key, value) => MapEntry('$key', value == true))
      : {};
  int _int(dynamic value, int fallback) => value is num ? value.toInt() : fallback;
}
