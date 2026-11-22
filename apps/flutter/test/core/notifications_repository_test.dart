import 'package:flutter_test/flutter_test.dart';
import 'package:alshaeri_mobile/core/notifications_repository.dart';

void main() {
  test('parses notification rows and identifies unread items', () {
    final item = AppNotification.fromRow({
      'id': 'notification-1',
      'task_id': 'task-1',
      'title': 'مهمة جديدة',
      'body': 'لديك مهمة جديدة',
      'severity': 'info',
      'read_at': null,
      'created_at': '2026-11-22T10:30:00.000Z',
    });

    expect(item.id, 'notification-1');
    expect(item.taskId, 'task-1');
    expect(item.isUnread, isTrue);
    expect(item.title, 'مهمة جديدة');
  });

  test('round-trips notification cache data', () {
    final item = AppNotification.fromRow({
      'id': 'notification-2',
      'title': 'تمت المراجعة',
      'read_at': '2026-11-22T10:31:00.000Z',
      'created_at': '2026-11-22T10:30:00.000Z',
    });

    final restored = AppNotification.fromJson(item.toJson());

    expect(restored, isNotNull);
    expect(restored!.id, item.id);
    expect(restored.isUnread, isFalse);
    expect(restored.readAt, item.readAt);
  });

  test('rejects malformed notification cache records', () {
    expect(AppNotification.fromJson(null), isNull);
    expect(AppNotification.fromJson({'title': 'بدون معرف'}), isNull);
  });
}
