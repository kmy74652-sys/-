import 'package:material_ui/material_ui.dart';

abstract final class AppRouter {
  static Route<void> placeholder(String title) {
    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text(title)),
      ),
    );
  }
}
