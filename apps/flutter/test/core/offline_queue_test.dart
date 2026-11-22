import 'package:flutter_test/flutter_test.dart';
import 'package:alshaeri_mobile/core/offline_queue.dart';

void main() {
  test('builds a stable idempotency item id', () {
    final payload = {
      'taskId': 'task-9',
      'idempotencyKey': 'report:task-9:fixed',
    };
    expect(
      OfflineQueue.itemId(OfflineQueueKind.report, payload),
      'report:task-9:report:task-9:fixed',
    );
    expect(
      OfflineQueue.itemId(OfflineQueueKind.report, payload),
      OfflineQueue.itemId(OfflineQueueKind.report, payload),
    );
  });

  group('OfflineQueueItem', () {
    test('round-trips supported queue data and nested report values', () {
      final createdAt = DateTime.utc(2026, 11, 22, 10, 30);
      final nextAttemptAt = DateTime.utc(2026, 11, 22, 10, 31);
      final item = OfflineQueueItem(
        id: 'report:task-1:key-1',
        ownerUid: 'user-1',
        kind: OfflineQueueKind.report,
        payload: {
          'taskId': 'task-1',
          'idempotencyKey': 'key-1',
          'values': {
            'comment': 'تم',
            'rows': [
              {'quantity': 3, 'checked': true},
            ],
          },
        },
        attempts: 2,
        createdAt: createdAt,
        nextAttemptAt: nextAttemptAt,
      );

      final restored = OfflineQueueItem.fromJson(item.toJson());

      expect(restored, isNotNull);
      expect(restored!.id, item.id);
      expect(restored.ownerUid, item.ownerUid);
      expect(restored.kind, OfflineQueueKind.report);
      expect(restored.attempts, 2);
      expect(restored.createdAt, createdAt);
      expect(restored.nextAttemptAt, nextAttemptAt);
      expect(restored.payload['values'], item.payload['values']);
    });

    test('rejects malformed or incomplete persisted items', () {
      expect(OfflineQueueItem.fromJson(null), isNull);
      expect(OfflineQueueItem.fromJson({'id': 'not-an-item'}), isNull);
      expect(
        OfflineQueueItem.fromJson({
          'id': '',
          'ownerUid': 'user-1',
          'kind': 'status',
          'payload': {'taskId': 'task-1'},
          'attempts': 0,
          'createdAt': '2026-11-22T10:30:00.000Z',
          'nextAttemptAt': '2026-11-22T10:30:00.000Z',
        }),
        isNull,
      );
    });

    test('rejects unknown queue kinds', () {
      expect(
        OfflineQueueItem.fromJson({
          'id': 'status:task-1:',
          'ownerUid': 'user-1',
          'kind': 'unknown',
          'payload': {'taskId': 'task-1'},
          'attempts': 0,
          'createdAt': '2026-11-22T10:30:00.000Z',
          'nextAttemptAt': '2026-11-22T10:30:00.000Z',
        }),
        isNull,
      );
    });

    test('round-trips a blocked item and its last error', () {
      final item = OfflineQueueItem(
        id: 'report:task-2:key-2',
        ownerUid: 'user-2',
        kind: OfflineQueueKind.report,
        payload: {'taskId': 'task-2', 'idempotencyKey': 'key-2'},
        attempts: 1,
        createdAt: DateTime.utc(2026, 11, 22, 10),
        nextAttemptAt: DateTime.utc(2036, 11, 22, 10),
        lastError: 'permission_denied',
        blocked: true,
      );

      final restored = OfflineQueueItem.fromJson(item.toJson());

      expect(restored, isNotNull);
      expect(restored!.blocked, isTrue);
      expect(restored.lastError, 'permission_denied');
    });

    test('round-trips an offline attachment with a local file reference', () {
      final item = OfflineQueueItem(
        id: 'attachment:task-3:evidence:key',
        ownerUid: 'user-3',
        kind: OfflineQueueKind.attachment,
        payload: {
          'taskId': 'task-3',
          'stepId': 'step-3',
          'idempotencyKey': 'evidence:key',
          'localPath': '/app-support/offline-attachments/user-3/key.bin',
          'storagePath': 'task-3/key-report.pdf',
          'fileName': 'report.pdf',
          'mimeType': 'application/pdf',
          'size': 128,
        },
        attempts: 0,
        createdAt: DateTime.utc(2026, 11, 22, 10),
        nextAttemptAt: DateTime.utc(2026, 11, 22, 10),
      );

      final restored = OfflineQueueItem.fromJson(item.toJson());

      expect(restored, isNotNull);
      expect(restored!.kind, OfflineQueueKind.attachment);
      expect(restored.payload['localPath'], item.payload['localPath']);
      expect(restored.payload['stepId'], 'step-3');
      expect(restored.payload['size'], 128);
    });

    test('preserves pending report attachment metadata without embedding bytes', () {
      final item = OfflineQueueItem(
        id: 'report:task-4:key-4',
        ownerUid: 'user-4',
        kind: OfflineQueueKind.report,
        payload: {
          'taskId': 'task-4',
          'idempotencyKey': 'key-4',
          'values': {
            'proof': [
              {
                'pendingUpload': true,
                'localPath': '/app-support/offline-attachments/user-4/a.bin',
                'name': 'a.pdf',
                'mimeType': 'application/pdf',
                'size': 2048,
              },
            ],
          },
        },
        attempts: 0,
        createdAt: DateTime.utc(2026, 11, 22, 10),
        nextAttemptAt: DateTime.utc(2026, 11, 22, 10),
      );

      final restored = OfflineQueueItem.fromJson(item.toJson());

      expect(restored, isNotNull);
      expect(restored!.payload['values'], item.payload['values']);
      expect(
        (restored.payload['values'] as Map)['proof'][0]['pendingUpload'],
        isTrue,
      );
    });
  });
}
