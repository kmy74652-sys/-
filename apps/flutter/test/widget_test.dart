import 'package:flutter_test/flutter_test.dart';

import 'package:alshaairy_mobile/main.dart';

void main() {
  testWidgets('يعرض التطبيق الواجهة العربية والتنقل الأساسي', (tester) async {
    await tester.pumpWidget(const AlshaairyApp());

    expect(find.text('مرحبًا بك في إدارة الشاعري'), findsOneWidget);
    expect(find.text('الرئيسية'), findsAtLeastNWidgets(1));
    expect(find.text('المهام'), findsAtLeastNWidgets(1));
    expect(find.text('التقارير'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('المهام').last);
    await tester.pumpAndSettle();
    expect(find.text('البحث في المهام'), findsOneWidget);

    await tester.tap(find.text('التقارير').last);
    await tester.pumpAndSettle();
    expect(
      find.text('إدارة مسودات التقارير ومتابعة دورة المراجعة والاعتماد.'),
      findsOneWidget,
    );
  });
}
