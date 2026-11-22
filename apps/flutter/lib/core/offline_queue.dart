import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_attachment_store.dart';

enum OfflineQueueKind { status, report, attachment }

class OfflineQueueItem {
  const OfflineQueueItem({
    required this.id,
    required this.ownerUid,
    required this.kind,
    required this.payload,
    required this.attempts,
    required this.createdAt,
    required this.nextAttemptAt,
    this.lastError,
    this.blocked = false,
  });

  final String id;
  final String ownerUid;
  final OfflineQueueKind kind;
  final Map<String, dynamic> payload;
  final int attempts;
  final DateTime createdAt;
  final DateTime nextAttemptAt;
  final String? lastError;
  final bool blocked;

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerUid': ownerUid,
    'kind': kind.name,
    'payload': payload,
    'attempts': attempts,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
    'lastError': lastError,
    'blocked': blocked,
  };

  static OfflineQueueItem? fromJson(dynamic value) {
    if (value is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(value);
      final kind = OfflineQueueKind.values.byName(map['kind'] as String);
      final payload = Map<String, dynamic>.from(map['payload'] as Map);
      final id = map['id'] as String;
      final ownerUid = map['ownerUid'] as String;
      final attempts = map['attempts'] as int;
      final createdAt = DateTime.tryParse(map['createdAt'] as String);
      final nextAttemptAt = DateTime.tryParse(map['nextAttemptAt'] as String);
      if (id.isEmpty ||
          ownerUid.isEmpty ||
          attempts < 0 ||
          createdAt == null ||
          nextAttemptAt == null)
        return null;
      return OfflineQueueItem(
        id: id,
        ownerUid: ownerUid,
        kind: kind,
        payload: payload,
        attempts: attempts,
        createdAt: createdAt,
        nextAttemptAt: nextAttemptAt,
        lastError: map['lastError']?.toString(),
        blocked: map['blocked'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

class OfflineQueue {
  OfflineQueue._();
  static const storageKey = '@alshaeri/mobile-offline-queue/v1';
  static const maxAttempts = 8;
  static bool _flushing = false;

  static String itemId(OfflineQueueKind kind, Map<String, dynamic> payload) =>
      '${kind.name}:${payload['taskId']}:${payload['idempotencyKey'] ?? ''}';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<List<OfflineQueueItem>> _read() async {
    final prefs = await _prefs();
    if (prefs == null) return [];
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(OfflineQueueItem.fromJson)
          .whereType<OfflineQueueItem>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<OfflineQueueItem> items) async {
    final prefs = await _prefs();
    if (prefs == null) throw StateError('Offline queue storage is unavailable');
    if (!await prefs.setString(
      storageKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    )) {
      throw StateError('Offline queue could not be persisted');
    }
  }

  static Future<void> enqueue(
    OfflineQueueKind kind,
    Map<String, dynamic> payload,
  ) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || payload['taskId'] == null) {
      throw StateError(
        'Cannot queue without an authenticated user and task ID',
      );
    }
    final id = itemId(kind, payload);
    var items = await _read();
    if (items.any((item) => item.id == id && item.ownerUid == uid)) return;

    // لا نسمح لحالة قديمة لنفس المهمة بأن تسبق الحالة الأحدث في الطابور.
    if (kind == OfflineQueueKind.status) {
      items = items
          .where(
            (item) =>
                !(item.ownerUid == uid &&
                    item.kind == OfflineQueueKind.status &&
                    item.payload['taskId'] == payload['taskId']),
          )
          .toList();
    }
    items.add(
      OfflineQueueItem(
        id: id,
        ownerUid: uid,
        kind: kind,
        payload: payload,
        attempts: 0,
        createdAt: DateTime.now().toUtc(),
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
    await _write(items);
  }

  static Future<int> pendingCount() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return 0;
    return (await _read())
        .where(
          (item) =>
              item.ownerUid == uid &&
              !item.blocked &&
              item.attempts < maxAttempts,
        )
        .length;
  }

  static Future<int> failedCount() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return 0;
    return (await _read())
        .where((item) => item.ownerUid == uid && item.blocked)
        .length;
  }

  static Future<void> retryFailed() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final items = await _read();
    await _write(
      items
          .map(
            (item) => item.ownerUid == uid && item.blocked
                ? OfflineQueueItem(
                    id: item.id,
                    ownerUid: item.ownerUid,
                    kind: item.kind,
                    payload: item.payload,
                    attempts: 0,
                    createdAt: item.createdAt,
                    nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
                      0,
                      isUtc: true,
                    ),
                  )
                : item,
          )
          .toList(),
    );
  }

  static Future<bool> isNetworkError(Object error) async {
    final message = error.toString().toLowerCase();
    return [
      'network',
      'fetch',
      'offline',
      'timeout',
      'timed out',
      'socketexception',
      'connection refused',
      'connection reset',
    ].any(message.contains);
  }

  static Future<Map<String, dynamic>> resolvePendingAttachments(
    Map<String, dynamic> values,
    String taskId,
  ) async {
    final resolved = await _resolvePending(values, taskId);
    return Map<String, dynamic>.from(resolved as Map);
  }

  static Future<dynamic> _resolvePending(dynamic value, String taskId) async {
    if (value is List) {
      return [for (final item in value) await _resolvePending(item, taskId)];
    }
    if (value is! Map) return value;
    final map = Map<String, dynamic>.from(value);
    if (map['pendingUpload'] == true && map['localPath'] != null) {
      final localPath = map['localPath'].toString();
      final bytes = await OfflineAttachmentStore.read(localPath);
      final safeName = '${map['name'] ?? 'attachment'}'.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final path =
          '$taskId/${DateTime.now().microsecondsSinceEpoch}-$safeName';
      final db = Supabase.instance.client;
      final user = db.auth.currentUser;
      if (user == null) throw StateError('سجّل الدخول مجددًا.');
      await db.storage.from('task-attachments').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: '${map['mimeType'] ?? 'application/octet-stream'}',
              upsert: false,
            ),
          );
      try {
        final row = await db
            .from('task_attachments')
            .insert({
              'task_id': taskId,
              'execution_step_id': null,
              'uploaded_by': user.id,
              'file_name': map['name'],
              'storage_path': path,
              'mime_type': map['mimeType'],
              'size_bytes': map['size'],
            })
            .select('id')
            .single();
        await OfflineAttachmentStore.delete(localPath);
        return {
          'id': '${row['id']}',
          'path': path,
          'name': map['name'],
          'mimeType': map['mimeType'],
          'size': map['size'],
        };
      } catch (_) {
        await db.storage.from('task-attachments').remove([path]);
        rethrow;
      }
    }
    return {
      for (final entry in map.entries)
        entry.key: await _resolvePending(entry.value, taskId),
    };
  }

  static Future<void> _execute(OfflineQueueItem item) async {
    final db = Supabase.instance.client;
    final p = item.payload;
    if (item.kind == OfflineQueueKind.status) {
      await db.rpc(
        'mobile_record_task_update',
        params: {
          'p_task_id': p['taskId'],
          'p_status': p['status'],
          'p_note': p['note'],
        },
      );
    } else if (item.kind == OfflineQueueKind.attachment) {
      final localPath = '${p['localPath'] ?? ''}';
      if (localPath.isEmpty) throw StateError('المرفق المحلي غير موجود.');
      final bytes = await OfflineAttachmentStore.read(localPath);
      await db.storage.from('task-attachments').uploadBinary(
            '${p['storagePath']}',
            bytes,
            fileOptions: FileOptions(
              contentType: '${p['mimeType']}',
              upsert: false,
            ),
          );
      try {
        await db.from('task_attachments').insert({
          'task_id': p['taskId'],
          'execution_step_id': p['stepId'],
          'uploaded_by': item.ownerUid,
          'file_name': p['fileName'],
          'storage_path': p['storagePath'],
          'mime_type': p['mimeType'],
          'size_bytes': p['size'],
        });
      } catch (_) {
        await db.storage.from('task-attachments').remove(['${p['storagePath']}']);
        rethrow;
      }
      await OfflineAttachmentStore.delete(localPath);
    } else if (p['snapshotId'] != null) {
      final values = await resolvePendingAttachments(
        Map<String, dynamic>.from(p['values'] as Map),
        '${p['taskId']}',
      );
      await db.rpc(
        'mobile_submit_task_report_form',
        params: {
          'p_task_id': p['taskId'],
          'p_snapshot_id': p['snapshotId'],
          'p_values': values,
          'p_idempotency_key': p['idempotencyKey'],
        },
      );
    } else {
      final values = await resolvePendingAttachments(
        Map<String, dynamic>.from(p['values'] as Map),
        '${p['taskId']}',
      );
      await db.rpc(
        'mobile_submit_task_report',
        params: {
          'p_task_id': p['taskId'],
          'p_values': values,
          'p_idempotency_key': p['idempotencyKey'],
        },
      );
    }
  }

  static Future<void> flush() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || _flushing) return;
    _flushing = true;
    try {
      final now = DateTime.now().toUtc();
      final due = (await _read())
          .where(
            (item) =>
                item.ownerUid == uid &&
                !item.blocked &&
                item.attempts < maxAttempts &&
                !item.nextAttemptAt.isAfter(now),
          )
          .toList();
      for (final item in due) {
        if (Supabase.instance.client.auth.currentUser?.id != uid) break;
        try {
          await _execute(item);
          final items = await _read();
          await _write(
            items
                .where(
                  (candidate) =>
                      candidate.id != item.id || candidate.ownerUid != uid,
                )
                .toList(),
          );
        } catch (error) {
          final items = await _read();
          final network = await isNetworkError(error);
          final delay = (1 << item.attempts.clamp(0, 8)) * 1000;
          await _write(
            items.map((candidate) {
              if (candidate.id != item.id || candidate.ownerUid != uid)
                return candidate;
              return OfflineQueueItem(
                id: candidate.id,
                ownerUid: candidate.ownerUid,
                kind: candidate.kind,
                payload: candidate.payload,
                attempts: candidate.attempts + 1,
                createdAt: candidate.createdAt,
                nextAttemptAt: network && candidate.attempts + 1 < maxAttempts
                    ? DateTime.now().toUtc().add(
                        Duration(
                          milliseconds: delay > 1800000 ? 1800000 : delay,
                        ),
                      )
                    : DateTime.now().toUtc().add(const Duration(days: 3650)),
                lastError: error.toString(),
                blocked: !network || candidate.attempts + 1 >= maxAttempts,
              );
            }).toList(),
          );
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
