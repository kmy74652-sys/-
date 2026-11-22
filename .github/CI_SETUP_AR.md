# إعداد CI/CD لتطبيق Flutter

تمت إضافة Workflow في:

```text
.github/workflows/flutter-ci.yml
```

يعمل تلقائيًا عند push أو pull request إلى `main` أو `master` أو `develop`، ويمكن تشغيله يدويًا من تبويب **Actions** عبر `workflow_dispatch`.

## ما ينفذه Workflow

ينفذ على Ubuntu x64:

1. تثبيت Java 17.
2. تثبيت Flutter stable بالإصدار المحدد في الملف.
3. تجهيز Android SDK.
4. تنفيذ `flutter pub get`.
5. فحص تنسيق Dart.
6. تشغيل `flutter analyze`.
7. تشغيل `flutter test`.
8. بناء APK release.
9. بناء Android App Bundle release.
10. رفع APK وAAB كـArtifacts لمدة 14 يومًا.

## أسرار Supabase

من إعدادات مستودع GitHub، أضف الأسرار التالية إن كان البناء يحتاج اتصال Supabase:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
```

المسموح هو URL والمفتاح العام anon/publishable فقط. يمنع إضافة `service_role` إلى GitHub Secrets المستخدمة في تطبيق Flutter أو إلى build arguments.

## ملاحظة مهمة عن التوقيع

الـWorkflow الحالي يبني artifact قابلًا للفحص، لكنه لا يستخدم Signing Keystore خاصًا بالإنتاج. قبل إصدار تحديث لتطبيق Expo المنشور، يجب إضافة إعداد توقيع محمي في GitHub Secrets والتأكد من تطابق `applicationId` وKeystore وSHA-1 وSHA-256. لا ينبغي نشر APK الناتج كترقية للإنتاج قبل هذا التحقق.

## حدود التحقق

نجاح Workflow يثبت التحليل والاختبارات والبناء على Ubuntu x64، لكنه لا يثبت وحده وصول Push Notifications أو سلوك الكاميرا/المرفقات أو الروابط العميقة على جهاز Android حقيقي. يلزم تثبيت APK على جهاز فعلي لإكمال بوابة QA.
