import 'package:flutter_test/flutter_test.dart';
import 'package:alshaeri_mobile/core/deep_link_controller.dart';

void main() {
  group('DeepLinkController.safeRoute', () {
    test('يسمح بمسار مهمة آمن من المخطط المخصص', () {
      expect(
        DeepLinkController.safeRoute(Uri.parse('alshaeri://tasks/123')),
        '/tasks/123',
      );
    });

    test('يرفض مخططًا أو مضيفًا غير معروف', () {
      expect(
        DeepLinkController.safeRoute(Uri.parse('javascript:/tasks')),
        isNull,
      );
      expect(
        DeepLinkController.safeRoute(Uri.parse('https://evil.example/tasks')),
        isNull,
      );
    });

    test('يرفض query وfragment حتى لا تمرر بيانات غير موثوقة', () {
      expect(
        DeepLinkController.safeRoute(
          Uri.parse('alshaeri://tasks/123?next=/admin'),
        ),
        isNull,
      );
      expect(
        DeepLinkController.safeRoute(
          Uri.parse('alshaeri://tasks/123#fragment'),
        ),
        isNull,
      );
    });

    test('يرفض المسارات غير الموجودة في القائمة المسموحة', () {
      expect(
        DeepLinkController.safeRoute(Uri.parse('alshaeri://unknown')),
        isNull,
      );
      expect(
        DeepLinkController.safeRoute(Uri.parse('alshaeri://admin/delete')),
        isNull,
      );
    });
  });
}
