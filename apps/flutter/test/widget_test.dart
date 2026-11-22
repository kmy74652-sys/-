import 'package:flutter_test/flutter_test.dart';

import 'package:alshaairy_mobile/main.dart';

void main() {
  testWidgets('يعرض التطبيق الواجهة العربية والتنقل الأساسي', (tester) async {
    await tester.pumpWidget(const AlshaairyApp());

    expect(find.text('إدارة الشاعري'), findsOneWidget);
    expect(find.text('الرئيسية'), findsAtLeastNWidgets(1));
    expect(find.text('المهام'), findsAtLeastNWidgets(1));
    expect(find.text('التقارير'), findsAtLeastNWidgets(1));
  });
}
