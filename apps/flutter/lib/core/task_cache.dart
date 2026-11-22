import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CachedTasks {
  const CachedTasks({required this.tasks, required this.savedAt});

  final List<Map<String, dynamic>> tasks;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.toUtc().toIso8601String(),
        'tasks': tasks,
      };

  static CachedTasks? fromJson(dynamic value) {
    if (value is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(value);
      final savedAt = DateTime.tryParse('${map['savedAt'] ?? ''}');
      final rawTasks = map['tasks'];
      if (savedAt == null || rawTasks is! List) return null;
      final tasks = rawTasks
          .whereType<Map>()
          .map((task) => Map<String, dynamic>.from(task))
          .toList();
      return CachedTasks(tasks: tasks, savedAt: savedAt.toUtc());
    } catch (_) {
      return null;
    }
  }
}

class TaskCache {
  TaskCache._();

  static const _keyPrefix = '@alshaeri/tasks-cache/v1/';

  static String _key(String uid) => '$_keyPrefix$uid';

  static Future<void> save(
    String uid,
    List<Map<String, dynamic>> tasks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(uid),
      jsonEncode(
        CachedTasks(tasks: tasks, savedAt: DateTime.now().toUtc()).toJson(),
      ),
    );
  }

  static Future<CachedTasks?> load(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      if (raw == null || raw.isEmpty) return null;
      return CachedTasks.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}
