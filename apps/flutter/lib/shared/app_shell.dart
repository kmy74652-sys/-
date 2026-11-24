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
  Set<String> _roles = <String>{};
  bool _navigationLoading = true;

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
        final roles = employee['roles'];
        if (mounted) {
          setState(() {
            _permissions = permissions is List
                ? permissions.map((value) => '$value').toSet()
                : <String>{};
            _roles = roles is List
                ? roles
                    .whereType<Map>()
                    .map((role) => '${role['code'] ?? ''}')
                    .where((code) => code.isNotEmpty)
                    .toSet()
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

  bool get _canEmployees =>
      _managesTasks && (_can('employees.read') || _can('employees.manage'));

  bool get _canReports =>
      _managesTasks &&
          (_can('reports.read_all') || _can('tasks.review')) ||
      (!_managesTasks && _can('tasks.execute'));

  bool get _canAdministration =>
      _managesTasks &&
      (_can('tasks.review') ||
          _can('reports.read_all') ||
          _can('employees.read') ||
          _can('branches.read_all') ||
          _can('audit.read'));

  bool get _canHr =>
      (_roles.contains('owner') || _roles.contains('admin_followup')) &&
      _can('employees.manage') &&
      _can('employee_hr.read_all');

  bool get _canSettings =>
      (_roles.contains('owner') || _roles.contains('admin_followup')) &&
      _can('employees.manage');

  List<_NavigationItem> _navigationItems() {
    final items = <_NavigationItem>[
      const _NavigationItem('الرئيسية', '/', Icons.home_outlined),
    ];
    if (_managesTasks || _can('tasks.execute')) {
      items.add(
        _NavigationItem(
          'المهام والمتابعة',
          _managesTasks ? '/admin/tasks' : '/tasks',
          Icons.task_alt_outlined,
        ),
      );
    }
    if (_canReports) {
      items.add(
        _NavigationItem(
          'التقارير',
          _managesTasks ? '/reports' : '/reports/independent',
          Icons.description_outlined,
        ),
      );
    }
    if (_canEmployees) {
      items.add(
        const _NavigationItem('الموظفون', '/admin?section=employees', Icons.people_outline),
      );
    }
    if (_managesTasks) {
      items.add(
        const _NavigationItem(
          'الجداول الموحدة',
          '/admin/unified-task-management',
          Icons.table_chart_outlined,
        ),
      );
    }
    if (_canAdministration) {
      items.add(
        const _NavigationItem(
          'الإدارة والتحليلات',
          '/admin',
          Icons.analytics_outlined,
        ),
      );
    }
    if (_canHr) {
      items.add(
        const _NavigationItem('الموارد البشرية', '/hr', Icons.badge_outlined),
      );
    }
    if (_canSettings) {
      items.add(
        const _NavigationItem('الإعدادات', '/settings', Icons.settings_outlined),
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

  /// Parent route for pages that are not one of the bottom-navigation roots.
  /// Returns null on root pages so no back button is shown there.
  String? _backRoute(String path) {
    const roots = {'/', '/settings', '/tasks'};
    if (path.isEmpty || roots.contains(path)) return null;
    final segments = path.split('/').where((e) => e.isNotEmpty).toList();
    if (segments.length <= 1) return '/';
    final parent = '/${segments.sublist(0, segments.length - 1).join('/')}';
    return parent;
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
    final path = GoRouterState.of(context).uri.path;
    final selected = _selectedIndex(path);
    final tabs = _tabs();
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
                  ),
                  _PageTitleBar(
                    title: widget.title,
                    subtitle: widget.subtitle,
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
  });

  final int unreadCount;
  final VoidCallback onAccount;
  final VoidCallback onNotifications;
  final VoidCallback onMenu;

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
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 8),
          decoration: const BoxDecoration(color: Colors.white),
          child: Row(
            children: [
              _BrandLogo(url: branding.logoUrl, width: compact ? 50 : 58, height: compact ? 58 : 66),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppCustomizer.instance.label('appName'), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _navy, fontSize: compact ? 18 : 21, height: 1.15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(AppCustomizer.instance.label('organizationName'), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _navy, fontSize: 12, height: 1.2, fontWeight: FontWeight.w700)),
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
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'لوحة التنقل',
                onPressed: widget.onMenu,
                style: IconButton.styleFrom(
                  fixedSize: const Size(42, 42),
                  backgroundColor: const Color(0xFFF4F8FB),
                  foregroundColor: _navy,
                  side: const BorderSide(color: Color(0xFFD5E0EA)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.menu_rounded, size: 23),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'تبديل الحساب: تسجيل الخروج',
                onPressed: widget.onAccount,
                style: IconButton.styleFrom(fixedSize: const Size(42, 42), backgroundColor: const Color(0xFFF4F8FB), foregroundColor: _navy, side: const BorderSide(color: Color(0xFFD5E0EA)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.account_circle_outlined, size: 23),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'التنبيهات',
                onPressed: widget.onNotifications,
                style: IconButton.styleFrom(fixedSize: const Size(42, 42), backgroundColor: _navy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
class _PageTitleBar extends StatelessWidget {
  const _PageTitleBar({required this.title, this.subtitle, this.onBack});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  static const _orgName = 'مؤسسة الشاعري للتجارة العامة';

  @override
  Widget build(BuildContext context) {
    final sub = subtitle?.trim() ?? '';
    final showSub = sub.isNotEmpty && sub != _orgName && sub != title;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(onBack == null ? 16 : 6, 8, 16, 8),
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
