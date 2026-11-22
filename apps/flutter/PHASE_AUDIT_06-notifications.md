# تدقيق المرحلة 06: الإشعارات — Flutter مقابل Expo وSupabase

**نطاق التدقيق:** الإشعارات فقط، مع التركيز على `apps/mobile/lib/pushNotifications.ts` وملفات Expo المرتبطة، و`apps/flutter/lib/shared/app_shell.dart` و`apps/flutter/lib/core`، وعقود `supabase/migrations` ذات الصلة.

**تاريخ التدقيق:** 2026-11-22

**قيود التنفيذ:** لم أعدّل كود التطبيق أو Backend، ولم أشغّل migrations، ولم أنشئ commit. هذا التقرير هو الملف الوحيد الذي أُنشئ لهذه المرحلة.

## الخلاصة التنفيذية

حالة مرحلة الإشعارات في Flutter هي **منفذة جزئيًا — قائمة إشعارات داخل التطبيق فقط**. يوجد زر في رأس التطبيق يفتح نافذة تعرض آخر 50 سجلًا من `public.notifications`، مع عنوان ونص وشدة وحالة القراءة، ويفتح المهمة المرتبطة عند توفر `task_id`. هذا يطابق جزءًا من شاشة Expo، لكنه لا يحقق سلوك الإشعارات الكامل الموجود في Expo.

لا يوجد في Flutter تسجيل لجهاز أو طلب صلاحية أو إنشاء push token أو استدعاء `register_push_device`، ولا قناة Android، ولا معالج foreground/local notification، ولا listener لاستجابة ضغط الإشعار، ولا اشتراك Realtime للإشعارات أو المهام. كذلك لا توجد عملية تعليم الإشعار كمقروء. لذلك لا ينبغي اعتبار المرحلة مكتملة أو استبدال Expo بها.

## ما هو منفذ في Flutter

1. `apps/flutter/lib/shared/app_shell.dart:41-151` يحتوي `_showNotifications`؛ يستعلم من جدول `notifications` عن `id,task_id,title,body,severity,read_at,created_at`، يرتب تنازليًا حسب `created_at`، ويحد القراءة بـ50 سجلًا.
2. النافذة تعرض حالات التحميل الفاشل والقائمة الفارغة، وتعرض أيقونة مختلفة حسب `read_at`، والعنوان والنص والشدة، وتفتح `/tasks/<taskId>` عند الضغط على إشعار مرتبط بمهمة (`app_shell.dart:104-141`).
3. الزر ظاهر في رأس التطبيق مع RTL ووسم عربي (`app_shell.dart:321-330`)، ويعمل من خلال الغلاف المشترك (`app_shell.dart:168-173`).
4. `apps/flutter/lib/core/router.dart:31-35` يوفّر المسارين `/tasks` و`/tasks/:taskId`، لذا فتح المهمة من القائمة الداخلية قابل للتنفيذ للمسارات التي تحتوي `task_id`.
5. يستخدم Flutter عميل Supabase المصادق الحالي مباشرة. لا توجد في `apps/flutter/lib/core` كتابة إلى جدول الإشعارات أو تجاوز لـRLS، وهذا متوافق مع مبدأ أن صلاحيات Backend هي المرجع.
6. توجد معالجة فشل عامة في القائمة: عند فشل الاستعلام تُعرض رسالة «تعذر تحميل التنبيهات حالياً». لكن لا توجد آلية cache أو retry أو refresh خاص بالإشعارات داخل هذه النافذة.

## مقارنة السلوك مع Expo

### تسجيل الجهاز وPush token

في Expo، `apps/mobile/lib/pushNotifications.ts:17-49` يتحقق من الجهاز الحقيقي، يضبط قناة Android، يطلب صلاحية الإشعارات، يستدعي `getExpoPushTokenAsync`، ثم يستدعي RPC `register_push_device` مع token والمنصة واسم الجهاز. Flutter لا يحتوي على أي مقابل لذلك، ولا توجد حزم push في `apps/flutter/pubspec.yaml`.

### الإشعار أثناء تشغيل التطبيق

Expo يضبط `Notifications.setNotificationHandler` لعرض التنبيه وتشغيل الصوت وتحديث الشارة (`pushNotifications.ts:7-14`). كما يملك `notifyInAppTaskReceived` (`:62-75`) الذي ينشئ إشعارًا محليًا بصوت افتراضي عند وصول مهمة. Flutter لا ينشئ إشعارًا محليًا ولا يشغل صوتًا أو شارة.

### استقبال المهمة والتحديث الحي

في `apps/mobile/app/tasks.tsx:237-265` يشترك Expo في `postgres_changes` على جدول `tasks` للمستخدم الحالي، ويعرض banner لمهمة جديدة ويستدعي التنبيه المحلي، ثم يعيد تحميل البيانات. Flutter لا يملك اشتراك Realtime مشابهًا في `app_shell.dart` أو `apps/flutter/lib/core`، ولا polling خاصًا بالإشعارات، لذلك القائمة لا تتحدث تلقائيًا بعد فتحها إلا عند إعادة بناء/فتح الشاشة أو إعادة تشغيل المسار.

### الضغط على push/deep link

في `apps/mobile/app/_layout.tsx:33-36` يوجد `addNotificationResponseReceivedListener` ينقل المستخدم إلى مساحة المهام. Flutter لا يملك listener لإشعارات النظام أو deep link للإشعار. فتح المهمة من القائمة الداخلية فقط هو السلوك المتاح حاليًا.

### قائمة الإشعارات

Expo يقرأ آخر 50 إشعارًا عبر `listMyNotifications` (`apps/mobile/lib/mobileData.ts:171-191`) ويعرض أول خمسة في `tasks.tsx:610-620`، مع cache جلسة وحالة «مقروء/جديد». Flutter يعرض حتى 50 داخل bottom sheet، وهو أوسع بصريًا، لكنه لا يملك cache أو تحديثًا حيًا. لا يملك أي من المصدرين الحاليين عملية فعلية لتعليم الإشعار كمقروء؛ Flutter يعرض الحالة فقط ولا يغيّرها.

## عقود Backend الموجودة

### عقد الإشعار الداخلي

`supabase/migrations/053_direct_task_delivery_notifications.sql:3-24` ينشئ `public.notifications` بالحقول `id`, `organization_id`, `recipient_user_id`, `task_id`, `title`, `body`, `severity`, `read_at`, `created_at`. توجد سياسة SELECT للمستخدم الذي يساوي `auth.uid()` ومنح SELECT للمصادقين. هذا يدعم الاستعلام الموجود في Flutter، بشرط تطبيق migration على البيئة المستهدفة.

الـmigration نفسه (`:26-47`) ينشئ إشعارًا عند إنشاء مهمة مسندة، كما تضيف ترحيلات لاحقة إشعارات لدورات التقارير والأدوار. لذلك مصدر الإشعارات الداخلية موجود على مستوى قاعدة البيانات.

### عقد push الخاص بـExpo

`supabase/migrations/069_push_notifications.sql:7-21` ينشئ `notification_devices` بحقل `expo_push_token` ومنصة محصورة في `android|ios|web`. الـRPC `register_push_device(text,text,text)` (`:29-59`) يفرض token بصيغة عامة لكنه اسميًا Expo، ويربطه بأول عضوية نشطة للمستخدم، ويعيد تفعيل الجهاز نفسه عند إعادة التسجيل. `disable_push_device()` (`:61-70`) يعطّل كل أجهزة المستخدم.

الـtrigger `notifications_dispatch_push` (`:72-109`) يرسل payload إلى Expo Push Service عبر `net.http_post`، ويضع `notificationId`, `taskId`, و`route` داخل `data`. هذا عقد صالح لـExpo، وليس عقدًا عامًا لـFlutter/FCM/APNs.

### التذكيرات المتأخرة

`supabase/migrations/070_overdue_task_reminders.sql:17-76` ينشئ تذكيرًا كل ساعة للمهمة المتأخرة، مع منع التكرار اليومي عبر `notification_reminder_log`، ثم يدرج في `notifications`. هذه الإضافة تغذي قائمة Flutter نظريًا، لكنها لا تضيف أي قناة Flutter أو push native.

### موثوقية تسليم المهمة

`supabase/migrations/078_task_dispatch_reliability.sql:124-141` يوفّر RPC `mobile_mark_task_opened` ويحدّث `received_at` و`opened_at` وحالة المهمة. هذا عقد لتسليم/فتح المهمة، وليس تعليم سجل `notifications` كمقروء؛ Flutter لا يستدعيه من مسار فتح الإشعار داخل `AppShell`.

## الفجوات القابلة للتنفيذ داخل Flutter

1. **إضافة طبقة إشعارات منفصلة** داخل `apps/flutter/lib` (مثل `features/notifications` أو `core/notifications`) بدل إبقاء استعلام Supabase وواجهة العرض داخل `AppShell`. الطبقة ينبغي أن تملك نموذجًا typed، وحالة loading/error/empty، وrefresh، وتبقي RLS مصدر الصلاحية.
2. **إضافة refresh/realtime للإشعارات**: الاشتراك في `postgres_changes` على `public.notifications` مع filter للمستلم الحالي، أو إعادة التحميل عند عودة التطبيق إلى foreground. يجب إزالة الاشتراك عند logout أو dispose ومنع تسرب القنوات.
3. **إكمال UX القائمة**: إضافة عداد غير مقروء حقيقي في زر الرأس بدل الأيقونة الثابتة فقط، وتمييز العناصر الجديدة، وتوفير إعادة المحاولة، وتنسيق التاريخ والشدة بالعربية، وربط الضغط بمسار المهمة مع fallback واضح للإشعار العام.
4. **تنفيذ فتح المهمة بصورة صحيحة**: قبل/بعد الانتقال إلى `/tasks/:taskId` يمكن استدعاء `mobile_mark_task_opened` عند ملاءمة الحالة، مع عدم اعتبار ذلك بديلًا عن `read_at`؛ يلزم فصل «فتح المهمة» عن «قراءة الإشعار».
5. **إضافة cache جلسة/ذاكرة اختيارية** للقائمة بحيث لا تختفي آخر البيانات عند فشل الشبكة، مع إظهار أنها قديمة. لا ينبغي تخزين بيانات مستخدم آخر بعد تبديل الحساب.
6. **إضافة اختبارات Dart/Widget** لـ: نجاح الاستعلام، قائمة فارغة، خطأ RLS/شبكة، إشعار بلا `task_id`، إشعار بمهمة، حالة unread، إعادة المحاولة، وتبديل المستخدم. كما يلزم اختبار Realtime وإزالة الاشتراك.
7. **اختيار استراتيجية push أصلية معتمدة** (FCM/APNs عبر حزمة Flutter مناسبة أو استمرار Expo token عبر حل متوافق) قبل كتابة كود تسجيل الجهاز. لا يجوز افتراض أن `expo_push_token` يمكن توليده أو استهلاكه من Flutter بلا مكتبة/عقد مدعوم.
8. **بعد اعتماد العقد فقط**: ربط دورة الصلاحية والتسجيل/التعطيل في session lifecycle، ومعالجة foreground/background/terminated، واختبار payload وفتح المهمة على Android وiOS.

## حواجز Backend والعقود

1. **حاجز push متعدد المنصات:** العقد الحالي يخزن `expo_push_token` ويرسل إلى Expo Push Service. لا يوجد حقل أو RPC لـFCM/APNs token، ولا عقد يحدد كيفية تسجيل Flutter native token أو تحديثه أو إبطال جهاز واحد. هذا يمنع تنفيذ Push Flutter بشكل آمن دون قرار معماري وترحيل/عقد جديد.
2. **حاجز تعليم الإشعار كمقروء:** الجدول يملك `read_at`، لكن `053_direct_task_delivery_notifications.sql` ينشئ SELECT فقط؛ لا توجد سياسة UPDATE/دالة مصرح بها لتحديث `read_at`. لذلك لا يستطيع Flutter تعليم الإشعار كمقروء عبر العقد الحالي دون تجاوز غير مسموح أو تعديل Backend.
3. **حاجز تتبع التسليم:** `dispatch_notification_push` يستدعي `net.http_post` داخل trigger، لكنه لا يسجل response/ticket/status ولا يملك retry أو معالجة token غير صالح. تسليم push موصوف صراحة بأنه best effort، فلا يمكن اعتبار وصوله مضمونًا أو بناء badge موثوق عليه.
4. **حاجز التحقق من بيئة الإنتاج:** جدول `notifications` وعقود 053/069/070 قد تكون غير مطبقة في بيئة فعلية قديمة؛ Expo نفسه يتعامل مع غياب relation في `listMyNotifications`. Flutter يعرض خطأ عامًا ولا يميز missing relation عن RLS أو الشبكة.
5. **حاجز تعدد العضويات:** `register_push_device` يختار أول عضوية نشطة للمستخدم (`069:43-48`). إذا كان المستخدم منتميًا لأكثر من مؤسسة، فالتسجيل لا يستقبل `organization_id` صريحًا وقد لا يطابق المؤسسة النشطة في واجهة Flutter.
6. **حاجز route payload:** Backend يرسل `route: '/tasks'` حتى عندما يوجد `taskId`، ولا يوجد عقد يحدد route/deep-link آمنًا أو سلوكًا عند حذف المهمة. Expo يتجاهل payload حاليًا وينقل إلى `/tasks`، وFlutter لا يملك مستمعًا أصلًا.
7. **حاجز الترحيلات:** طلب المرحلة لا يجيز تعديل Backend؛ لذلك لا يمكن سد الحواجز السابقة داخل Flutter فقط. أي حل يتطلب migration أو RPC/policy جديدًا يجب اعتماده منفصلًا واختباره على بيئة غير إنتاجية.

## حواجز الأدوات والتحقق

1. لا يوجد Android SDK متاح في البيئة الحالية بحسب توثيق مشروع Flutter، ولا توجد أداة iOS/Xcode؛ لذلك لا يمكن إثبات طلب الصلاحية، القناة، الصوت، استقبال push، أو سلوك التطبيق المغلق على جهاز حقيقي.
2. لا يوجد في Flutter dependency أو scaffold مثبت لتنفيذ FCM/APNs/local notifications؛ اختبار المصدر وحده لا يثبت التكامل native.
3. لا توجد اختبارات Flutter للإشعارات أو Widget للـAppShell؛ الاختبار الموجود في `apps/flutter/test/core/offline_queue_test.dart` لا يغطي هذه المرحلة.
4. لا ينبغي تشغيل migration أو اختبار push ضد الإنتاج كجزء من هذا التدقيق. يلزم Supabase غير إنتاجي، جهاز Android/iOS فعلي، ومفاتيح/مشروع push مضبوط عند تنفيذ المرحلة التالية.

## ترتيب إنجاز مقترح دون خلط العقود

1. أولًا: اعتماد قرار Backend: إما عقد Expo مستمر مع طريقة Flutter مدعومة، أو عقد FCM/APNs جديد، مع RPC آمن لـ`mark_notification_read` وسياسة/صلاحية مناسبة.
2. ثانيًا: نقل القراءة الداخلية إلى repository/provider typed، وإضافة cache وRealtime/foreground refresh والعداد والاختبارات.
3. ثالثًا: تنفيذ native push/local notifications وربط دورة الجلسة، ثم deep link من payload إلى المهمة.
4. رابعًا: اختبار مصادقة/RLS، تعدد الأجهزة، logout، token rotation، الإشعارات المتأخرة، التطبيق في foreground/background/terminated، وأداء القائمة على جهاز حقيقي.

## الحكم النهائي

**الحالة: جزئي / غير جاهز للاستبدال.** الجزء المنقول القابل للإثبات هو عرض إشعارات Supabase الداخلية وفتح المهمة المرتبطة من bottom sheet. تسجيل الجهاز، push، التنبيه المحلي، التحديث الحي، deep links، والقراءة المؤكدة لم تُنقل. أكبر عائقين ليسا UI Flutter فقط: عقد Backend الحالي Expo-specific، ولا يوجد عقد مصرح به لتحديث `read_at`. 
