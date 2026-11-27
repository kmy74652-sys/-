import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notifications_repository.dart';
import '../core/notifications_runtime.dart';
import '../core/theme.dart';
import 'app_customizer.dart';
import 'form_widgets.dart';
import 'organization_branding.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onBeforeNavigate,
    this.immersive = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Future<bool> Function()? onBeforeNavigate;
  final bool immersive;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _unreadCount = 0;
  Set<String> _permissions = <String>{};

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
          });
        }
        return;
      }
    } catch (_) {
      // The destination screens still enforce their own permissions.
    }
  }

  bool _can(String permission) => _permissions.contains(permission);

  bool get _managesTasks => _can('tasks.manage');

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
        if (_permissions.contains('employees.manage'))
          _ShellTab('/settings', 'الإعدادات', Icons.settings_outlined),
      ];

  int _selectedIndex(String path) {
    if (path == '/tasks' || path.startsWith('/tasks/')) return 1;
    if (path == '/settings' || path.startsWith('/settings/')) return _tabs().length - 1;
    if (path == '/' || path.isEmpty) return 0;
    // الإدارة والتقارير والتحليلات مسارات داخلية وتُحسب بصريًا على الرئيسية.
    return 0;
  }

  String? _backRoute(String path) {
    switch (path) {
      case '/':
        return null;
      case '/tasks':
      case '/reports':
      case '/reports/independent':
      case '/hr':
      case '/settings':
        return '/';
      case '/admin/tasks':
      case '/admin/unified-task-management':
      case '/admin/performance':
      case '/admin/report-designer':
        return '/';
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
        textDirection: Directionality.of(sheetContext),
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
    return AnimatedBuilder(
      animation: AppCustomizer.instance,
      builder: (context, _) {
        return PopScope<void>(
        canPop: path == '/',
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final route = _backRoute(path);
          if (route != null) _navigate(route);
        },
        child: Directionality(
        textDirection: Directionality.of(context),
        child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FD),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                children: [
                  if (!widget.immersive)
                    _BrandHeader(
                      unreadCount: _unreadCount,
                      onAccount: () => _confirmSignOut(context),
                      onNotifications: () => _showNotifications(context),
                    ),
                  if (!widget.immersive)
                    _PageTitleBar(
                      title: widget.title,
                      showDateTime: path == '/',
                      onBack: _backRoute(path) == null
                          ? null
                          : () => _navigate(_backRoute(path)!),
                    ),
                  Expanded(
                    child: Padding(
                      padding: widget.immersive
                          ? EdgeInsets.zero
                          : const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: widget.immersive ? null : Container(
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
  });

  final int unreadCount;
  final VoidCallback onAccount;
  final VoidCallback onNotifications;

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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(AppCustomizer.instance.label('appName'), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.fade,
                      style: TextStyle(color: _navy, fontSize: compact ? 17 : 21, height: 1.15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      AppCustomizer.instance.label('organizationName'),
                      textAlign: TextAlign.center,
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
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
              SizedBox(width: controlGap),
              IconButton(
                tooltip: 'تبديل الحساب: تسجيل الخروج',
                onPressed: widget.onAccount,
                style: IconButton.styleFrom(fixedSize: Size.square(controlSize), backgroundColor: Colors.transparent, foregroundColor: _navy, shadowColor: Colors.transparent, shape: const CircleBorder()),
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

/// Slim page-title strip under the brand header: back button on inner pages,
/// page title, and the home date/time display.
class _PageTitleBar extends StatefulWidget {
  const _PageTitleBar({
    required this.title,
    this.showDateTime = false,
    this.onBack,
  });

  final String title;
  final bool showDateTime;
  final VoidCallback? onBack;

  @override
  State<_PageTitleBar> createState() => _PageTitleBarState();
}

class _PageTitleBarState extends State<_PageTitleBar> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.showDateTime) {
      _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String get _dateTimeLabel =>
      '${_now.year}/${_now.month.toString().padLeft(2, '0')}/${_now.day.toString().padLeft(2, '0')} - ${formatArabicTime(_now)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        widget.onBack == null ? 16 : 6,
        8,
        16,
        8,
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
          if (widget.onBack != null)
            IconButton(
              tooltip: 'رجوع',
              onPressed: widget.onBack,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.arrow_back,
                size: 22,
                color: Color(0xFF0B3458),
              ),
            ),
          Container(
            width: 4,
            height: widget.showDateTime ? 34 : 22,
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
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B3458),
                    fontSize: 17,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (widget.showDateTime)
                  Text(
                    _dateTimeLabel,
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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.navy.withAlpha(22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.view_agenda_outlined,
                  size: 19,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.right,
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
          const Divider(height: 22),
          child,
        ],
      ),
    ),
  );
}
