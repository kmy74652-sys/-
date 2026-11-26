import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _name;
  String? _error;
  Map<String, int>? _summary;
  Set<String> _permissions = {};
  Set<String> _roles = {};
  RealtimeChannel? _tasksRealtime;
  Timer? _summaryRefreshTimer;
  int _request = 0;
  static const _homeCachePrefix = '@nexora/home-cache/v1/';

  static const _metrics = <_Metric>[
    _Metric(
      'all',
      'إجمالي المهام',
      Icons.task_alt,
      Color(0xFFE0ECFF),
      Color(0xFF164C80),
    ),
    _Metric(
      'in_progress',
      'قيد التنفيذ',
      Icons.play_circle_outline,
      Color(0xFFE2F3EE),
      Color(0xFF146B50),
    ),
    _Metric(
      'submitted',
      'بانتظار المراجعة',
      Icons.fact_check_outlined,
      Color(0xFFFFF0DC),
      Color(0xFF915511),
    ),
    _Metric(
      'late',
      'مهام متأخرة',
      Icons.schedule,
      Color(0xFFFFE2E7),
      Color(0xFFAB2B37),
    ),
    _Metric(
      'reports_pending',
      'تقارير غير معتمدة',
      Icons.pending_actions_outlined,
      Color(0xFFF0E7FF),
      Color(0xFF68419A),
    ),
  ];

  bool get _manageTasks => _permissions.contains('tasks.manage');
  bool _allowed(String key) {
    switch (key) {
      case 'tasks':
        return _manageTasks || _permissions.contains('tasks.execute');
      case 'reports':
        return _manageTasks
            ? (_permissions.contains('reports.read_all') ||
                  _permissions.contains('tasks.review'))
            : _permissions.contains('tasks.execute');
      default:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _subscribeToTaskChanges();
    _load();
  }

  void _subscribeToTaskChanges() {
    _tasksRealtime = Supabase.instance.client
        .channel('home-task-summary-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (_) => _scheduleSummaryRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_reports',
          callback: (_) => _scheduleSummaryRefresh(),
        )
      ..subscribe();
  }

  void _scheduleSummaryRefresh() {
    if (!mounted) return;
    _summaryRefreshTimer?.cancel();
    _summaryRefreshTimer = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    final ticket = ++_request;
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      if (mounted) context.go('/login');
      return;
    }
    final uid = client.auth.currentUser?.id;
    if (uid != null && _summary == null) await _restoreCache(uid);
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
    });
    try {
      final raw = await client.rpc('mobile_my_profile').timeout(
        const Duration(seconds: 10),
      );
      final root = raw is Map ? raw : const <dynamic, dynamic>{};
      final employee = root['employee'];
      if (employee is! Map)
        throw Exception(
          'الحساب غير مرتبط بملف موظف نشط. تواصل مع مسؤول النظام.',
        );
      final profile = Map<String, dynamic>.from(employee);
      final permissions = profile['permissions'] is List
          ? (profile['permissions'] as List).map((v) => v.toString()).toSet()
          : <String>{};
      final roles = profile['roles'] is List
          ? (profile['roles'] as List)
                .whereType<Map>()
                .map((r) => (r['code'] ?? '').toString())
                .toSet()
          : <String>{};
      final organization =
          (profile['institutionId'] ??
                  profile['institution_id'] ??
                  profile['organization_id'])
              ?.toString();
      final branch = _defaultBranch(profile);
      final name = (profile['fullName'] ?? profile['full_name'] ?? '')
          .toString();
      if (ticket != _request || !mounted) return;
      setState(() {
        _name = name;
        _permissions = permissions;
        _roles = roles;
      });

      final summary = await _loadSummary(
        client,
        organization,
        branch,
        permissions.contains('tasks.manage'),
        permissions.contains('tasks.execute'),
      ).timeout(const Duration(seconds: 12));
      if (ticket != _request || !mounted) return;
      setState(() {
        _summary = summary;
      });
      if (uid != null) await _saveCache(uid);
    } catch (e) {
      if (ticket == _request && mounted)
        setState(() => _error = _friendlyNetworkError(e));
    } finally {
      if (ticket == _request && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restoreCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_homeCachePrefix$uid');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final summary = map['summary'];
      if (summary is! Map) return;
      final cachedSummary = <String, int>{};
      for (final entry in summary.entries) {
        final value = entry.value;
        if (value is num) cachedSummary[entry.key.toString()] = value.toInt();
      }
      if (cachedSummary.isEmpty || !mounted) return;
      final permissions = map['permissions'];
      final roles = map['roles'];
      setState(() {
        _name = map['name']?.toString();
        _summary = cachedSummary;
        _permissions = permissions is List
            ? permissions.map((value) => value.toString()).toSet()
            : <String>{};
        _roles = roles is List
            ? roles.map((value) => value.toString()).toSet()
            : <String>{};
        _loading = false;
        _error = 'لا يوجد اتصال حاليًا. الأرقام المعروضة من آخر تحديث محفوظ.';
      });
    } catch (_) {
      // Cache failures must never prevent the online load.
    }
  }

  Future<void> _saveCache(String uid) async {
    final summary = _summary;
    if (summary == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_homeCachePrefix$uid',
        jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'name': _name,
          'permissions': _permissions.toList(),
          'roles': _roles.toList(),
          'summary': summary,
        }),
      );
    } catch (_) {
      // Online data remains valid even if local storage is unavailable.
    }
  }

  String _friendlyNetworkError(Object error) {
    final message = error.toString();
    final networkError = message.contains('AuthRetryableFetchException') ||
        message.contains('SocketFailed') ||
        message.contains('Failed host lookup') ||
        message.contains('SocketException') ||
        message.contains('TimeoutException') ||
        message.contains('statusCode: null');
    if (networkError) {
      return _summary == null
          ? 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة ثم اضغط إعادة المحاولة.'
          : 'تعذر تحديث البيانات بسبب ضعف الاتصال. الأرقام المعروضة من آخر تحديث محفوظ.';
    }
    return message.replaceFirst('Exception: ', '');
  }

  String? _defaultBranch(Map<String, dynamic> profile) {
    final value = profile['branches'];
    if (value is! List) return null;
    for (final item in value.whereType<Map>()) {
      if (item['isDefault'] == true || item['is_default'] == true) {
        final id = item['id'];
        if (id != null && id.toString().isNotEmpty) return id.toString();
      }
    }
    return null;
  }

  Future<Map<String, int>> _loadSummary(
    SupabaseClient client,
    String? organization,
    String? branch,
    bool manages,
    bool executes,
  ) async {
    if (!manages && !executes)
      return {
        'all': 0,
        'in_progress': 0,
        'submitted': 0,
        'late': 0,
        'reports_pending': 0,
      };
    final user = client.auth.currentUser;
    if (user == null) throw Exception('انتهت الجلسة. سجّل الدخول مجددًا.');
    if (organization == null || organization.isEmpty)
      throw Exception('تعذر تحديد المؤسسة المرتبطة بالحساب.');
    const pageSize = 500;
    final tasks = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      var query = client
          .from('tasks')
          .select('id,status,due_at')
          .eq('organization_id', organization);
      query = query.isFilter('deleted_at', null);
      if (!manages) query = query.eq('assigned_to', user.id);
      if (branch != null) query = query.eq('branch_id', branch);
      final page = await query.order('id').range(offset, offset + pageSize - 1);
      tasks.addAll(
        (page as List).whereType<Map>().map(
          (row) => Map<String, dynamic>.from(row),
        ),
      );
      if ((page as List).length < pageSize) break;
    }
    final reviewIds = <String>{};
    for (var start = 0; start < tasks.length; start += 200) {
      final ids = tasks
          .skip(start)
          .take(200)
          .map((t) => t['id'].toString())
          .toList();
      for (var offset = 0; ; offset += pageSize) {
        final rows = await client
            .from('task_reports')
            .select('id,task_id')
            .inFilter('task_id', ids)
            .eq('status', 'submitted')
            .order('id')
            .range(offset, offset + pageSize - 1);
        for (final row in (rows as List).whereType<Map>()) {
          if (row['task_id'] != null) reviewIds.add(row['task_id'].toString());
        }
        if ((rows as List).length < pageSize) break;
      }
    }
    final now = DateTime.now().toUtc();
    var active = 0, submitted = 0, late = 0;
    for (final task in tasks) {
      final status = _normalizeStatus((task['status'] ?? '').toString());
      if (status == 'in_progress') active++;
      final id = task['id']?.toString();
      if (status == 'submitted' || (id != null && reviewIds.contains(id)))
        submitted++;
      final due = DateTime.tryParse((task['due_at'] ?? '').toString())?.toUtc();
      if (status == 'late' ||
          (!{'approved', 'cancelled'}.contains(status) &&
              due != null &&
              due.isBefore(now)))
        late++;
    }
    return {
      'all': tasks.length,
      'in_progress': active,
      'submitted': submitted,
      'late': late,
      'reports_pending': submitted,
    };
  }

  String _normalizeStatus(String status) =>
      const {
        'new': 'pending',
        'received': 'pending',
        'on_hold': 'in_progress',
        'report_submitted': 'submitted',
        'completed_approved': 'approved',
        'needs_revision': 'rejected',
      }[status] ??
      status;

  @override
  void dispose() {
    _request++;
    _summaryRefreshTimer?.cancel();
    final channel = _tasksRealtime;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'الرئيسية',
    subtitle: _name == null || _name!.isEmpty
        ? 'بوابة العمل والتواصل الإداري'
        : 'مرحبًا ${_name!}',
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 22),
        children: [
          if (_error != null)
            SectionCard(
              title: 'تعذر تحديث الرئيسية',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!, textAlign: TextAlign.right),
                  if (_summary != null)
                    const Text(
                      'الأرقام المعروضة من آخر تحديث ناجح.',
                      textAlign: TextAlign.right,
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              ),
            ),
          if (_loading && _summary == null)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(),
              ),
            _metricGrid(),
          ],
        ],
      ),
    ),
  );

  Widget _metricGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final visibleMetrics = _metrics
          .where((item) => item.key != 'reports_pending' || _manageTasks)
          .toList();
      final width = constraints.maxWidth;
      if (width < 560) {
        const gap = 7.0;
        final cardWidth = (width - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          textDirection: TextDirection.rtl,
          children: [
            for (var index = 0; index < visibleMetrics.length; index++)
              SizedBox(
                width: index == visibleMetrics.length - 1 &&
                        visibleMetrics.length.isOdd
                    ? width
                    : cardWidth,
                child: _metricCard(visibleMetrics[index], width < 370),
              ),
          ],
        );
      }
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: visibleMetrics.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 7,
          mainAxisSpacing: 7,
          childAspectRatio: 1.35,
        ),
        itemBuilder: (context, index) => _metricCard(visibleMetrics[index], false),
      );
    },
  );

  Widget _metricCard(_Metric item, bool compact) => Material(
    color: item.background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: BorderSide(color: item.foreground.withOpacity(0.15)),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: _allowed(item.key == 'reports_pending' ? 'reports' : 'tasks')
          ? () {
              if (item.key == 'reports_pending') {
                context.go('/reports?status=submitted');
                return;
              }
              if (item.key == 'submitted') {
                context.go('/tasks?status=submitted');
                return;
              }
              if (item.key == 'in_progress') {
                context.go('/tasks?status=in_progress');
                return;
              }
              if (item.key == 'late') {
                context.go('/tasks?status=late');
                return;
              }
              if (item.key == 'all') {
                context.go('/tasks');
                return;
              }
              final route = _manageTasks ? '/admin/tasks' : '/tasks';
              final status = switch (item.key) {
                'in_progress' => 'in_progress',
                'submitted' => 'submitted',
                'late' => 'late',
                _ => null,
              };
              context.go(
                status == null ? route : '$route?status=$status',
              );
            }
          : null,
      child: SizedBox(
        height: compact ? 108 : 126,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, color: item.foreground, size: compact ? 23 : 29),
              Text(
                _summary?[item.key]?.toString() ?? '—',
                style: TextStyle(
                  fontSize: compact ? 23 : 29,
                  fontWeight: FontWeight.w900,
                  color: item.foreground,
                ),
              ),
              Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10.5 : 12,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: item.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

}

class _Metric {
  const _Metric(
    this.key,
    this.title,
    this.icon,
    this.background,
    this.foreground,
  );
  final String key, title;
  final IconData icon;
  final Color background, foreground;
}
