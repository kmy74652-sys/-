import 'package:flutter_test/flutter_test.dart';
import 'package:alshaeri_mobile/core/task_cache.dart';

void main() {
  test('round-trips cached tasks with timestamp and nested values', () {
    final savedAt = DateTime.utc(2026, 11, 22, 10, 30);
    final cached = CachedTasks(
      savedAt: savedAt,
      tasks: [
        {
          'id': 'task-1',
          'title': 'مهمة تجريبية',
          'metadata': {'priority': 'urgent'},
        },
      ],
    );

    final restored = CachedTasks.fromJson(cached.toJson());

    expect(restored, isNotNull);
    expect(restored!.savedAt, savedAt);
    expect(restored.tasks.single['id'], 'task-1');
    expect(restored.tasks.single['metadata'], {'priority': 'urgent'});
  });

  test('rejects malformed cached data', () {
    expect(CachedTasks.fromJson(null), isNull);
    expect(CachedTasks.fromJson({'savedAt': 'not-a-date', 'tasks': []}), isNull);
    expect(
      CachedTasks.fromJson({
        'savedAt': '2026-11-22T10:30:00.000Z',
        'tasks': 'not-a-list',
      }),
      isNull,
    );
  });
}
