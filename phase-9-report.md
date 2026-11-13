# تقرير المرحلة التاسعة — تطبيق Android وتجهيز APK

تمت إضافة تطبيق Expo/React Native مستقل داخل `apps/mobile` مرتبط بمصادقة Supabase وواجهة API الحالية. التطبيق يدعم شاشة دخول عربية RTL، عرض ملف الموظف والأدوار والفروع، وإظهار الوحدات حسب الصلاحيات.

أضيفت إعدادات Android التالية:

- اسم التطبيق: برنامج الشاعري
- المعرف: `com.alshaeri.mobile`
- scheme: `alshaeri`
- أيقونات launcher وsplash وadaptive icon
- إعداد `eas.json` بملف preview من نوع APK
- ملف `.env.example` للمتغيرات العامة فقط

## التحقق

- `pnpm typecheck` ناجح لكل API والويب وMobile.
- `expo export --platform android` ناجح.
- Metro أنتج حزمة Android بحجم 3.03 MB.
- تم إصلاح اعتماديات `@babel/runtime` و`query-string` اللازمة للتصدير.
- لم تتم طباعة أو تضمين مفاتيح Supabase السرية.

## حد بناء APK

البيئة الحالية لا تحتوي Android SDK أو Gradle أو EAS CLI، وعقد Mobile يمنع تنفيذ release build داخل Sandbox أو داخل خدمة Metro. لذلك تم تجهيز المصدر والإعدادات والـcheckpoint ليتم بناء APK الفعلي من Dashboard/EAS بعد قبول النسخة. نتيجة التصدير الناجحة تثبت أن حزمة JavaScript قابلة للبناء، لكنها ليست ملف APK نهائيًا.
