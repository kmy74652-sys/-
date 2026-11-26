import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notifications_repository.dart';
import '../core/notifications_runtime.dart';
import '../core/theme.dart';
import 'app_customizer.dart';
import 'organization_branding.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onBeforeNavigate,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Future<bool> Function()? onBeforeNavigate;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _unreadCount = 0;
  Set<String> _permissions = <String>{};
  bool _navigationLoading = true;

  Future<List<_GlobalSearchResult>> _globalSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2) return const [];
    final client = Supabase.instance.client;
    final results = <_GlobalSearchResult>[];
    String? organizationId;
    try {
      final profile = await client.rpc('mobile_my_profile');
      final employee = profile is Map ? profile['employee'] : null;
      if (employee is Map) {
        organizationId = (employee['institutionId'] ??
                employee['institution_id'] ??
                employee['organization_id'])
            ?.toString();
      }
    } catch (_) {}

    Future<void> loadEmployees() async {
      if (organizationId == null || organizationId.isEmpty) return;
      try {
        final rows = await client
            .from('organization_memberships')
            .select('id,user_id,display_name,employee_no')
            .eq('organization_id', organizationId)
            .eq('is_active', true)
            .or('display_name.ilike.%$query%,employee_no.ilike.%$query%')
            .limit(20);
        for (final row in rows.whereType<Map>()) {
          final data = Map<String, dynamic>.from(row);
          results.add(_GlobalSearchResult(
            type: 'الموظفون',
            title: '${data['display_name'] ?? 'موظف'}',
            subtitle: 'رقم الموظف: ${data['employee_no'] ?? '—'}',
            icon: Icons.person_outline,
            route: '/admin?section=employees',
          ));
        }
      } catch (_) {}
    }

    Future<void> loadTasks() async {
      if (organizationId == null || organizationId.isEmpty) return;
      try {
        final rows = await client
            .from('tasks')
            .select('id,title,description,status')
            .eq('organization_id', organizationId)
            .isFilter('deleted_at', null)
            .or('title.ilike.%$query%,description.ilike.%$query%')
            .order('updated_at', ascending: false)
            .limit(20);
        for (final row in rows.whereType<Map>()) {
          final data = Map<String, dynamic>.from(row);
          final id = '${data['id'] ?? ''}';
          results.add(_GlobalSearchResult(
            type: 'المهام',
            title: '${data['title'] ?? 'مهمة'}',
            subtitle: 'الحالة: ${data['status'] ?? '—'} · السجل: $id',
            icon: Icons.task_alt_outlined,
            route: id.isEmpty ? '/tasks' : '/tasks/$id',
          ));
        }
      } catch (_) {}
    }

    Future<void> loadReports() async {
      try {
        final rows = await client
            .from('task_reports')
            .select('id,task_id,status,submitted_at,review_note')
            .or('status.ilike.%$query%,review_note.ilike.%$query%')
            .order('submitted_at', ascending: false)
            .limit(20);
        for (final row in rows.whereType<Map>()) {
          final data = Map<String, dynamic>.from(row);
          results.add(_GlobalSearchResult(
            type: 'التقارير',
            title: 'تقرير رقم ${data['id'] ?? '—'}',
            subtitle: 'الحالة: ${data['status'] ?? '—'} · المهمة: ${data['task_id'] ?? '—'}',
            icon: Icons.description_outlined,
            route: '/reports?status=${data['status'] ?? 'submitted'}',
          ));
        }
      } catch (_) {}
    }

    Future<void> loadBranches() async {
      if (organizationId == null || organizationId.isEmpty) return;
      try {
        final rows = await client
            .from('branches')
            .select('id,name,code')
            .eq('organization_id', organizationId)
            .or('name.ilike.%$query%,code.ilike.%$query%')
            .limit(20);
        for (final row in rows.whereType<Map>()) {
          final data = Map<String, dynamic>.from(row);
          results.add(_GlobalSearchResult(
            type: 'الفروع',
            title: '${data['name'] ?? 'فرع'}',
            subtitle: 'الرمز: ${data['code'] ?? '—'}',
            icon: Icons.account_tree_outlined,
            route: '/admin?section=branches',
          ));
        }
      } catch (_) {}
    }

    Future<void> loadTemplates() async {
      if (organizationId == null || organizationId.isEmpty) return;
      try {
        final rows = await client
            .from('report_form_templates')
            .select('id,title,role_code')
            .eq('organization_id', organizationId)
            .or('title.ilike.%$query%,role_code.ilike.%$query%')
            .limit(20);
        for (final row in rows.whereType<Map>()) {
          final data = Map<String, dynamic>.from(row);
          results.add(_GlobalSearchResult(
            type: 'القوالب',
            title: '${data['title'] ?? 'قالب تقرير'}',
            subtitle: 'الدور: ${data['role_code'] ?? '—'} · السجل: ${data['id'] ?? '—'}',
            icon: Icons.article_outlined,
            route: '/admin/report-designer',
          ));
        }
      } catch (_) {}
    }

    await Future.wait([
      loadEmployees(),
      loadTasks(),
      loadReports(),
      loadBranches(),
      loadTemplates(),
    ]);
    const typeOrder = ['الموظفون', 'المهام', 'التقارير', 'الفروع', 'القوالب'];
    results.sort(
      (a, b) => typeOrder.indexOf(a.type).compareTo(typeOrder.indexOf(b.type)),
    );
    return results;
  }

  Future<void> _showGlobalSearch() async {
    final controller = TextEditingController();
    List<_GlobalSearchResult> results = const [];
    var busy = false;
    var searched = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('بحث عام داخل التطبيق'),
            content: SizedBox(
              width: 560,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textAlign: TextAlign.right,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'موظف، مهمة، تقرير، فرع، قالب أو رقم سجل',
                        prefixIcon: busy
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                tooltip: 'بحث',
                                onPressed: () async {
                                  if (controller.text.trim().length < 2) return;
                                  setDialogState(() {
                                    busy = true;
                                    searched = true;
                                  });
                                  final found = await _globalSearch(controller.text);
                                  if (dialogContext.mounted) {
                                    setDialogState(() {
                                      results = found;
                                      busy = false;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.search),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) async {
                        if (controller.text.trim().length < 2) return;
                        setDialogState(() {
                          busy = true;
                          searched = true;
                        });
                        final found = await _globalSearch(controller.text);
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            results = found;
                            busy = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (!searched)
                      const Text('اكتب كلمتين على الأقل ثم اضغط بحث.', textAlign: TextAlign.right)
                    else if (!busy && results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('لا توجد نتائج مطابقة في البيانات المسموح بها.', textAlign: TextAlign.center),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final result = results[index];
                            return ListTile(
                              leading: Icon(result.icon, color: AppColors.navy),
                              title: Text(result.title, textAlign: TextAlign.right),
                              subtitle: Text('${result.type} · ${result.subtitle}', textAlign: TextAlign.right),
                              onTap: () {
                                Navigator.of(dialogContext).pop();
                                context.go(result.route);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppCustomizer.instance.load();
    _loadNavigationAccess();
    _refreshUnreadCount();
    NotificationsRuntime.start(onOpen: _openTaskFromNotification);
  }

  Future<void> _loadNavigationAccess() async {
    try {
      final raw = await Supabase.instance.client.rpc('mobile_my_profile');
      final employee = raw is Map ? raw['employee'] : null;
      if (employee is Map) {
        final permissions = employee['permissions'];
        if (mounted) {
          setState(() {
            _permissions = permissions is List
                ? permissions.map((value) => '$value').toSet()
                : <String>{};
            _navigationLoading = false;
          });
        }
        return;
      }
    } catch (_) {
      // The destination screens still enforce their own permissions.
    }
    if (mounted) setState(() => _navigationLoading = false);
  }

  bool _can(String permission) => _permissions.contains(permission);

  bool get _managesTasks => _can('tasks.manage');

  bool get _canCustomizer => _managesTasks && _can('customizer.manage');

  List<_NavigationItem> _navigationItems() {
    final items = <_NavigationItem>[
      const _NavigationItem('الرئيسية', '/', Icons.home_outlined),
    ];
    if (_canCustomizer) {
      items.add(
        const _NavigationItem(
          'تخصيص الواجهات',
          '/admin/customizer',
          Icons.palette_outlined,
        ),
      );
    }
    return items;
  }

  Future<void> _openNavigationDrawer(String route) async {
    _scaffoldKey.currentState?.closeDrawer();
    await _navigate(route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationsRuntime.stop();
    super.dispose();
  }

  void _openTaskFromNotification(String? taskId) {
    if (!mounted || taskId == null || taskId.isEmpty) return;
    context.go('/tasks/$taskId');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUnreadCount();
  }

  Future<void> _refreshUnreadCount() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final items = await NotificationsRepository.load(uid: uid);
      if (mounted) {
        setState(
          () => _unreadCount = items.where((item) => item.isUnread).length,
        );
      }
    } catch (_) {
      final cached = await NotificationsRepository.loadCached(uid);
      if (mounted && cached != null) {
        setState(
          () => _unreadCount = cached.where((item) => item.isUnread).length,
        );
      }
    }
  }

  List<_ShellTab> _tabs() => [
        _ShellTab('/', AppCustomizer.instance.label('home'), Icons.home_outlined),
        _ShellTab('/tasks', AppCustomizer.instance.label('tasks'), Icons.task_alt_outlined),
        _ShellTab('/settings', 'الإعدادات', Icons.settings_outlined),
      ];

  int _selectedIndex(String path) {
    if (path == '/tasks' || path.startsWith('/tasks/')) return 1;
    if (path == '/settings' || path.startsWith('/settings/')) return 2;
    if (path == '/' || path.isEmpty) return 0;
    // الإدارة والتقارير والتحليلات مسارات داخلية وتُحسب بصريًا على الرئيسية.
    return 0;
  }

  String? _backRoute(String path) {
    switch (path) {
      case '/':
      case '/tasks':
      case '/reports':
      case '/reports/independent':
      case '/hr':
      case '/settings':
        return null;
      case '/admin/tasks':
      case '/admin/unified-task-management':
      case '/admin/performance':
      case '/admin/report-designer':
        return '/admin';
      case '/admin/customizer':
        return '/settings';
      case '/admin':
        return '/';
    }
    if (path.startsWith('/tasks/')) {
      return _managesTasks ? '/admin/tasks' : '/tasks';
    }
    return '/';
  }

  List<_Breadcrumb> _breadcrumbs(Uri uri) {
    final path = uri.path;
    if (path == '/') return const [_Breadcrumb('الرئيسية')];
    if (path.startsWith('/tasks/')) {
      return [
        _Breadcrumb('الرئيسية', '/'),
        _Breadcrumb(
          'المهام والمتابعة',
          _managesTasks ? '/admin/tasks' : '/tasks',
        ),
        _Breadcrumb('تفاصيل المهمة'),
      ];
    }
    if (path == '/tasks') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('المهام والمتابعة')];
    }
    if (path == '/reports' || path == '/reports/independent') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('التقارير')];
    }
    if (path == '/admin' && uri.queryParameters['section'] == 'employees') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('الموظفون')];
    }
    if (path == '/admin') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('الإدارة والتحليلات')];
    }
    if (path == '/admin/tasks') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('المهام والمتابعة')];
    }
    if (path == '/admin/unified-task-management') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('الجداول الموحدة')];
    }
    if (path == '/admin/performance') {
      return const [
        _Breadcrumb('الرئيسية', '/'),
        _Breadcrumb('الإدارة والتحليلات', '/admin'),
        _Breadcrumb('تحليلات الأداء'),
      ];
    }
    if (path == '/admin/report-designer') {
      return const [
        _Breadcrumb('الرئيسية', '/'),
        _Breadcrumb('الإدارة والتحليلات', '/admin'),
        _Breadcrumb('مصمم التقارير'),
      ];
    }
    if (path == '/admin/customizer') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('الإعدادات'), _Breadcrumb('تخصيص التطبيق')];
    }
    if (path == '/hr') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('الموارد البشرية')];
    }
    if (path == '/settings') {
      return const [_Breadcrumb('الرئيسية', '/'), _Breadcrumb('الإعدادات')];
    }
    return const [_Breadcrumb('الرئيسية', '/')];
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // A failed network sign-out should not trap the user on a protected page.
    } finally {
      if (context.mounted) context.go('/login');
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من حسابك الحالي؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await _signOut(context);
  }

  Future<void> _showNotifications(BuildContext context) async {
    List<AppNotification> notifications = <AppNotification>[];
    var failed = false;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      if (uid == null) {
        failed = true;
      } else {
        notifications = await NotificationsRepository.load(uid: uid);
      }
    } catch (_) {
      if (uid != null) {
        notifications = await NotificationsRepository.loadCached(uid) ?? [];
      }
      failed = notifications.isEmpty;
    }
    if (mounted) {
      setState(
        () =>
            _unreadCount = notifications.where((item) => item.isUnread).length,
      );
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.68,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'التنبيهات',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0B3458),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق التنبيهات',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: failed
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'تعذر تحميل التنبيهات حالياً.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _showNotifications(context);
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : notifications.isEmpty
                    ? const Center(child: Text('لا توجد تنبيهات.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = notifications[index];
                          final isUnread = item.isUnread;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 5,
                            ),
                            leading: Icon(
                              isUnread
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_none,
                              color: isUnread
                                  ? const Color(0xFF0B3458)
                                  : AppColors.muted,
                            ),
                            title: Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: item.body == null
                                ? null
                                : Text(
                                    item.body!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: item.severity == null
                                ? null
                                : Text(
                                    item.severity!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                    ),
                                  ),
                            onTap: () async {
                              try {
                                await NotificationsRepository.markRead(item.id);
                                if (mounted && item.isUnread) {
                                  setState(
                                    () => _unreadCount = (_unreadCount - 1)
                                        .clamp(0, 999999)
                                        .toInt(),
                                  );
                                }
                              } catch (_) {
                                // لا يمنع فشل الشبكة قراءة الإشعار أو فتح المهمة.
                              }
                              final taskId = item.taskId;
                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              if (taskId != null && taskId.isNotEmpty) {
                                NotificationsRepository.markTaskOpened(taskId);
                                context.go('/tasks/$taskId');
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigate(String route) async {
    final current = GoRouterState.of(context).uri.path;
    if (route == current) return;
    final allowed = await widget.onBeforeNavigate?.call() ?? true;
    if (allowed && mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri;
    final path = location.path;
    final selected = _selectedIndex(path);
    final tabs = _tabs();
    final breadcrumbs = _breadcrumbs(location);
    return AnimatedBuilder(
      animation: AppCustomizer.instance,
      builder: (context, _) {
        return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF5F7FD),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                children: [
                  _BrandHeader(
                    unreadCount: _unreadCount,
                    onAccount: () => _confirmSignOut(context),
                    onNotifications: () => _showNotifications(context),
                    onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                    onSearch: _showGlobalSearch,
                  ),
                  _PageTitleBar(
                    title: widget.title,
                    subtitle: widget.subtitle,
                    breadcrumbs: breadcrumbs,
                    onBack: _backRoute(path) == null
                        ? null
                        : () => _navigate(_backRoute(path)!),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        drawer: _NavigationDrawer(
          loading: _navigationLoading,
          items: _navigationItems(),
          currentPath: path,
          onNavigate: _openNavigationDrawer,
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B3458),
            border: Border(top: BorderSide(color: Color(0xFFDBA62A), width: 2)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 62,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _BottomTab(
                        tab: tabs[i],
                        selected: selected == i,
                        onTap: () => _navigate(tabs[i].route),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ),
        );
      },
    );
  }
}

class _ShellTab {
  const _ShellTab(this.route, this.label, this.icon);
  final String route;
  final String label;
  final IconData icon;
}

class _BrandHeader extends StatefulWidget {
  const _BrandHeader({
    required this.unreadCount,
    required this.onAccount,
    required this.onNotifications,
    required this.onMenu,
    required this.onSearch,
  });

  final int unreadCount;
  final VoidCallback onAccount;
  final VoidCallback onNotifications;
  final VoidCallback onMenu;
  final VoidCallback onSearch;

  @override
  State<_BrandHeader> createState() => _BrandHeaderState();
}

class _BrandHeaderState extends State<_BrandHeader> {
  late Future<OrganizationBranding> _branding;
  static const _navy = Color(0xFF0B3458);
  static const _gold = Color(0xFFDBA62A);

  @override
  void initState() {
    super.initState();
    _branding = OrganizationBrandingStore.instance.forSession();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 370;
    return FutureBuilder<OrganizationBranding>(
      future: _branding,
      builder: (context, snapshot) {
        final branding = snapshot.data ?? OrganizationBranding.fallback;
        final controlSize = compact ? 36.0 : 42.0;
        final controlGap = compact ? 3.0 : 6.0;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 8),
          decoration: const BoxDecoration(color: Colors.white),
          child: Row(
            children: [
              _BrandLogo(url: branding.logoUrl, width: compact ? 44 : 58, height: compact ? 52 : 66),
              SizedBox(width: compact ? 6 : 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(AppCustomizer.instance.label('appName'), maxLines: 1, overflow: TextOverflow.fade,
                      style: TextStyle(color: _navy, fontSize: compact ? 17 : 21, height: 1.15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      AppCustomizer.instance.label('organizationName'),
                      maxLines: 2,
                      softWrap: true,
                      textWidthBasis: TextWidthBasis.parent,
                      style: TextStyle(
                        color: _navy,
                        fontSize: compact ? 10.5 : 11.5,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(width: 14, height: 1.2, color: _gold),
                      const SizedBox(width: 5),
                      Flexible(child: Text(AppCustomizer.instance.label('tagline'), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF9A6814), fontSize: 10, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 5),
                      Container(width: 14, height: 1.2, color: _gold),
                    ]),
                  ],
                ),
              ),
              SizedBox(width: compact ? 4 : 8),
              IconButton(
                tooltip: 'لوحة التنقل',
                onPressed: widget.onMenu,
                style: IconButton.styleFrom(
                  fixedSize: Size.square(controlSize),
                  backgroundColor: const Color(0xFFF4F8FB),
                  foregroundColor: _navy,
                  side: const BorderSide(color: Color(0xFFD5E0EA)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.menu_rounded, size: 23),
              ),
              SizedBox(width: controlGap),
              IconButton(
                tooltip: 'بحث عام',
                onPressed: widget.onSearch,
                style: IconButton.styleFrom(
                  fixedSize: Size.square(controlSize),
                  backgroundColor: const Color(0xFFF4F8FB),
                  foregroundColor: _navy,
                  side: const BorderSide(color: Color(0xFFD5E0EA)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.search, size: 23),
              ),
              SizedBox(width: controlGap),
              IconButton(
                tooltip: 'تبديل الحساب: تسجيل الخروج',
                onPressed: widget.onAccount,
                style: IconButton.styleFrom(fixedSize: Size.square(controlSize), backgroundColor: const Color(0xFFF4F8FB), foregroundColor: _navy, side: const BorderSide(color: Color(0xFFD5E0EA)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.account_circle_outlined, size: 23),
              ),
              SizedBox(width: controlGap),
              IconButton(
                tooltip: 'التنبيهات',
                onPressed: widget.onNotifications,
                style: IconButton.styleFrom(fixedSize: Size.square(controlSize), backgroundColor: _navy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: Stack(clipBehavior: Clip.none, children: [
                  const Icon(Icons.notifications_none, size: 24),
                  if (widget.unreadCount > 0) Positioned(top: -8, left: -9, child: Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(10)),
                    child: Text(widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}', textAlign: TextAlign.center,
                      style: const TextStyle(color: _navy, fontSize: 10, fontWeight: FontWeight.w900)),
                  )),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.url, required this.width, required this.height});
  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset('assets/images/nexora-logo.png', width: width, height: height, fit: BoxFit.contain, semanticLabel: 'شعار NEXORA');
    if (url == null) return fallback;
    return Image.network(url!, width: width, height: height, fit: BoxFit.contain, semanticLabel: 'شعار المؤسسة', errorBuilder: (_, __, ___) => fallback);
  }
}

/// Slim page-title strip under the brand header: back button (on inner
/// pages), page title and an optional one-line subtitle.
class _GlobalSearchResult {
  const _GlobalSearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}

class _Breadcrumb {
  const _Breadcrumb(this.label, [this.route]);

  final String label;
  final String? route;
}

class _PageTitleBar extends StatelessWidget {
  const _PageTitleBar({
    required this.title,
    this.subtitle,
    this.breadcrumbs = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<_Breadcrumb> breadcrumbs;
  final VoidCallback? onBack;

  static const _orgName = 'مؤسسة الشاعري للتجارة العامة';

  @override
  Widget build(BuildContext context) {
    final sub = subtitle?.trim() ?? '';
    final showSub = sub.isNotEmpty && sub != _orgName && sub != title;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        onBack == null ? 16 : 6,
        8,
        16,
        breadcrumbs.length > 1 ? 7 : 8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFD),
        border: Border(
          top: BorderSide(color: Color(0xFFE4EAF0)),
          bottom: BorderSide(color: Color(0xFFE4EAF0)),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'رجوع',
              onPressed: onBack,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.arrow_back,
                size: 22,
                color: Color(0xFF0B3458),
              ),
            ),
          Container(
            width: 4,
            height: showSub ? 34 : 22,
            margin: const EdgeInsetsDirectional.only(end: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFDBA62A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B3458),
                    fontSize: 17,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (showSub)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF637188),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                if (breadcrumbs.length > 1) ...[
                  const SizedBox(height: 5),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        for (var i = 0; i < breadcrumbs.length; i++) ...[
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(
                                Icons.chevron_left,
                                size: 15,
                                color: Color(0xFF8A98A8),
                              ),
                            ),
                          InkWell(
                            onTap: breadcrumbs[i].route == null
                                ? null
                                : () => context.go(breadcrumbs[i].route!),
                            child: Text(
                              breadcrumbs[i].label,
                              style: TextStyle(
                                color: breadcrumbs[i].route == null
                                    ? const Color(0xFF637188)
                                    : const Color(0xFF0B568C),
                                fontSize: 10.5,
                                fontWeight: breadcrumbs[i].route == null
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem(this.label, this.route, this.icon);

  final String label;
  final String route;
  final IconData icon;
}

class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer({
    required this.loading,
    required this.items,
    required this.currentPath,
    required this.onNavigate,
  });

  final bool loading;
  final List<_NavigationItem> items;
  final String currentPath;
  final Future<void> Function(String route) onNavigate;

  bool _selected(_NavigationItem item) {
    if (item.route == '/') return currentPath == '/';
    final routePath = item.route.split('?').first;
    return currentPath == routePath || currentPath.startsWith('$routePath/');
  }

  @override
  Widget build(BuildContext context) => Drawer(
        child: SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B3458),
                    border: Border(bottom: BorderSide(color: Color(0xFFDBA62A), width: 3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'NEXORA',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'لوحة التنقل الموحدة',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Color(0xFFFFD36A), fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 18),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final selected = _selected(item);
                        return ListTile(
                          selected: selected,
                          selectedTileColor: const Color(0xFFEAF1F8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: Icon(
                            item.icon,
                            color: selected ? const Color(0xFF0B3458) : AppColors.muted,
                          ),
                          title: Text(
                            item.label,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: selected ? const Color(0xFF0B3458) : null,
                              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_left,
                            color: selected ? const Color(0xFFDBA62A) : AppColors.muted,
                          ),
                          onTap: () => onNavigate(item.route),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });
  final _ShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: tab.label,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tab.icon,
              size: 22,
              color: selected ? const Color(0xFFFFD36A) : Colors.white70,
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? const Color(0xFFFFD36A) : Colors.white70,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
