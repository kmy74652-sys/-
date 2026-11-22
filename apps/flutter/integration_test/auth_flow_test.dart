import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:alshaeri_mobile/main.dart' as application;

/// اختبار قبول حقيقي لتدفق دخول الموظف.
///
/// لا يحتوي هذا الملف على بيانات اعتماد. مرّرها وقت التشغيل عبر:
/// TEST_EMPLOYEE_NO و TEST_EMPLOYEE_CODE، مع SUPABASE_URL وSUPABASE_ANON_KEY.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('employee can log in and reach the authenticated home', (
    tester,
  ) async {
    const employeeNo = String.fromEnvironment('TEST_EMPLOYEE_NO');
    const employeeCode = String.fromEnvironment('TEST_EMPLOYEE_CODE');
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (employeeNo.isEmpty || employeeCode.isEmpty) {
      fail(
        'بيانات اختبار الدخول غير موجودة. مرّر TEST_EMPLOYEE_NO و '
        'TEST_EMPLOYEE_CODE عبر --dart-define ولا تضعها في Git.',
      );
    }
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      fail(
        'إعداد Supabase غير موجود. مرّر SUPABASE_URL و SUPABASE_ANON_KEY '
        'عبر --dart-define.',
      );
    }

    await application.main();
    await tester.pumpAndSettle();

    // ضمان عدم توريث جلسة من تشغيل سابق. يتم ذلك بعد main لأن main.dart
    // هو المسؤول عن تهيئة Supabase مرة واحدة.
    if (Supabase.instance.client.auth.currentSession != null) {
      await Supabase.instance.client.auth.signOut();
      await tester.pumpAndSettle();
    }

    // 1) عند عدم وجود جلسة يجب أن تظهر شاشة الدخول.
    expect(find.text('بوابة العمل والتواصل الإداري'), findsOneWidget);
    expect(find.text('دخول آمن'), findsOneWidget);
    expect(Supabase.instance.client.auth.currentSession, isNull);

    // 2) إدخال رقم الموظف ورمز الدخول عبر واجهة التطبيق.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), employeeNo);
    await tester.enterText(fields.at(1), employeeCode);
    await tester.tap(find.text('دخول آمن'));

    // 3) انتظار انتقال الراوتر إلى الصفحة المحمية مع حد زمني واضح.
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline) &&
        find.text('العمل والمتابعة').evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();

    // 4) التحقق من أن Edge Function أنشأت جلسة Supabase فعلية.
    final session = Supabase.instance.client.auth.currentSession;
    expect(session, isNotNull);
    expect(session!.accessToken, isNotEmpty);

    // 5) التحقق من عقد الملف الشخصي الذي تعتمد عليه الشاشة والراوتر.
    final profileResponse = await Supabase.instance.client.rpc(
      'mobile_my_profile',
    );
    expect(profileResponse, isA<Map>());
    final profile = (profileResponse as Map)['employee'];
    expect(profile, isA<Map>());
    expect((profile as Map)['status'], 'active');

    // 6) التحقق من الوصول إلى الصفحة الرئيسية بعد نجاح Auth وprofile.
    expect(find.text('العمل والمتابعة'), findsOneWidget);
    expect(find.text('إدارة المهام'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 90)));

  tearDown(() async {
    // تنظيف الجلسة حتى لا يؤثر الاختبار على التشغيل التالي.
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) {
      await client.auth.signOut();
    }
  });
}
