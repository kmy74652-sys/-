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
- واجهة مهام الموظف تقرأ `task_report_form_snapshots` وتعرض حقول التقرير المحفوظة مع المهمة، بما فيها الجداول متعددة الصفوف.
- مصمم المهام يحفظ القالب ثم يرسل طلب نشر عبر `submit_task_publication_request`؛ لا تُرسل المهمة للموظفين حتى يعتمدها حساب صاحب المؤسسة عبر `review_and_publish_task_request`.
- بعد الاعتماد، ينشر الخادم المهمة تلقائياً للموظفين النشطين المطابقين للدور والفرع، مع الاحتفاظ بنسخة التصميم على المهمة.
- فحوص Flutter الآلية موجودة في GitHub Actions. بناء APK مؤجل حتى اكتمال اختبارات قبول دورة المهمة كاملة، وفق تدقيق المشروع.
- لم يتم تغيير مخطط Supabase أو بيانات الإنتاج.
