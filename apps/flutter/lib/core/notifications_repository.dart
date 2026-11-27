import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    this.taskId,
    required this.title,
    this.body,
    this.severity,
    this.readAt,
    required this.createdAt,
  });

  final String id;
  final String? taskId;
  final String title;
  final String? body;
  final String? severity;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
        id: id,
        taskId: taskId,
        title: title,
        body: body,
        severity: severity,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
      );

  static AppNotification fromRow(Map<String, dynamic> row) => AppNotification(
        id: '${row['id'] ?? ''}',
        taskId: row['task_id']?.toString(),
        title: '${row['title'] ?? 'تنبيه'}',
        body: row['body']?.toString(),
        severity: row['severity']?.toString(),
        readAt: DateTime.tryParse('${row['read_at'] ?? ''}'),
        createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': taskId,
        'title': title,
        'body': body,
        'severity': severity,
        'read_at': readAt?.toUtc().toIso8601String(),
        'created_at': createdAt?.toUtc().toIso8601String(),
      };

  static AppNotification? fromJson(dynamic value) {
    if (value is! Map) return null;
    try {
      final row = Map<String, dynamic>.from(value);
      if ('${row['id'] ?? ''}'.isEmpty) return null;
      return fromRow(row);
    } catch (_) {
      return null;
    }
  }
}

class NotificationsRepository {
  NotificationsRepository._();

  static const _keyPrefix = '@alshaeri/notifications-cache/v1/';

  static String _key(String uid) => '$_keyPrefix$uid';

  static Future<List<AppNotification>> load({required String uid}) async {
    final client = Supabase.instance.client;
    final result = await client
        .from('notifications')
        .select('id,task_id,title,body,severity,read_at,created_at')
        .order('created_at', ascending: false)
        .limit(50);
    final rows = (result as List)
        .map((row) => AppNotification.fromRow(Map<String, dynamic>.from(row)))
        .toList();
    await _save(uid, rows);
    return rows;
  }

  static Future<List<AppNotification>?> loadCached(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map(AppNotification.fromJson).whereType<AppNotification>().toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(String uid, List<AppNotification> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(uid),
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> markTaskOpened(String taskId) async {
    try {
      await Supabase.instance.client.rpc(
        'mobile_mark_task_opened',
        params: {'p_task_id': taskId},
      );
    } catch (_) {
      // فتح المهمة لا يفشل بسبب تعذر تسجيل حالة الفتح.
    }
  }

  static Future<bool> markRead(String notificationId) async {
    final result = await Supabase.instance.client.rpc(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
    final marked = result == true;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null && uid.isNotEmpty) {
      final cached = await loadCached(uid);
      if (cached != null) {
        await _save(
          uid,
          cached
              .map((item) => item.id == notificationId
                  ? item.copyWith(readAt: DateTime.now().toUtc())
                  : item)
              .toList(),
        );
      }
    }
    return marked;
  }

  static Future<bool> deleteNotification(String notificationId) async {
    final result = await Supabase.instance.client.rpc(
      'delete_notification',
      params: {'p_notification_id': notificationId},
    );
    final deleted = result == true;
    if (!deleted) return false;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null && uid.isNotEmpty) {
      final cached = await loadCached(uid);
      if (cached != null) {
        await _save(
          uid,
          cached.where((item) => item.id != notificationId).toList(),
        );
      }
    }
    return true;
  }
}
