import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/offline_queue.dart';
import '../../core/task_cache.dart';
import '../../shared/app_shell.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = [];
  bool _showingCachedTasks = false;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  int _pendingCount = 0;
  int _failedCount = 0;
  bool _queueBusy = false;

  static const Map<String, String> _statusLabels = {
    'pending': 'جديدة',
    'in_progress': 'قيد التنفيذ',
    'submitted': 'بانتظار المراجعة',
    'approved': 'معتمدة / مكتملة',
    'rejected': 'تحتاج استكمالًا / معادة',
    'late': 'متأخرة',
  };
  static const Map<String, String> _priorityLabels = {
    'normal': 'عادية',
    'important': 'مهمة',
    'urgent': 'عاجلة',
    'critical': 'حرجة',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((r) => r != ConnectivityResult.none)) _flushQueue();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      final rows = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 500) {
        final page = await client
            .from('tasks')
            .select(
              'id,title,description,due_at,priority,status,assigned_at,received_at,opened_at',
            )
            .isFilter('deleted_at', null)
            .order('due_at')
            .range(offset, offset + 499);
        rows.addAll(List<Map<String, dynamic>>.from(page));
        if (page.length < 500) break;
      }
      _tasks = rows;
      _showingCachedTasks = false;
      if (uid != null) {
        await TaskCache.save(uid, rows);
        await OfflineQueue.flush();
        _pendingCount = await OfflineQueue.pendingCount();
        _failedCount = await OfflineQueue.failedCount();
      }
    } catch (error) {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final cached = uid == null ? null : await TaskCache.load(uid);
      if (cached != null) {
        _tasks = cached.tasks;
        _showingCachedTasks = true;
        _error = null;
      } else {
        _error = 'تعذر تحميل المهام. تحقق من الاتصال وصلاحيات حسابك.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _flushQueue() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null || _queueBusy) return;
    _queueBusy = true;
    try {
      await OfflineQueue.flush();
      final count = await OfflineQueue.pendingCount();
      final failed = await OfflineQueue.failedCount();
      if (!mounted) return;
      setState(() {
        _pendingCount = count;
        _failedCount = failed;
      });
      await _load();
    } finally {
      _queueBusy = false;
    }
  }

  String _normalizedStatus(Map<String, dynamic> task) {
    final status = '${task['status'] ?? 'pending'}';
    return const {
          'new': 'pending',
          'received': 'pending',
          'on_hold': 'in_progress',
          'report_submitted': 'submitted',
          'completed_approved': 'approved',
          'completed': 'approved',
          'needs_revision': 'rejected',
          'returned': 'rejected',
        }[status] ??
        status;
  }

  bool _matchesStatus(Map<String, dynamic> task, DateTime now) {
    final status = _normalizedStatus(task);
    if (_statusFilter == 'all') return true;
    if (_statusFilter == 'late') {
      if (status == 'approved' || status == 'cancelled') return false;
      final due = DateTime.tryParse('${task['due_at'] ?? ''}');
      return status == 'late' || (due != null && due.isBefore(now));
    }
    return status == _statusFilter;
  }

  List<Map<String, dynamic>> get _filteredTasks {
    final query = _search.trim().toLowerCase();
    final now = DateTime.now();
    return _tasks.where((task) {
      final text = '${task['title'] ?? ''} ${task['description'] ?? ''}'
          .toLowerCase();
      final priority = '${task['priority'] ?? 'normal'}';
      return (query.isEmpty || text.contains(query)) &&
          _matchesStatus(task, now) &&
          (_priorityFilter == 'all' || priority == _priorityFilter);
    }).toList();
  }

  void _resetFilters() {
    setState(() {
      _search = '';
      _searchController.clear();
      _statusFilter = 'all';
      _priorityFilter = 'all';
    });
  }

  Widget _chip(
    String value,
    String label,
    String selected,
    ValueChanged<String> onSelected,
  ) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: value == selected,
      onSelected: (_) => setState(() => onSelected(value)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
    ),
  );

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'المهام والمتابعة',
    subtitle: 'قائمة المهام المصرّح بها لحسابك',
    child: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? ListView(
              children: const [
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator()),
              ],
            )
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(_error!, textAlign: TextAlign.right),
                TextButton(
                  onPressed: _load,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            )
          : Builder(
              builder: (context) {
                final visibleTasks = _filteredTasks;
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_showingCachedTasks)
                      Card(
                        color: Colors.amber.shade50,
                        child: const ListTile(
                          dense: true,
                          leading: Icon(Icons.cloud_off),
                          title: Text(
                            'تُعرض آخر نسخة محفوظة من المهام',
                            textAlign: TextAlign.right,
                          ),
                          subtitle: Text(
                            'ستتم المزامنة تلقائيًا عند عودة الاتصال.',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                    if (_pendingCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'لديك $_pendingCount طلبات بانتظار المزامنة',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_failedCount > 0)
                      Card(
                        color: Colors.orange.shade50,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          title: Text(
                            '$_failedCount عمليات تحتاج مراجعة أو إعادة محاولة',
                            textAlign: TextAlign.right,
                          ),
                          subtitle: const Text(
                            'تم إيقاف المحاولة التلقائية لخطأ غير متعلق بالشبكة.',
                            textAlign: TextAlign.right,
                          ),
                          trailing: TextButton(
                            onPressed: _queueBusy
                                ? null
                                : () async {
                                    await OfflineQueue.retryFailed();
                                    await _flushQueue();
                                  },
                            child: const Text('إعادة المحاولة'),
                          ),
                        ),
                      ),
                    TextField(
                      controller: _searchController,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        hintText: 'ابحث في عنوان المهمة أو وصفها…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _search = '';
                                  _searchController.clear();
                                }),
                              ),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() => _search = value),
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'الحالة',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          _chip(
                            'all',
                            'الكل',
                            _statusFilter,
                            (v) => _statusFilter = v,
                          ),
                          ..._statusLabels.entries.map(
                            (entry) => _chip(
                              entry.key,
                              entry.value,
                              _statusFilter,
                              (v) => _statusFilter = v,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'الأولوية',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          _chip(
                            'all',
                            'كل الأولويات',
                            _priorityFilter,
                            (v) => _priorityFilter = v,
                          ),
                          ..._priorityLabels.entries.map(
                            (entry) => _chip(
                              entry.key,
                              entry.value,
                              _priorityFilter,
                              (v) => _priorityFilter = v,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'المعروض ${visibleTasks.length} من ${_tasks.length}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('مسح المرشحات'),
                        ),
                      ],
                    ),
                    if (_tasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 72),
                        child: Center(child: Text('لا توجد مهام متاحة حاليًا')),
                      )
                    else if (visibleTasks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 44),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.filter_alt_off,
                              size: 34,
                              color: AppColors.muted,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'لا توجد مهام تطابق البحث والمرشحات',
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: _resetFilters,
                              child: const Text('عرض جميع المهام'),
                            ),
                          ],
                        ),
                      )
                    else
                      ...visibleTasks.map(
                        (task) => Card(
                          child: ListTile(
                            onTap: () => context.push('/tasks/${task['id']}'),
                            contentPadding: const EdgeInsets.all(14),
                            title: Text(
                              '${task['title'] ?? 'مهمة'}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if ((task['description'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Text(
                                      '${task['description']}',
                                      textAlign: TextAlign.right,
                                    ),
                                  Text(
                                    'الحالة: ${_statusLabels[_normalizedStatus(task)] ?? task['status'] ?? 'جديدة'} · الأولوية: ${_priorityLabels['${task['priority'] ?? 'normal'}'] ?? task['priority'] ?? 'عادية'}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  if (task['due_at'] != null)
                                    Text(
                                      'الاستحقاق: ${task['due_at']}',
                                      textAlign: TextAlign.right,
                                    ),
                                ],
                              ),
                            ),
                            trailing: const Icon(Icons.assignment_outlined),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    ),
  );
}
