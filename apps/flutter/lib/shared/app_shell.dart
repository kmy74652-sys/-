import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notifications_repository.dart';
import '../core/theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshUnreadCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
        setState(() => _unreadCount = items.where((item) => item.isUnread).length);
      }
    } catch (_) {
      final cached = await NotificationsRepository.loadCached(uid);
      if (mounted && cached != null) {
        setState(() => _unreadCount = cached.where((item) => item.isUnread).length);
      }
    }
  }

  static const _tabs = <_ShellTab>[
    _ShellTab('/', 'الرئيسية', Icons.home_outlined),
    _ShellTab('/settings', 'الموظفون', Icons.people_outline),
    _ShellTab('/tasks', 'المهام', Icons.task_alt_outlined),
    _ShellTab('/admin', 'الإعدادات', Icons.settings_outlined),
  ];

  int _selectedIndex(String path) {
    if (path == '/settings' || path.startsWith('/settings/')) return 1;
    if (path == '/tasks' || path.startsWith('/tasks/')) return 2;
    if (path == '/' || path.isEmpty) return 0;
    // Admin, analytics, designers, reports, HR, and agreement screens stay
    // on their current route; this only highlights the nearest shell section.
    if (path == '/hr' || path.startsWith('/hr/')) return 1;
    return 3;
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
      setState(() => _unreadCount = notifications.where((item) => item.isUnread).length);
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
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'تعذر تحميل التنبيهات حالياً.',
                            textAlign: TextAlign.center,
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
                            onTap: item.taskId == null
                                ? null
                                : () {
                                    final taskId = item.taskId!;
                                    Navigator.pop(sheetContext);
                                    if (taskId.isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final selected = _selectedIndex(path);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FD),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                children: [
                  _BrandHeader(
                    title: widget.title,
                    subtitle: widget.subtitle,
                    unreadCount: _unreadCount,
                    onAccount: () => _signOut(context),
                    onNotifications: () => _showNotifications(context),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: _BottomTab(
                        tab: _tabs[i],
                        selected: selected == i,
                        onTap: () => context.go(_tabs[i].route),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab(this.route, this.label, this.icon);
  final String route;
  final String label;
  final IconData icon;
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.title,
    this.subtitle,
    required this.unreadCount,
    required this.onAccount,
    required this.onNotifications,
  });
  final String title;
  final String? subtitle;
  final int unreadCount;
  final VoidCallback onAccount;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 370;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 104),
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10, vertical: 7),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Image.asset(
                  'assets/images/alshaeri-official-logo.png',
                  width: compact ? 63 : 74,
                  height: compact ? 73 : 86,
                  fit: BoxFit.contain,
                  semanticLabel: 'الشعار الرسمي لمؤسسة الشاعري',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'مانجمنت',
                        style: TextStyle(
                          color: const Color(0xFF0B3458),
                          fontSize: compact ? 17 : 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'مؤسسة الشاعري للتجارة العامة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF0B3458),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: 13,
                            child: Divider(
                              color: Color(0xFFDBA62A),
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'معاً .. نحو إدارة أفضل',
                              style: TextStyle(
                                color: Color(0xFF9A6814),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 13,
                            child: Divider(
                              color: Color(0xFFDBA62A),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0B3458),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF637188),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          IconButton(
            tooltip: 'تبديل الحساب: تسجيل الخروج',
            onPressed: onAccount,
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              backgroundColor: const Color(0xFFF4F8FB),
              foregroundColor: const Color(0xFF0B3458),
              side: const BorderSide(color: Color(0xFFD5E0EA)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            icon: const Icon(Icons.account_circle_outlined, size: 23),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'التنبيهات',
            onPressed: onNotifications,
            style: IconButton.styleFrom(
              fixedSize: const Size(42, 42),
              backgroundColor: const Color(0xFF0B3458),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none, size: 24),
                if (unreadCount > 0)
                  Positioned(
                    top: -8,
                    right: -9,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBA62A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF0B3458),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
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
