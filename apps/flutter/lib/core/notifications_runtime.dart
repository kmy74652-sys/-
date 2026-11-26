import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsRuntime {
  NotificationsRuntime._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static RealtimeChannel? _channel;
  static String? _uid;
  static bool _initialized = false;
  static void Function(String? taskId)? _onOpen;

  static Future<void> start({void Function(String? taskId)? onOpen}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _onOpen = onOpen;
    if (_uid == uid && _channel != null) return;
    await stop();
    if (!_initialized) {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (response) {
          _onOpen?.call(response.payload?.isEmpty == true ? null : response.payload);
        },
      );
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          DarwinFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'alshaeri_notifications',
          'تنبيهات NEXORA',
          description: 'تنبيهات المهام داخل NEXORA',
          importance: Importance.high,
        ),
      );
      _initialized = true;
    }
    _uid = uid;
    _channel = Supabase.instance.client
        .channel('flutter-notifications-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_user_id',
            value: uid,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final id = row['id']?.toString();
            final title = row['title']?.toString() ?? 'تنبيه جديد';
            final body = row['body']?.toString() ?? '';
            final taskId = row['task_id']?.toString();
            if (id == null) return;
            unawaited(_show(id, title, body, taskId));
          },
        )
        .subscribe();
  }

  static Future<void> _show(
    String id,
    String title,
    String body,
    String? taskId,
  ) async {
    final numericId = id.codeUnits.fold<int>(0, (value, unit) => value + unit);
    await _plugin.show(
      numericId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'alshaeri_notifications',
          'تنبيهات NEXORA',
          channelDescription: 'تنبيهات المهام داخل NEXORA',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: taskId ?? '',
    );
  }

  static Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _uid = null;
    if (channel != null) {
      await Supabase.instance.client.removeChannel(channel);
    }
  }
}
