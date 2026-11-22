import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مسؤول عن تحويل الروابط الخارجية إلى مسارات داخلية مسموحة فقط.
class DeepLinkController {
  DeepLinkController({AppLinks? links}) : _links = links ?? AppLinks();

  static const _pendingKey = 'pending_safe_route';
  final AppLinks _links;
  StreamSubscription<Uri>? _subscription;

  static String? safeRoute(Uri uri) {
    if (uri.scheme.isEmpty && uri.path.startsWith('/')) {
      if (uri.queryParameters.isNotEmpty || uri.fragment.isNotEmpty)
        return null;
      return _allowedPath(uri.path) ? uri.path : null;
    }
    if (uri.scheme != 'alshaeri' && uri.scheme != 'https') return null;
    if (uri.scheme == 'https' && uri.host != 'alshaeri.app') return null;
    final path = uri.scheme == 'alshaeri'
        ? '/${uri.host}${uri.path == '/' ? '' : uri.path}'
        : (uri.path.isEmpty ? '/' : uri.path);
    if (!_allowedPath(path)) return null;
    if (uri.queryParameters.isNotEmpty || uri.fragment.isNotEmpty) {
      // لا نمرر query/fragment قد يحتويان رموزًا أو وجهات خارجية.
      return null;
    }
    return path;
  }

  static bool _allowedPath(String path) => RegExp(
    r'^/(tasks|tasks/[^/]+|reports|reports/daily|reports/independent|agreement|hr|settings|admin|admin/tasks|admin/report-designer|admin/task-designer|admin/performance)$',
  ).hasMatch(path);

  Future<String?> initialRoute() async {
    final uri = await _links.getInitialLink();
    return uri == null ? null : safeRoute(uri);
  }

  Future<void> savePending(String? route) async {
    final preferences = await SharedPreferences.getInstance();
    if (route == null) {
      await preferences.remove(_pendingKey);
    } else {
      await preferences.setString(_pendingKey, route);
    }
  }

  Future<String?> consumePending() async {
    final preferences = await SharedPreferences.getInstance();
    final route = preferences.getString(_pendingKey);
    await preferences.remove(_pendingKey);
    return route == null ? null : safeRoute(Uri.parse(route));
  }

  void listen(void Function(String route) onRoute) {
    _subscription ??= _links.uriLinkStream.listen((uri) {
      final route = safeRoute(uri);
      if (route != null) onRoute(route);
    });
  }

  Future<void> dispose() async => _subscription?.cancel();
}
