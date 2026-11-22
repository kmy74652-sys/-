# تدقيق المرحلة 09 — الاختبارات والبناء

- **النطاق:** Flutter فقط في مرحلة الاختبارات والبناء، مع مقارنة Expo وFlutter والعقود الظاهرة في `supabase/migrations`.
- **المستودع:** `/home/ubuntu/alshaeri-work/repo`
- **الملفات المرجعية المفحوصة:** `apps/flutter/pubspec.yaml`، `apps/flutter/test`، `apps/flutter/android`، `apps/flutter/README.md`، وملفات البناء/الاختبار المقابلة في `apps/mobile` و`.github/workflows`، مع مسح migrations.
- **تاريخ التدقيق:** 2026-11-22.
- **القيود:** لم يتم تعديل كود التطبيق أو Backend، ولم يتم إنشاء commit. الملف الحالي هو مخرج التدقيق فقط.

## الخلاصة التنفيذية

حالة Flutter في هذه المرحلة **غير قابلة للاعتماد كمرشح إصدار**. يوجد scaffold Android صالح مبدئيًا، وملف `pubspec.yaml` يضم الاعتماديات اللازمة للتطبيق، واختبار وحدة حقيقي واحد يغطي نماذج طابور العمل دون اتصال. لكن لا توجد في الشجرة إلا خمسة اختبارات داخل ملف واحد، ولا توجد اختبارات Widget أو Integration أو اختبارات عقود Supabase أو اختبارات بناء/تثبيت. كذلك تعذر تشغيل الاختبارات والتحليل والبناء لأن أمر `flutter` غير موجود، والمسار البديل الموثق في README (`/home/ubuntu/tools/flutter/...`) غير موجود أيضًا، ولا توجد Android SDK أو متغيرات `ANDROID_HOME`/`ANDROID_SDK_ROOT` في البيئة.

مقابل ذلك، يملك Expo اختبارات سلوك/أمن متعددة عبر أوامر `pnpm test:*`، وفحوص `typecheck`، وworkflow لبناء APK والتحقق من وجود artifact. لا يوجد مقابل Flutter في CI أو script اختبار/بناء مكافئ. لذلك لا يمكن اعتبار نجاح static analysis أو وجود ملفات Android دليلًا على أن Flutter يبني أو يحافظ على parity مع Expo.

## ما هو منفذ فعليًا

1. **تهيئة Flutter الأساسية موجودة:** `apps/flutter/pubspec.yaml` يعرّف Flutter SDK `>=3.3.0 <4.0.0`، و`flutter_test` و`flutter_lints`، واعتماديات Supabase وRiverpod وGoRouter والاتصال والتخزين والملفات والصور والإشعارات المحلية.
2. **اختبار وحدة منفذ ومحدد النطاق:** `apps/flutter/test/core/offline_queue_test.dart` يختبر ثبات معرّف عنصر الطابور، round-trip للحقول المتداخلة والتواريخ، رفض العناصر المشوهة، رفض أنواع الطابور المجهولة، وحفظ حالة العنصر المحجوب ورسالة الخطأ. هذا اختبار مفيد لكنه لا يغطي التطبيق أو الشبكة أو قاعدة البيانات.
3. **هيكل Android موجود:** `apps/flutter/android` يحتوي Gradle Kotlin DSL، `MainActivity`، manifest، intent filter للمخطط `alshaeri`، `applicationId`/namespace `com.alshaeri.mobile`، ونسخة release تستخدم توقيع debug مؤقتًا.
4. **إعدادات Flutter الأساسية متسقة مع Expo جزئيًا:** اسم التطبيق العربي «مانجمنت»، RTL، package ID `com.alshaeri.mobile`، ومخطط deep link `alshaeri` متوافقون مع القيم الظاهرة في `apps/mobile/app.json`.
5. **تغطية أسماء عقود RPC:** تم استخراج 37 اسم RPC مستعملة في `apps/flutter/lib`. كل الأسماء لها تعريفات ظاهرة في migrations، بما فيها `mobile_my_profile`، تحديث/إرسال/مراجعة المهام، مصمم التقارير والمهام، HR، الاتفاقيات، وطلب نشر المهام. لم يظهر اسم RPC مفقود في المسح النصي.
6. **اعتماد Flutter على مفاتيح عميل صحيحة مبدئيًا:** `app_config.dart` يستخدم `SUPABASE_URL` و`SUPABASE_ANON_KEY` من dart-define، ولا يظهر service role key في الملفات المفحوصة. تبقى RLS وAuthorization في Backend هي المرجع النهائي.

## نتائج الاختبارات والتحليل والبناء

### Flutter

تمت محاولة:

- `flutter test`
- `flutter analyze`
- `flutter build apk --release`
- المسار البديل المذكور في README باستخدام `/home/ubuntu/tools/flutter/bin/cache/dart-sdk/bin/dart` و`flutter_tools.dart`.

النتيجة: **لم يبدأ أي أمر Flutter**. السبب الأول أن `flutter` غير موجود في PATH. والسبب الثاني أن المسار البديل الموثق نفسه غير موجود (`No such file or directory`). لذلك لا توجد نتيجة pass/fail للكود يمكن نسبتها إلى test runner أو analyzer، ولا يجوز تسجيل المرحلة كناجحة.

كما أن فحص البيئة أظهر Java 21 فقط، دون Android SDK أو `ANDROID_HOME` أو `ANDROID_SDK_ROOT` أو أدوات `adb`/`sdkmanager`. وبناءً عليه لم يمكن الوصول إلى Gradle/Flutter build verification.

### Expo/React Native كخط أساس

- `apps/mobile/package.json` يملك `typecheck` وscripts تشغيل Android/iOS.
- `.github/workflows/verify-administrative-app.yml` و`verify-administration-fixes.yml` يشغلان typecheck ومجموعات اختبارات سلوكية وأمنية، منها task workflow وreport designer وreport submissions وHR والاتفاقيات والإشعارات.
- `.github/workflows/android-apk.yml` يجهز Android، ينفذ Expo prebuild، يبني APK، ويتحقق من أن artifact غير فارغ.
- `apps/mobile/eas.json` يحدد APK للـ preview وAAB للإنتاج.

لا يوجد في Flutter ما يعادل هذه الاختبارات أو workflows أو تعريف preview/production للبناء.

## فجوات قابلة للتنفيذ داخل Flutter

مرتبة حسب الأولوية لتمكين إغلاق المرحلة، دون تنفيذها في هذا التدقيق:

1. **إضافة طبقة تشغيل قابلة لإعادة الإنتاج:** تثبيت Flutter stable وDart وAndroid SDK/Build Tools، إزالة الاعتماد على `local.properties` ذي المسار المحلي الصلب، وتوثيق/تحقق `flutter doctor -v` ونسخ Java/Gradle/SDK.
2. **إضافة أوامر وCI لـ Flutter:** workflow يشغل `flutter pub get`, `flutter analyze`, `flutter test --coverage`، ثم `flutter build apk --release` أو AAB، ويرفع artifact ويتحقق من وجوده. يجب تمرير Supabase URL والمفتاح العام فقط كأسرار/متغيرات CI.
3. **توسيع الاختبارات:** إضافة unit tests لـ session/config/router وserialization وvalidation وoffline retry/idempotency، ثم Widget tests للشاشات الحرجة، وIntegration tests لتسجيل الدخول، قائمة/تفاصيل المهمة، draft/submit/review، رفع المرفقات، وإعادة الاتصال.
4. **اختبارات عقد Supabase:** اختبار typed payloads والـ RPC parameters والنتائج والأخطاء المتوقعة (`permission_denied`, `task_not_found`, `invalid_task_schedule`) ضد مشروع staging، مع fixtures لمستخدمين وأدوار وفروع مختلفة. وجود اسم RPC في migrations لا يثبت صحة التوقيع أو RLS runtime.
5. **اختبار الطابور دون اتصال على جهاز:** تغطية lifecycle والتزامن وإعادة المحاولة، انتقال blocked، duplicate/idempotency، تغيير المستخدم، وفشل/استئناف رفع الملفات. الاختبار الحالي يغطي serialization فقط.
6. **إكمال مسار الإشعارات في Flutter:** Flutter يعرض صفوف `notifications` لكنه لا يسجل device token ولا يهيئ foreground/background local notifications. يجب تنفيذ تكامل أصلي واضح أو إبقاء الميزة معلّمة كغير مدعومة؛ لا يجوز إرسال FCM/APNs token إلى عقد Expo الحالي.
7. **إضافة اختبارات بناء/تثبيت Android:** التحقق من launch، RTL، deep link `alshaeri://`، image/file picker، notification permission، upload، وupgrade/install-over-existing-app.
8. **فصل release signing عن debug:** `android/app/build.gradle.kts` يوقع release باستخدام debug signing. يلزم إعداد signing آمن في CI/الإصدار، مع تثبيت package ID والتحقق من key continuity قبل استبدال تطبيق Expo.
9. **فحص parity وظيفي موجه للاختبارات:** نقل حالات Expo المهمة إلى Flutter، خصوصًا report designer، task designer/publication review، HR/agreements، reviewer controls، branch administration، report export، accessibility، timezone Asia/Aden، وconflict handling.
10. **إضافة بوابة جودة:** منع release إذا فشل analyze/test أو غاب artifact أو لم تمر اختبارات العقد، وتسجيل coverage وحد أدنى متفق عليه بدل الاكتفاء بوجود اختبار واحد.

## مقارنة العقود والحواجز Backend/tools

### ما تم التحقق منه

- أسماء RPC الـ37 المستخدمة في Flutter موجودة في migrations بصيغ نهائية أو `CREATE OR REPLACE` لاحقة. هذا يشمل التوقيع ذي 10 معاملات لـ `assign_task_from_template` في migration الحديثة، مع `p_idempotency_key` اختياريًا.
- Flutter يستعمل `mobile_submit_task_report` و`mobile_submit_task_report_form` مع مفاتيح idempotency، ويتعامل مع snapshots/drafts، وهي عقود ظاهرة في migrations.
- مسار `report_submissions` لديه جدول وRLS وtrigger للتحقق من الحالة والحقول المطلوبة في migrations 083–086، لذا يجب اختبار عمليات insert/update من Flutter ضد هذه القيود بدل تجاوزها.

### الحواجز أو مخاطر العقد

1. **حاجز أدوات حاسم:** Flutter SDK غير مثبت/غير متاح في PATH، والمسار الذي يذكره README غير موجود. لا يمكن اعتماد test/analyze/build حتى تُصلح بيئة التنفيذ.
2. **حاجز Android حاسم:** لا Android SDK ولا أدوات platform/build/adb ظاهرة، فلا يمكن إثبات APK أو تشغيل smoke tests.
3. **حاجز توقيع إصدار:** release يستخدم debug key مؤقتًا. هذا يمنع اعتبار APK صالحًا للنشر أو upgrade فوق Expo، حتى لو نجح البناء لاحقًا.
4. **عقد push غير قابل لإعادة الاستخدام تلقائيًا:** Backend في migration 069 يعرّف `register_push_device(p_expo_push_token, p_platform, p_device_name)` ويخزن Expo push tokens، وExpo يستدعيه فعلًا. Flutter لا يستدعيه ولا يملك عقدًا بديلًا لـ FCM/APNs؛ لذلك تسجيل token أصلي مباشرة سيكون خرقًا للعقد، وليس إصلاحًا آمنًا.
5. **صلاحيات RLS لا يمكن إثباتها static:** نجاح أسماء RPC لا يثبت أن حساب employee/manager/owner يستطيع المسار المقصود أو أن select المباشر من Flutter يمر في كل الحالات. يلزم staging data واختبارات صلاحيات حقيقية.
6. **مسارات legacy/modern متجاورة:** migrations تحتوي تعريفات متعاقبة لنفس RPC وبعض جداول legacy مثل `task_report_fields` إلى جانب snapshots و`task_template_report_fields`. يجب تثبيت schema snapshot/production الفعلية في staging قبل كتابة golden tests، حتى لا تمر اختبارات على عقد قديم بالخطأ.
7. **التوقيع والبيانات الزمنية:** عقود المهام تستخدم `timestamptz` وBackend يضبط Asia/Aden في أجزاء من النظام؛ يلزم اختبار parsing وإرسال due/start خصوصًا حول المنطقة الزمنية والتوقيت الصيفي/الحدود، لا مجرد اختبار واجهة.

## الملفات المرشحة للتغيير لإغلاق الفجوات (اقتراح فقط)

لم تُعدّل هذه الملفات. القائمة التالية تحدد أماكن العمل المحتملة:

- `.github/workflows/flutter-qa.yml` أو workflow جديد مماثل.
- `apps/flutter/pubspec.yaml` لإضافة test/integration/dev tooling عند اعتمادها.
- `apps/flutter/test/` لإضافة اختبارات unit/widget/contract.
- `apps/flutter/integration_test/` لاختبارات الجهاز والمسارات الحرجة.
- `apps/flutter/android/app/build.gradle.kts` وملفات signing/manifest عند اعتماد إعداد إصدار آمن.
- `apps/flutter/android/local.properties` أو آلية CI البديلة؛ لا ينبغي تثبيت مسار جهاز شخصي في المستودع.
- `apps/flutter/README.md` لتحديث متطلبات SDK وأوامر QA ونتيجة البناء بعد توفير بيئة حقيقية.
- طبقة Flutter الخاصة بالإشعارات (ملف خدمة جديد أو موضع التكامل القائم) فقط بعد قرار عقد push رسمي؛ لا تعدل migrations تلقائيًا.

## حكم المرحلة

**الحالة: غير مكتملة / محجوبة بيئيًا.** يوجد تنفيذ أولي واختبار وحدة واحد، وتوجد مواءمة أسماء جيدة مع Supabase، لكن لا يوجد دليل تشغيل آلي ناجح للاختبارات أو التحليل أو البناء. الأولوية العملية هي تجهيز Flutter/Android في CI أو جهاز موثوق، ثم إضافة بوابة analyze/test/build واختبارات عقد staging، وبعدها معالجة signing وpush parity قبل إعلان Flutter بديلًا قابلًا للإصدار عن Expo.
