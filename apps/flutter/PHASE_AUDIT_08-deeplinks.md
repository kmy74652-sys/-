# تدقيق المرحلة 08: الروابط العميقة وإعادة المصادقة

**النطاق:** Flutter مقابل Expo وعقود Supabase الموجودة في `supabase/migrations`.

**الملفات المرجعية الأساسية:**
- `apps/mobile/app/_layout.tsx`
- `apps/flutter/lib/core/router.dart`
- `apps/flutter/lib/features/auth/login_screen.dart`

**تاريخ التدقيق:** 2026-11-22

## الخلاصة التنفيذية

الحالة الحالية **أولية وغير جاهزة لاعتماد مرحلة الروابط العميقة وإعادة المصادقة**. تدفق تسجيل الدخول برمز الموظف منسوخ وظيفيًا إلى Flutter من حيث استدعاء Edge Function والتحقق من الأخطاء، لكن دورة الجلسة ليست مربوطة بالموجّه، ولا توجد معالجة فعلية لـ deep links في كود Dart، ولا يوجد مسار لإعادة المصادقة بعد انتهاء/رفض refresh token أو عند فتح التطبيق من رابط وارد. يوجد intent filter أندرويد بالمخطط `alshaeri`، كما أن `pubspec.lock` يحتوي أثرًا لحزمة `app_links`، لكن الحزمة ليست معلنة في `pubspec.yaml` ولا يوجد مستهلك Dart لها. لذلك فوجود إعداد native وحده لا يحقق استقبال الرابط أو تحويله إلى مسار آمن داخل التطبيق.

لم أعدل كود التطبيق أو Backend، ولم أشغّل migrations، ولم أنشئ commit. ملف هذا التقرير هو التغيير الوحيد المقصود في نطاق المهمة.

## ما هو منفذ

### 1. عقد الدخول برمز الموظف منقول بصورة أساسية

`login_screen.dart` يستدعي:

```text
employee-code-auth
body: { action: login, employeeNo, code }
```

وهذا يطابق عقد `supabase/functions/employee-code-auth/index.ts` الذي يتحقق من الموظف النشط، رمز الدخول، تحديد المعدل، ثم يستعمل حساب Auth الجسري ويعيد `access_token` و`refresh_token`. رسائل Flutter تغطي الحالات 401 و429 و404/503، وتمنع إرسال رمز فارغ أو يحوي مسافات وتفرض 8–64 محرفًا؛ وهذا متوافق مع `isAccessCode` في الـEdge Function.

### 2. تخزين جلسة Supabase موجود جزئيًا

بعد نجاح Edge Function يستدعي Flutter `auth.setSession` باستخدام `refresh_token`. هذا يتيح لـSupabase إنشاء/تجديد جلسة من refresh token، لكن Flutter يهمل `access_token` الذي أعاده العقد. Expo، في `apps/mobile/app/index.tsx`، يمرر الرمزين معًا إلى `supabase.auth.setSession({ access_token, refresh_token })` ثم يعيد تحميل ملف الموظف. لا يوجد في Flutter بعد الدخول تحميل صريح لـ`mobile_my_profile` أو فحص أن العضوية لا تزال نشطة قبل الانتقال إلى `/`.

### 3. مراقب جلسة قابل لإعادة الاستخدام موجود لكنه غير موصول

`apps/flutter/lib/core/session_controller.dart` يعرّف `sessionProvider` على `auth.onAuthStateChange`، لكن البحث في المشروع لا يظهر استعماله من `MaterialApp.router` أو `GoRouter`. لذلك فهو ليس آلية حراسة فعلية للمسارات حاليًا.

### 4. حراسة أولية للمسارات

`router.dart` يفحص `currentSession` وقت تنفيذ redirect:
- المستخدم غير الموقع يُعاد إلى `/login` عند أي مسار غير `/`.
- المستخدم الموقع يُعاد من `/login` إلى `/`.

هذه حراسة متزامنة وبسيطة، وليست استماعًا مستمرًا لانتهاء الجلسة أو تبدلها. كما أن السماح بـ`/` للمستخدم غير الموقع يجعل السلوك مختلفًا عن حراسة بقية المسارات ويحتاج قرارًا صريحًا: هل الصفحة الرئيسية شاشة دخول أم مسار عام؟

### 5. إعداد Android جزئي للرابط المخصص

`AndroidManifest.xml` يحتوي `VIEW`/`BROWSABLE` intent filter للمخطط `alshaeri` مع `singleTop`. هذا يثبت نية استقبال روابط مثل `alshaeri://...` على Android فقط، لكنه لا يثبت أن التطبيق يقرأ intent الأول أو intents اللاحقة، ولا يثبت وجود مسارات مكافئة في GoRouter. لا توجد ملفات iOS في مشروع Flutter الحالي، ولا إعداد Universal Links/App Links موثق له.

## مقارنة Expo وFlutter

في Expo، `_layout.tsx` يثبت مستمع `supabase.auth.onAuthStateChange`، ويحصل على الجلسة الحالية عند بدء التشغيل، ويتعامل صراحة مع `SIGNED_OUT` بتنظيف حالة تسجيل push. و`index.tsx` يستدعي `load()` عند الإقلاع، ويستمع إلى `SIGNED_OUT` لتنظيف الملف، ثم بعد `setSession` يعيد تحميل الملف ويعرض إعادة الاتصال عند فشل الاستعادة.

في Flutter:
- `main.dart` يهيئ Supabase فقط ثم يبني `MaterialApp.router`.
- `session_controller.dart` يعرّف stream لكنه غير موصول بالموجّه أو الشاشة.
- `router.dart` يقرأ `currentSession` قراءة لحظية فقط.
- `login_screen.dart` ينتقل مباشرة إلى `/` بعد `setSession` دون تحميل `mobile_my_profile` أو انتظار/عرض حالة استعادة الجلسة.
- لا يوجد `app_links`, `uni_links`, `uriLinkStream`, أو `GoRouter` refresh/listener في كود Dart.
- لا يوجد parsing أو allow-list لرابط وارد، ولا حفظ للرابط المقصود قبل إجبار المستخدم على تسجيل الدخول.

وبالتالي فالفجوة ليست في تسجيل الدخول الأولي فقط؛ بل في دورة الحياة الكاملة: رابط وارد، جلسة محفوظة، انتهاء الجلسة، إعادة توثيق، ثم العودة إلى الوجهة الآمنة.

## فحص عقد Backend وmigrations

العقود الموجودة لا تقدم عقدًا مستقلًا للرابط العميق أو لإعادة المصادقة، وهذا متوقع لأن deep linking وظيفة عميل/نظام تشغيل. العقود التي يعتمد عليها الدخول هي:

1. `migrations/020_membership_employee_code_auth.sql`:
   - يضيف `employee_no` الفريد على `organization_memberships`.
   - يضيف `mobile_my_profile()` كدالة `security definer` للمستخدم المصادق عليه.
   - يمنح تنفيذها إلى `authenticated` فقط.
2. `migrations/021_employee_access_credentials.sql`:
   - يجعل بيانات اعتماد رمز الموظف متاحة لـ`service_role` فقط.
   - لا يجوز للعميل القراءة أو الكتابة المباشرة إلى جدول credentials.
3. `migrations/019_employee_access_codes.sql`:
   - يعرّف سجل محاولات الدخول وتحديد المعدل، مع وصول `service_role` فقط.
4. `employee-code-auth/index.ts`:
   - يعيد الرمزين عند `action=login`.
   - يتطلب إعدادات Edge Function السرية (`SUPABASE_SECRET_KEY`/البدائل) على الخادم.
   - يستخدم refresh token فعليًا عبر Supabase Auth؛ لا يوجد RPC أو migration مطلوب لإضافة deep link.

### حواجز عقد Backend

- لا يوجد عقد Backend مخصص لـ`reauthenticate` أو `refresh` مستقل للعميل. إعادة المصادقة يجب أن تعتمد على `supabase_flutter` وrefresh token، أو تحتاج قرارًا تعاقديًا جديدًا من مالك Backend؛ لا ينبغي اختراع endpoint داخل Flutter.
- لا يوجد عقد يضمن إرجاع ملف الموظف مع جلسة login؛ لذلك يجب على Flutter استدعاء `mobile_my_profile()` بعد تثبيت الجلسة كما يفعل Expo عبر طبقة بياناته.
- نتيجة `mobile_my_profile()` قد تكون فارغة عند حذف/تعطيل العضوية، ويجب أن يعاملها Flutter كحالة خروج/حساب غير صالح لا كجلسة صالحة دائمًا.
- تغيير/سحب رمز الموظف يحدّث كلمة المرور الجسرية في Auth. الجلسات القديمة قد تستمر أو تفشل بحسب سياسة Supabase؛ يلزم اختبارًا بيئيًا يحدد ما إذا كان `TOKEN_REFRESHED` أو `SIGNED_OUT` يصل للعميل، دون افتراض سلوك غير موثق.
- لا يجوز إدخال service role أو الوصول المباشر إلى جداول `employee_access_credentials` و`employee_access_code_login_attempts` في Flutter.

هذه حواجز عقد/اختبار وليست مبررًا لتعديل migrations في هذه المرحلة. لا توجد migration حالية تمنع deep link بحد ذاتها، لكن لا توجد أيضًا migration توفر fallback أو reauth endpoint.

## الفجوات القابلة للتنفيذ داخل Flutter

### أولوية P0 — استقبال الرابط وربطه بالموجّه

1. إعلان اعتماد رابط عميق فعلي في `apps/flutter/pubspec.yaml` (مثل `app_links` المتوافق مع نسخة Flutter)، بدل الاعتماد على أثر lockfile فقط.
2. إنشاء طبقة deep-link واحدة تقرأ الرابط الأول عند تشغيل التطبيق وتستمع إلى الروابط اللاحقة، مع إلغاء الاشتراك عند dispose.
3. تعريف allow-list لمسارات التطبيق (`/tasks`, `/tasks/:taskId`, `/reports`, وغيرها) ورفض scheme/host/path غير المعروف؛ لا ينبغي تمرير URI كامل إلى `context.go` بلا تحقق.
4. حفظ المسار المقصود مؤقتًا عندما يكون المستخدم غير مصادق، ثم إكماله بعد نجاح الجلسة و`mobile_my_profile()`، مع منع open redirect وعدم حفظ access/refresh token في URI أو logs.
5. إضافة اختبار cold start وwarm start وفتح رابط عند وجود جلسة وعند غيابها، واختبار رابط غير صالح.

### أولوية P0 — ربط Auth state بالموجّه

1. تمرير `refreshListenable` أو notifier إلى `GoRouter` يعتمد على `auth.onAuthStateChange` أو إعادة بناء router بطريقة لا تفقد الحالة.
2. معالجة `SIGNED_OUT`, `TOKEN_REFRESHED`, `USER_UPDATED` وحالات خطأ استعادة الجلسة، لا الاكتفاء بقراءة `currentSession` في redirect.
3. إزالة/توضيح الاستثناء الحالي الذي يسمح للمستخدم غير الموقع بالبقاء على `/`، أو جعل `/` شاشة عامة مصممة صراحة. يجب ألا تكون حماية المسارات موزعة ضمنيًا بين router والشاشات.
4. إضافة حالة تحميل/استعادة قبل redirect حتى لا يظهر login لحظيًا ثم يقفز إلى الصفحة الرئيسية عند استعادة الجلسة.

### أولوية P0 — إكمال دورة إعادة المصادقة

1. بعد login، تمرير `access_token` و`refresh_token` معًا إلى `setSession`، ثم استدعاء profile والتحقق من العضوية قبل `context.go`.
2. إضافة مسار واضح عند فشل refresh أو وصول `AuthException` بسبب جلسة منتهية: تنظيف الجلسة، حفظ الوجهة الآمنة، وإظهار شاشة login برسالة عربية قابلة للتنفيذ.
3. توفير retry يدوي لاستعادة الجلسة شبيه بـExpo، مع منع تكرار الطلبات عند rebuild أو auth callbacks.
4. بعد sign-out، تنظيف الرابط المقصود وأي بيانات مؤقتة مرتبطة بالمستخدم، وعدم إعادة فتح مسار محمي بحساب مختلف دون تحقق.
5. التعامل مع race بين deep link وauth initialization: لا تنفذ redirect قبل معرفة حالة الجلسة النهائية.

### أولوية P1 — المنصات والاختبار

1. إضافة إعداد iOS (`CFBundleURLTypes` على الأقل للمخطط المخصص، أو Universal Links إن كان المطلوب رابط HTTPS)؛ مشروع Flutter الحالي لا يحتوي scaffold iOS.
2. توحيد scheme/host/path مع التطبيق المنشور. README يذكر `alshaeri` لكنه يحذر من عدم إثبات توافق package ID والتوقيع مع Expo؛ لذلك لا ينبغي اعتبار التثبيت فوق نسخة Expo مضمونًا.
3. إضافة اختبارات وحدات للـURI parser واختبارات Widget لحالات login/expired session/pending route.
4. تنفيذ اختبار Android حقيقي: cold start من `adb`, warm start، رابط من متصفح، رابط task غير موجود، رابط بعد sign-out، وانتهاء refresh token.
5. اختبار عدم تسريب URI أو tokens إلى crash logs وanalytics، والتحقق من سلوك Android `singleTop` عند وصول intent ثانٍ.

## الملفات المقترحة للتغيير لاحقًا

هذه قائمة تخطيطية فقط؛ لم أعدلها في هذا التدقيق:

- `apps/flutter/pubspec.yaml` — إعلان اعتماد deep-link المناسب.
- `apps/flutter/lib/main.dart` — تهيئة lifecycle/deep-link وربط auth bootstrap إذا كان التصميم المختار يضعه هنا.
- `apps/flutter/lib/core/router.dart` — auth refresh، pending destination، allow-list، ومعالجة redirect الآمنة.
- `apps/flutter/lib/core/session_controller.dart` — تحويله إلى مصدر حالة فعلي أو استبداله بمراقب lifecycle موحد.
- `apps/flutter/lib/features/auth/login_screen.dart` — setSession بالرمزين، profile verification، وإكمال pending route ورسائل reauth.
- ملف جديد مقترح مثل `apps/flutter/lib/core/deep_link_controller.dart` — parsing/stream/subscription وسياسة الروابط.
- `apps/flutter/android/app/src/main/AndroidManifest.xml` — مراجعة scheme/host فقط بعد الاتفاق على العقد والتطبيق المنشور.
- `apps/flutter/ios/Runner/Info.plist` وملفات iOS المقابلة — عند إنشاء دعم iOS فعلي.
- `apps/flutter/test/core/...` — اختبارات parser والجلسة والموجّه.

## خطة تحقق قصيرة قابلة للتنفيذ

1. تشغيل `flutter analyze` و`flutter test` بعد إدخال طبقة الرابط، ثم إصلاح أخطاء lifecycle والاشتراكات.
2. على Supabase غير إنتاجي، login صحيح، رمز خاطئ، rate limit، سحب الرمز، تعطيل العضوية، وانتهاء refresh token.
3. قياس الأحداث الفعلية (`SIGNED_IN`, `TOKEN_REFRESHED`, `SIGNED_OUT`) في Flutter، والتأكد من عدم تسجيل tokens.
4. اختبار كل نوع رابط مدعوم مع جلسة باردة/ساخنة، ومع مستخدم غير مصادق، ثم التحقق من منع المسارات غير المسموحة.
5. اختبار تبديل الحساب بعد sign-out، والتأكد من أن pending route لا يعبر بين المستخدمين.
6. بناء Android على جهاز فعلي؛ لا يكفي وجود intent filter أو `GeneratedPluginRegistrant.java` لإثبات الوظيفة.

## الحكم النهائي

- **تسجيل الدخول الأولي:** منفذ جزئيًا ومطابق للعقد في نقطة الاستدعاء، مع ملاحظة أن Flutter لا يمرر access token إلى `setSession` ولا يتحقق من profile بعده.
- **استعادة/إعادة المصادقة:** غير مكتملة؛ يوجد stream غير موصول وحراسة لحظية فقط.
- **Deep links:** غير منفذة وظيفيًا؛ يوجد إعداد Android native جزئي بلا قارئ URI أو routes آمنة أو دعم iOS.
- **Backend:** لا يوجد blocker migration مباشر، لكن لا يوجد عقد reauth مستقل ولا عقد deep-link؛ يجب استخدام Supabase Auth والعقود القائمة وعدم تعديل Backend دون قرار صريح.
- **الأهلية للمرحلة:** غير جاهز للاعتماد حتى تنفيذ P0 وإثباته باختبارات cold/warm/device وبيئة Supabase غير إنتاجية.
