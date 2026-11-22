# تطبيق الشاعري الإداري — Flutter

هذا تطبيق Flutter مستقل داخل المستودع، أُضيف دون استبدال تطبيق الهاتف الحالي أو تعديل Supabase.

## المتطلبات
- Flutter stable يدعم Dart 3.4 أو أحدث.
- Android SDK.

## التشغيل
من هذا المجلد:
```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_ANON_KEY
```

لا تضع مفاتيح Supabase داخل ملفات المصدر أو Git. استخدم مفتاح publishable فقط في تطبيق الهاتف، ولا تستخدم service-role key مطلقاً.

إذا لم تُمرر متغيرات الاتصال، يعرض التطبيق شاشة توضح أن إعداد الاتصال مطلوب ولا يحاول تسجيل الدخول.

## الحالة
- أساس Flutter وMaterial 3.
- واجهة عربية RTL وتسجيل دخول برقم الموظف وكلمة المرور.
- تسجيل الدخول برقم الموظف وكلمة المرور عبر Edge Function الحالية `employee-code-auth` ثم إنشاء جلسة Supabase.
- تحميل ملف الموظف والدور عبر RPC الحالية `mobile_my_profile` بعد تسجيل الدخول.
- فحوص Flutter الآلية موجودة في GitHub Actions؛ لم يُنفذ بناء APK أو اختبار جهاز فعلي بعد.
- لم يتم تغيير مخطط Supabase أو بيانات الإنتاج.
