# تطبيق إدارة الشاعري - Flutter

هذا مجلد تطبيق Flutter الجديد، ويعمل مؤقتًا بجانب تطبيق Expo/React Native الحالي إلى أن تكتمل عملية الترحيل والتحقق الوظيفي.

## الحالة الحالية

- Flutter stable 3.50.1 وDart 3.14.0.
- دعم أولي للعربية وRTL وMaterial 3.
- اعتماد `supabase_flutter` مضاف.
- إعداد Supabase لا يحفظ مفاتيح داخل المستودع؛ تُمرر القيم وقت التشغيل عبر `dart-define`.
- مجلدات الميزات الأساسية جاهزة: الهوية، المهام، والتقارير.

## التشغيل

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL="https://your-project.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="your-anon-key"
```

عند عدم تمرير القيم، يعمل التطبيق في وضع الواجهة المحلية دون تهيئة عميل Supabase، وذلك لتسهيل فحص الواجهة دون تسريب أسرار.

## الهيكل

```text
lib/
  core/
    config/       إعدادات البيئة وSupabase
    routing/      التنقل المركزي
    theme/        الثيم والألوان RTL
  features/
    auth/         تسجيل الدخول والصلاحيات
    tasks/        المهام والتنفيذ والمراجعة
    reports/      النماذج وحالات التقارير
  shared/widgets/ المكونات المشتركة
  main.dart       نقطة التشغيل
```

سيتم نقل منطق البيانات تدريجيًا من `apps/mobile/lib` مع الحفاظ على RPC وRLS والجداول الحالية دون استبدالها بتحديثات مباشرة غير آمنة.

## المسارات الحالية

يستخدم التطبيق `go_router` مع غلاف موحد وشريط تنقل RTL:

- `/` — لوحة الرئيسية والملخص.
- `/tasks` — قائمة المهام والفلاتر وحالة الإسناد.
- `/reports` — التقارير مع حالات `draft`, `submitted`, `reviewed`, `approved`, و`returned`.
- `/more` — الحساب والإعدادات والمساعدة.

الصفحات الحالية هي طبقة واجهة أولية منظمة، وتنتظر ربط مستودعات البيانات وRPC الآمنة الموجودة في Supabase.
