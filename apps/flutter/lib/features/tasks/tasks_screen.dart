import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/offline_queue.dart';
import '../../core/task_cache.dart';
import '../../shared/app_shell.dart';
import '../../shared/ui_labels.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, this.initialStatus});

  final String? initialStatus;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = [];
  final Map<String, Map<String, dynamic>> _reportByTask = {};
  bool _showingCachedTasks = false;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  bool _filtersExpanded = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  RealtimeChannel? _tasksChannel;
  int _pendingCount = 0;
  int _failedCount = 0;
  bool _queueBusy = false;
  String _view = 'tasks';
  String _ledgerOrder = 'latest';
  bool _officialHeaderCollapsed = false;
  bool _administrativeDetailsCollapsed = true;
  String? _organizationId;
  bool _canEditOfficialTasks = false;
  bool _canFilterEmployees = false;
  String _employeeFilter = 'all';
  List<Map<String, dynamic>> _employees = [];

  static const Map<String, String> _statusLabels = {
    'pending': 'جديدة',
    'in_progress': 'قيد التنفيذ',
    'submitted': 'بانتظار المراجعة',
    'approved': 'معتمدة',
    'rejected': 'مرفوضة',
    'late': 'متأخرة',
  };
  static const Map<String, String> _priorityLabels = {
    'low': 'منخفضة',
    'normal': 'عادية',
    'high': 'عالية',
    'urgent': 'عاجلة',
    'important': 'مهمة',
    'critical': 'حرجة',
  };

  @override
  void initState() {
    super.initState();
    const supportedStatuses = {'all', 'pending', 'in_progress', 'submitted', 'approved', 'rejected', 'late'};
    if (supportedStatuses.contains(widget.initialStatus)) {
      _statusFilter = widget.initialStatus!;
    }
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadTaskEditIdentity();
    _tasksChannel = Supabase.instance.client
        .channel('tasks-screen-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (_) {
            if (mounted) _load();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_reports',
          callback: (_) {
            if (mounted) _load();
          },
        )
      ..subscribe();
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
    if (_tasksChannel != null) {
      Supabase.instance.client.removeChannel(_tasksChannel!);
    }
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (_tasks.isEmpty && uid != null) {
      final cached = await TaskCache.load(uid);
      if (cached != null && mounted && _tasks.isEmpty) {
        setState(() {
          _tasks = cached.tasks;
          _showingCachedTasks = true;
        });
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final rows = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 500) {
        final page = await client
            .from('tasks')
            .select(
              'id,organization_id,title,description,due_at,priority,status,report_required,report_form_snapshot_id,assigned_to,assigned_at,received_at,opened_at,created_at,updated_at',
            )
            .isFilter('deleted_at', null)
            .order('due_at')
            .range(offset, offset + 499);
        rows.addAll(List<Map<String, dynamic>>.from(page));
        if (page.length < 500) break;
      }
        _tasks = rows;
        _reportByTask.clear();
        if (rows.isNotEmpty) {
          final ids = rows.map((row) => '${row['id']}').toList();
          for (var reportOffset = 0; ; reportOffset += 500) {
            final reports = await client
                .from('task_reports')
                .select('id,task_id,status,submitted_at,reviewed_at,review_note')
                .inFilter('task_id', ids)
                .order('submitted_at', ascending: false)
                .range(reportOffset, reportOffset + 499);
            for (final report in (reports as List).whereType<Map>()) {
              final taskId = '${report['task_id'] ?? ''}';
              if (taskId.isNotEmpty && !_reportByTask.containsKey(taskId)) {
                _reportByTask[taskId] = Map<String, dynamic>.from(report);
              }
            }
            if (reports.length < 500) break;
          }
        }
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

  Future<void> _loadTaskEditIdentity() async {
    try {
      final raw = await Supabase.instance.client.rpc('mobile_my_profile');
      final root = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final employee = root['employee'];
      if (employee is! Map) return;
      final profile = Map<String, dynamic>.from(employee);
      final roles = profile['roles'] is List
          ? (profile['roles'] as List)
                .whereType<Map>()
                .map((role) => '${role['code'] ?? ''}')
                .toSet()
          : <String>{};
      final permissions = profile['permissions'] is List
          ? (profile['permissions'] as List).map((value) => '$value').toSet()
          : <String>{};
      final organization = (profile['institutionId'] ??
              profile['institution_id'] ??
              profile['organization_id'])
          ?.toString();
      var employees = <Map<String, dynamic>>[];
      final canFilter = permissions.contains('tasks.manage') ||
          permissions.contains('tasks.review') ||
          permissions.contains('reports.read_all');
      if (canFilter && organization != null && organization.isNotEmpty) {
        try {
          final rows = await Supabase.instance.client
              .from('organization_memberships')
              .select('id,user_id,display_name,employee_no')
              .eq('organization_id', organization)
              .eq('is_active', true)
              .order('display_name');
          employees = rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .where((row) => '${row['user_id'] ?? ''}'.isNotEmpty)
              .toList();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _organizationId = organization;
        _canEditOfficialTasks =
            roles.contains('owner') || roles.contains('admin_followup');
        _canFilterEmployees = canFilter;
        _employees = employees;
      });
    } catch (_) {
      // Keep the edit affordance hidden; Supabase remains the final authority.
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
          (_priorityFilter == 'all' || priority == _priorityFilter) &&
          (_employeeFilter == 'all' ||
              '${task['assigned_to'] ?? ''}' == _employeeFilter);
    }).toList();
  }

  void _resetFilters() {
    setState(() {
      _search = '';
      _searchController.clear();
      _statusFilter = 'all';
      _priorityFilter = 'all';
      _employeeFilter = 'all';
    });
  }

  Future<void> _openTaskSearch() async {
    final controller = TextEditingController(text: _search);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('البحث في المهام', textAlign: TextAlign.right),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            hintText: 'عنوان المهمة أو وصفها',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (query) => Navigator.of(dialogContext).pop(query),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('بحث'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null) return;
    setState(() {
      _search = value;
      _searchController.value = TextEditingValue(text: value);
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
          : _error != null && _tasks.isEmpty
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
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: IconButton(
                        tooltip: _search.isEmpty ? 'بحث' : 'مسح البحث',
                        icon: Icon(_search.isEmpty ? Icons.search : Icons.search_off),
                        onPressed: _search.isEmpty
                            ? _openTaskSearch
                            : () => setState(() {
                                  _search = '';
                                  _searchController.clear();
                                }),
                      ),
                    ),
                    if (_canFilterEmployees && _employees.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _employeeFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'عرض الموظفين',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('كل الموظفين'),
                          ),
                          ..._employees.map(
                            (employee) => DropdownMenuItem<String>(
                              value: '${employee['user_id']}',
                              child: Text(
                                '${employee['display_name'] ?? 'موظف'}'
                                '${employee['employee_no'] == null ? '' : ' · ${employee['employee_no']}' }',
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _employeeFilter = value ?? 'all',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        ChoiceChip(
                          label: const Text('المهام الحالية'),
                          selected: _view == 'tasks',
                          onSelected: (_) => setState(() => _view = 'tasks'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('كشف المهام'),
                          selected: _view == 'ledger',
                          onSelected: (_) => setState(() => _view = 'ledger'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _statusFilter == 'all' && _priorityFilter == 'all'
                                      ? 'الفلاتر'
                                      : 'الفلاتر · نشط: ${(_statusFilter == 'all' ? 0 : 1) + (_priorityFilter == 'all' ? 0 : 1)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              IconButton(
                                tooltip: 'إعادة تعيين الفلاتر',
                                onPressed: _resetFilters,
                                icon: const Icon(Icons.restart_alt),
                              ),
                              IconButton(
                                tooltip: _filtersExpanded ? 'إخفاء الفلاتر' : 'إظهار الفلاتر',
                                onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
                                icon: Icon(_filtersExpanded ? Icons.expand_less : Icons.expand_more),
                              ),
                            ],
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            child: !_filtersExpanded
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        const Text('الحالة', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700)),
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            textDirection: TextDirection.rtl,
                                            children: [
                                              _chip('all', 'الكل', _statusFilter, (v) => _statusFilter = v),
                                              ..._statusLabels.entries.map((entry) => _chip(entry.key, entry.value, _statusFilter, (v) => _statusFilter = v)),
                                            ],
                                          ),
                                        ),
                                        const Text('الأولوية', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700)),
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            textDirection: TextDirection.rtl,
                                            children: [
                                              _chip('all', 'كل الأولويات', _priorityFilter, (v) => _priorityFilter = v),
                                              ..._priorityLabels.entries.map((entry) => _chip(entry.key, entry.value, _priorityFilter, (v) => _priorityFilter = v)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
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
                      ],
                    ),
                    if (_view == 'ledger')
                      _taskLedger(visibleTasks)
                    else if (visibleTasks.isNotEmpty)
                      _officialTableCard(visibleTasks),
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
                  ],
                );
              },
            ),
    ),
  );

  Widget _officialCell(
    String text, {
    bool bold = false,
    Color? background,
    bool singleLine = false,
  }) =>
      Container(
        color: background,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        alignment: Alignment.centerRight,
        child: Text(
          text.trim().isEmpty ? '—' : text,
          textAlign: TextAlign.right,
          softWrap: !singleLine,
          maxLines: singleLine ? 1 : null,
          overflow: singleLine ? TextOverflow.ellipsis : TextOverflow.clip,
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal),
        ),
      );

  String _cleanOfficialOutput(String title, String output) {
    final cleanTitle = title.trim();
    final cleanOutput = output.trim();
    if (cleanOutput.isEmpty || cleanOutput == cleanTitle) return '—';
    return cleanOutput;
  }

  Widget _officialStatusChip(String statusKey, String label) {
    final style = switch (statusKey) {
      'in_progress' => (Icons.autorenew, const Color(0xff9a6700), const Color(0xfffff4cc)),
      'submitted' => (Icons.fact_check_outlined, const Color(0xff1565c0), const Color(0xffe5f0ff)),
      'approved' => (Icons.verified_outlined, const Color(0xff137333), const Color(0xffe5f5e9)),
      'rejected' => (Icons.replay_outlined, const Color(0xffb3261e), const Color(0xffffe9e7)),
      'late' => (Icons.schedule_outlined, const Color(0xffb3261e), const Color(0xffffe9e7)),
      _ => (Icons.fiber_new_outlined, AppColors.navy, const Color(0xffeaf1f8)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: style.$3,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: Directionality.of(context),
        children: [
          Icon(style.$1, size: 15, color: style.$2),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: Text(
              label,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: style.$2, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _officialTwoWordPreview(String text) {
    final clean = text.trim();
    if (clean.isEmpty || clean == '—') return '—';
    final words = clean.split(RegExp(r'\s+'));
    return words.length <= 2 ? clean : '${words.take(2).join(' ')}...';
  }

  String _replaceOfficialRow(
    String description, {
    required String time,
    required String title,
    required String output,
  }) {
    final row = 'صف الجدول: ${time.trim()} | ${title.trim()} | ${output.trim()}';
    final rowPattern = RegExp(r'^صف الجدول:\s*.*$', multiLine: true);
    if (rowPattern.hasMatch(description)) {
      return description.replaceFirst(rowPattern, row);
    }
    final lines = description.split('\n').map((line) {
      if (line.startsWith('الوقت المحدد:')) return 'الوقت المحدد: ${time.trim()}';
      if (line.startsWith('المخرج المطلوب:')) return 'المخرج المطلوب: ${output.trim()}';
      return line;
    }).toList();
    return lines.join('\n');
  }

  Future<Map<String, String>?> _editOfficialRowDialog(
    Map<String, dynamic> row,
  ) async {
    final timeController = TextEditingController(text: '${row['time'] ?? ''}');
    final titleController = TextEditingController(text: '${row['title'] ?? ''}');
    final outputController = TextEditingController(
      text: row['output'] == '—' ? '' : '${row['output'] ?? ''}',
    );
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل بيانات صف المهمة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: timeController,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'الوقت'),
                ),
                TextField(
                  controller: titleController,
                  maxLines: 2,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'المهمة والمسؤولية'),
                ),
                TextField(
                  controller: outputController,
                  maxLines: 2,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'المخرج المطلوب'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                Navigator.of(dialogContext).pop({
                  'time': timeController.text.trim(),
                  'title': title,
                  'output': outputController.text.trim(),
                });
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ التعديلات'),
            ),
          ],
        ),
      ),
    );
    timeController.dispose();
    titleController.dispose();
    outputController.dispose();
    return result;
  }

  Future<void> _editOfficialRow(Map<String, dynamic> row) async {
    if (!_canEditOfficialTasks) return;
    final task = row['_task'];
    final organizationId = '${task is Map ? task['organization_id'] ?? _organizationId ?? '' : _organizationId ?? ''}';
    final taskId = '${row['taskId'] ?? ''}';
    if (taskId.isEmpty || organizationId.isEmpty) return;
    final values = await _editOfficialRowDialog(row);
    if (values == null || !mounted) return;
    try {
      final description = _replaceOfficialRow(
        '${task is Map ? task['description'] ?? '' : ''}',
        time: values['time'] ?? '',
        title: values['title'] ?? '',
        output: values['output'] ?? '',
      );
      await Supabase.instance.client.rpc(
        'admin_update_task',
        params: {
          'p_organization_id': organizationId,
          'p_task_id': taskId,
          'p_title': values['title'],
          'p_description': description,
          'p_due_at': null,
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ تعديلات صف المهمة')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString();
      final message = raw.contains('management_role_required')
          ? 'لا تملك صلاحية تعديل المهام.'
          : raw.contains('task_not_found')
          ? 'المهمة غير موجودة أو لم تعد متاحة.'
          : 'تعذر حفظ التعديل: $raw';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _showOfficialTextCard({
    required String section,
    required String time,
    required String text,
    Map<String, dynamic>? row,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty || clean == '—') return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFA),
              border: Border.all(color: const Color(0xFFD8E4E0)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  color: AppColors.navy,
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          section,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.schedule_outlined, size: 17, color: AppColors.muted),
                      const SizedBox(width: 5),
                      Text(
                        'الوقت: ${time.trim().isEmpty ? 'غير محدد' : time.trim()}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE0EAE7)),
                  ),
                  child: Text(
                    clean,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 16, height: 1.65, color: AppColors.navy),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Row(
                    children: [
                      if (_canEditOfficialTasks && row != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();
                              await _editOfficialRow(row);
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('تعديل'),
                          ),
                        ),
                      if (_canEditOfficialTasks && row != null) const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                          label: const Text('إغلاق'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _officialTextCell({
    required String section,
    required String time,
    required String text,
    Map<String, dynamic>? row,
  }) {
    final preview = _officialTwoWordPreview(text);
    return InkWell(
      onTap: preview == '—'
          ? null
          : () => _showOfficialTextCard(section: section, time: time, text: text, row: row),
      child: _officialCell(preview, singleLine: true),
    );
  }

  Widget _officialTableCard(List<Map<String, dynamic>> tasks) {
    final firstDescription = '${tasks.first['description'] ?? ''}';
    String value(String label) {
      final line = firstDescription.split('\n').firstWhere(
        (item) => item.startsWith('$label:'),
        orElse: () => '',
      );
      return line.isEmpty ? '—' : line.substring(label.length + 1).trim();
    }
    final workHours = value('ساعات الدوام')
        .split('·')
        .map((item) => item.trim())
        .toList();
    String workHour(int index) => index < workHours.length ? workHours[index] : '—';
    final legacyWorkHours = workHours.length < 6 ||
        !workHour(2).startsWith('الفترة الأولى:');
    final firstPeriod = legacyWorkHours
        ? '—'
        : workHour(2).replaceFirst('الفترة الأولى:', '').trim();
    final breakPeriod = legacyWorkHours
        ? '—'
        : workHour(3).replaceFirst('الاستراحة:', '').trim();
    final secondPeriod = legacyWorkHours
        ? '—'
        : workHour(4).replaceFirst('الفترة الثانية:', '').trim();
    final weeklyException = legacyWorkHours
        ? workHour(2).replaceFirst('الاستثناء الأسبوعي:', '').trim()
        : workHour(5).replaceFirst('الاستثناء الأسبوعي:', '').trim();
    Widget compactField(String label, String fieldValue) => Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          color: const Color(0xFFF8FBFA),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.navy),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                fieldValue.trim().isEmpty ? '—' : fieldValue,
                textAlign: TextAlign.right,
                softWrap: true,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );

    Widget compactGrid(List<(String, String)> fields) {
      final items = [...fields];
      if (items.length.isOdd) items.add(('', ''));
      return Table(
        textDirection: Directionality.of(context),
        border: TableBorder.all(color: const Color(0xFFD8E4E0), width: 0.8),
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
        children: [
          for (var i = 0; i < items.length; i += 2)
            TableRow(
              children: [
                compactField(items[i].$1, items[i].$2),
                compactField(items[i + 1].$1, items[i + 1].$2),
              ],
            ),
        ],
      );
    }

    final employeeFields = <(String, String)>[
      ('المسمى الوظيفي', value('المسمى الوظيفي')),
      ('الفرع', value('الفرع')),
      ('تاريخ بدء التطبيق', value('تاريخ بدء التطبيق')),
      ('الهدف من الوظيفة', value('الهدف من الوظيفة')),
    ];
    final workFields = <(String, String)>[
      ('نوع الدوام', workHour(0)),
      ('الأيام', workHour(1)),
      ('الاستثناء الأسبوعي', weeklyException),
      if (firstPeriod != '—' && firstPeriod.isNotEmpty) ('الفترة الأولى', firstPeriod),
      if (breakPeriod != '—' && breakPeriod.isNotEmpty) ('الاستراحة', breakPeriod),
      if (secondPeriod != '—' && secondPeriod.isNotEmpty) ('الفترة الثانية', secondPeriod),
    ];
    final recommendations = value('التوصيات الإدارية') != '—'
        ? value('التوصيات الإدارية')
        : value('التعليمات');
    final detailFields = <(String, String)>[
      ('المسؤوليات الأساسية', value('المسؤوليات')),
      ('الصلاحيات', value('الصلاحيات')),
      ('التوصيات الإدارية', recommendations),
      ('مؤشرات تقييم الأداء', value('مؤشرات الأداء')),
      ('ملاحظات وتعليمات للإدارة أو الموظف', value('ملاحظات وتعليمات إضافية')),
    ];
    final officialRows = <Map<String, dynamic>>[];
    final rowPattern = RegExp(
      r'^صف الجدول:\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*$',
      multiLine: true,
    );
    for (final task in tasks) {
      final description = '${task['description'] ?? ''}';
      final matches = rowPattern.allMatches(description).toList();
      if (matches.isEmpty) {
        final timeLine = description.split('\n').firstWhere(
          (line) => line.startsWith('الوقت المحدد:'),
          orElse: () => 'الوقت المحدد: —',
        );
        final outputLine = description.split('\n').firstWhere(
          (line) => line.startsWith('المخرج المطلوب:'),
          orElse: () => 'المخرج المطلوب: —',
        );
          officialRows.add({
            'taskId': '${task['id'] ?? ''}',
            '_task': task,
            'time': timeLine.replaceFirst('الوقت المحدد:', '').trim(),
            'title': '${task['title'] ?? 'مهمة'}',
            'output': _cleanOfficialOutput(
              '${task['title'] ?? 'مهمة'}',
              outputLine.replaceFirst('المخرج المطلوب:', ''),
            ),
            'statusKey': _normalizedStatus(task),
            'status': _statusLabels[_normalizedStatus(task)] ?? 'جديدة',
          });
      } else {
        for (final match in matches) {
          officialRows.add({
            'taskId': '${task['id'] ?? ''}',
            '_task': task,
            'time': match.group(1)?.trim() ?? 'غير محدد',
            'title': match.group(2)?.trim() ?? '—',
            'output': _cleanOfficialOutput(
              match.group(2)?.trim() ?? '—',
              match.group(3)?.trim() ?? '',
            ),
            'statusKey': _normalizedStatus(task),
            'status': _statusLabels[_normalizedStatus(task)] ?? 'جديدة',
          });
        }
      }
    }
    return Card(
      color: const Color(0xFFF8FBFA),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFD8E4E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: Directionality.of(context),
              children: [
                const Expanded(
                  child: Text(
                    'مؤسسة الشاعري للتجارة العامة · الجدول الرسمي',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _officialHeaderCollapsed = !_officialHeaderCollapsed),
                  icon: Icon(_officialHeaderCollapsed ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 17),
                  label: Text(_officialHeaderCollapsed ? 'إظهار' : 'إخفاء'),
                ),
              ],
            ),
            if (!_officialHeaderCollapsed) ...[
              const SizedBox(height: 4),
              const Text(
                'بيانات الموظف والاعتماد والهدف',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
              ),
              const SizedBox(height: 5),
              compactGrid(employeeFields),
              const SizedBox(height: 8),
              const Text(
                'ساعات الدوام والاستثناء الأسبوعي',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
              ),
              const SizedBox(height: 5),
              compactGrid(workFields),
            ],
            const SizedBox(height: 8),
            Table(
              textDirection: Directionality.of(context),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FlexColumnWidth(0.90),
                1: FlexColumnWidth(1.55),
                2: FlexColumnWidth(1.45),
                3: FlexColumnWidth(1.05),
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: Color(0xFFD8E4E0), width: 0.8),
              ),
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFEAF1EF)),
                  children: [
                    _officialCell('الوقت', bold: true, background: const Color(0xFFEAF1EF), singleLine: true),
                    _officialCell('المهمة والمسؤولية', bold: true, background: const Color(0xFFEAF1EF)),
                    _officialCell('المخرج المطلوب', bold: true, background: const Color(0xFFEAF1EF)),
                    _officialCell('الحالة', bold: true, background: const Color(0xFFEAF1EF)),
                  ],
                ),
                ...officialRows.map(
                  (row) => TableRow(
                    children: [
                      _officialCell(row['time'] ?? '—', singleLine: true),
                      _officialTextCell(
                        section: 'المهمة والمسؤولية',
                        time: row['time'] ?? '—',
                        text: row['title'] ?? '—',
                        row: row,
                      ),
                      _officialTextCell(
                        section: 'المخرج المطلوب',
                        time: row['time'] ?? '—',
                        text: row['output'] ?? '—',
                        row: row,
                      ),
                      Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                        alignment: Alignment.center,
                        child: _officialStatusChip(row['statusKey'] ?? 'pending', row['status'] ?? 'جديدة'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              textDirection: Directionality.of(context),
              children: [
                Expanded(
                  child: const Text(
                    'التفاصيل الإدارية للمهمة',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
                  ),
                ),
                IconButton(
                  tooltip: _administrativeDetailsCollapsed ? 'إظهار التفاصيل' : 'إخفاء التفاصيل',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _administrativeDetailsCollapsed
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19,
                    color: AppColors.navy,
                  ),
                  onPressed: () => setState(() {
                    _administrativeDetailsCollapsed = !_administrativeDetailsCollapsed;
                  }),
                ),
              ],
            ),
            if (!_administrativeDetailsCollapsed) ...[
              const SizedBox(height: 5),
              compactGrid(detailFields),
            ],
            const SizedBox(height: 6),
            Text(
              'التقرير اليومي: ${tasks.any((task) => task['report_required'] == true) ? 'نموذج جاهز مطلوب' : 'غير محدد'}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskLedger(List<Map<String, dynamic>> tasks) {
    final ordered = [...tasks]
      ..sort((a, b) {
        final left = '${a['updated_at'] ?? a['due_at'] ?? a['created_at'] ?? ''}';
        final right = '${b['updated_at'] ?? b['due_at'] ?? b['created_at'] ?? ''}';
        return _ledgerOrder == 'oldest' ? left.compareTo(right) : right.compareTo(left);
      });
    if (ordered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: Text('لا توجد سجلات في كشف المهام المطابق للبحث والمرشحات.')),
      );
    }
    final completed = ordered
        .where((task) => {'approved', 'completed'}.contains(_normalizedStatus(task)))
        .length;
    final submitted = ordered.where((task) => _reportByTask['${task['id']}']?['status'] == 'submitted').length;
    final pending = ordered.length - completed;
    final late = ordered.where((task) {
      final status = _normalizedStatus(task);
      final due = DateTime.tryParse('${task['due_at'] ?? ''}');
      return status != 'approved' && due != null && due.isBefore(DateTime.now());
    }).length;
    return Card(
      color: const Color(0xFFF8FBFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFD8E4E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              'كشف المهام · سجل محفوظ ومرتب',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'يشمل المهام التي أُنجزت والتقارير المرتبطة بها للرجوع والمراجعة.',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Wrap(
              textDirection: TextDirection.rtl,
              spacing: 6,
              runSpacing: 6,
              children: [
                _ledgerSummaryChip('الإجمالي', ordered.length, Icons.receipt_long_outlined),
                _ledgerSummaryChip('مكتملة', completed, Icons.verified_outlined),
                _ledgerSummaryChip('بانتظار المراجعة', submitted, Icons.fact_check),
                _ledgerSummaryChip('غير مكتملة', pending, Icons.pending_actions),
                _ledgerSummaryChip('متأخرة', late, Icons.schedule_outlined),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: DropdownButtonFormField<String>(
              value: _ledgerOrder,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ترتيب الكشف', isDense: true),
              items: const [
                DropdownMenuItem(value: 'latest', child: Text('الأحدث تحديثًا أولًا')),
                DropdownMenuItem(value: 'oldest', child: Text('الأقدم أولًا')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _ledgerOrder = value);
              },
            ),
          ),
          for (final task in ordered)
            _ledgerEntry(task),
        ],
      ),
    );
  }

  Widget _ledgerSummaryChip(String label, int count, IconData icon) => Chip(
    avatar: Icon(icon, size: 16, color: AppColors.green),
    label: Text('$label: $count'),
    visualDensity: VisualDensity.compact,
  );

  Widget _ledgerEntry(Map<String, dynamic> task) {
    final report = _reportByTask['${task['id']}'];
    final status = _normalizedStatus(task);
    final date = _formatLedgerDate(task['updated_at'] ?? task['due_at'] ?? task['created_at']);
    return InkWell(
      onTap: () => context.push('/tasks/${task['id']}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD8E4E0)),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            const Icon(Icons.receipt_long_outlined, color: AppColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${task['title'] ?? 'مهمة'}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
                  const SizedBox(height: 3),
                  Text('التاريخ: $date', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text('المهمة: ${_statusLabels[status] ?? uiStatusLabel(status)} · التقرير: ${_reportStatusLabel(report?['status'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_left),
          ],
        ),
      ),
    );
  }

  String _formatLedgerDate(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return 'غير محدد';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} · ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  String _reportStatusLabel(Object? status) => switch ('$status') {
    'submitted' => 'مرفوع للمراجعة',
    'approved' => 'معتمد',
    'returned' => 'معاد للاستكمال',
    _ => 'غير مرفوع',
  };
}
