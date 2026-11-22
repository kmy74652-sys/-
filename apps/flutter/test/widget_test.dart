import 'package:alshaeri_mobile/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Arabic employee login fields', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(isSupabaseConfigured: false),
      ),
    );

    expect(find.text('الشاعري الإداري'), findsOneWidget);
    expect(find.text('رقم الموظف'), findsOneWidget);
    expect(find.text('كلمة المرور'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
  });

  testWidgets('does not attempt login without Supabase configuration', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(isSupabaseConfigured: false),
      ),
    );

    await tester.tap(find.text('دخول'));
    await tester.pump();

    expect(find.text('الاتصال بقاعدة البيانات غير مُعدّ بعد.'), findsOneWidget);
  });
}
