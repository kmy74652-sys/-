# تدقيق المرحلة 05: التقارير

- **النطاق:** فحص مرحلة «التقارير» فقط، مع مقارنة واجهات Expo المتاحة فعليًا، شاشات Flutter، ومigrations التقارير في `supabase/migrations`.
- **المستودع:** `/home/ubuntu/alshaeri-work/repo`
- **تاريخ التدقيق:** 2026-11-22
- **القرار:** التنفيذ موجود وواسع في Flutter، لكن التكافؤ مع Expo وعقد التقارير غير مكتمل؛ يلزم استكمال التحقق المحلي/العرض لبعض الأنواع، وتوحيد مسار تقارير الدور، وإضافة اختبارات تشغيلية.

## ملاحظة على الملفات المرجعية

الملف المرجعي `apps/mobile/app/reports.tsx` غير موجود في النسخة المفحوصة. مسارات Expo الحالية لا تحتوي route باسم `reports.tsx`؛ شاشة التقارير موزعة على مكونات وطبقات مكتبة، أهمها:

- `apps/mobile/components/EmployeeDynamicReportsPanel.tsx`
- `apps/mobile/components/EmployeeRoleReportPanel.tsx`
- `apps/mobile/lib/dynamicReports.ts`
- `apps/mobile/lib/employeeRoleReports.ts`
- `apps/mobile/lib/reportSchema.ts`

لذلك تمت المقارنة مع هذه الملفات الفعلية، مع اعتبار غياب route المطلوب فجوة توثيق/مرجعية وليس دليلاً على غياب الميزة.

## العقود التي تمت مراجعتها

- `068_employee_role_reports.sql`: جدول `employee_role_reports`، قيد التقرير اليومي الواحد، RLS، وRPCs `mobile_submit_employee_role_report` و`review_employee_role_report`.
- `073_employee_dynamic_reports.sql`: RPCs `list_my_dynamic_report_forms` و`submit_my_dynamic_report`، اختيار آخر نسخة منشورة ومعتمدة، التحقق من الدور/الفرع، والحقول المطلوبة.
- `083_report_submissions_workflow.sql`: جدول `report_submissions`، حالات `draft/submitted/reviewed/approved/returned`، trigger انتقالات الحالة، وسياسات القراءة/الإدراج/التحديث.
- `084_validate_report_submission_answers.sql`: تحقق Backend من الحقول المطلوبة عند الإرسال وإعادة الإرسال.
- `085_harden_report_submissions_anon_access.sql` و`086_limit_report_submissions_table_privileges.sql`: منع anonymous وتطبيق أقل امتيازات على جدول الإرساليات.
- `059_report_field_types_extension.sql` و`060_report_field_types_rpc_allowlist.sql`: قائمة أنواع الحقول الموسعة.
- `030_calculated_report_validation.sql` و`031_signature_report_validation.sql`: تحقق تقارير المهام من الأنواع/الخيارات/الصيغ والتوقيع.

## ما هو منفذ في Flutter

### 1. لوحة المراجعة والإدارة

`apps/flutter/lib/features/reports/reports_screen.dart` تنفذ مسارًا موحدًا لثلاثة مصادر:

1. **تقارير المهام:** قراءة `task_reports` حتى 100 سجل، عرض القيم والحالة، ومراجعة التقرير عبر `mobile_review_task` أو `mobile_review_task_form_report` بحسب وجود `report_form_snapshot_id`.
2. **التقارير المستقلة:** قراءة `report_submissions` حتى 200 سجل مع بيانات النموذج، استبعاد المسودات، وعرض المراجع والمعتمد وملاحظة المراجعة.
3. **تقارير الأدوار اليومية:** قراءة `employee_role_reports` حتى 200 سجل وعرض الدور والفرع والموظف والقيم.

وتنفذ الشاشة البحث النصي، مرشحات الحالة، التبديل بين المصادر، نسخ النتائج CSV، رسائل أخطاء منفصلة، وحالة busy لكل عملية.

### 2. صلاحيات المراجعة

تحميل الصلاحيات من `mobile_my_profile` ومطابقتها مع:

- `reports.read_all` و`tasks.review` و`tasks.manage` لقراءة/مراجعة تقارير المهام.
- `report_submissions.review` للمراجعة الأولى.
- `report_submissions.approve` للاعتماد النهائي.
- `tasks.review` أو `reports.read_all` لمراجعة تقارير الأدوار.

الأزرار تُعطّل بصريًا عند غياب الصلاحية، مع بقاء التحقق الحقيقي في RLS/RPC/trigger.

### 3. إرسال التقارير المستقلة

`independent_reports_screen.dart` تنفذ:

- جلب الملف والفرع الافتراضي.
- استدعاء `list_my_dynamic_report_forms`.
- تحميل إرساليات اليوم من `report_submissions`.
- إنشاء مسودة/إرسالها، وتحديث المسودة أو التقرير المعاد.
- احترام حالات القفل `submitted/approved` والسماح بالتحرير في `draft/returned`.
- حقول `boolean/checkbox`، select، multiselect، table، signature، والمرفقات.
- رفع التوقيع كـ strokes مع إقرار consent عند وجوده.
- إرسال JSON متوافق مع `answers`، وترك التحقق الإلزامي النهائي للـ Backend.

### 4. تقارير الأدوار

يوجد مساران Flutter:

- `role_report_screen.dart`: شاشة إرسال يومي ثابتة حسب الدور، تستدعي `mobile_submit_employee_role_report`.
- `independent_reports_screen.dart`/`reports_screen.dart`: المسار الديناميكي/الإداري الذي يتعامل مع النماذج أو جدول `employee_role_reports`.

مسار الإرسال الثابت يطابق قيم Expo الحالية للأدوار والحقول الأساسية، ويدعم حالة `returned` وإعادة الإرسال، كما أن Backend يمنع إعادة إرسال التقرير عند `submitted/approved` ويشترط assignment صحيحًا.

## الفجوات القابلة للتنفيذ داخل Flutter

### أولوية عالية

1. **غياب تحقق Flutter المكافئ لـ `reportSchema.ts`.** Expo يطبق تحققًا غنيًا قبل الإرسال: numeric min/max/decimal، أطوال النص، الخيارات، التكرار في multiselect، date/date-range، system reference، barcode، table columns/rows، calculated formulas، visibility، default values، signature consent والمرفقات. Flutter يطبق حاليًا تحقق required نصي فقط في `independent_reports_screen.dart`، ويحوّل بقية القيم إلى JSON/أرقام دون إظهار أخطاء المجال للمستخدم. النتيجة تجربة أخطاء Backend غير واضحة، خصوصًا للحقول الرقمية، الجدول، التاريخ، التوقيع والصيغ المحسوبة.
2. **أنواع معتمدة في العقد لكنها غير ممثلة بعناصر UI متخصصة.** `system_reference` و`barcode` و`calculated` و`datetime` و`date` و`date_range` تعرض غالبًا كـ TextField أو JSON hint. يجب تنفيذ محررات/عرض مناسب أو منع الإرسال حتى تصبح القيمة ممثلة بالعقد المتوقع.
3. **الحقل المحسوب غير محسوب في Flutter.** Expo يملك `calculateFormula/evaluateReportField` ويدعم `sum_rows`، بينما Flutter يعرض/يحرر الحقل كإدخال نصي. هذا يسمح بقيمة محسوبة يدويًا قد يرفضها Backend في مسارات المهام، ويخالف دلالة `calculated`.
4. **تقارير المهام في Flutter للقراءة/المراجعة فقط ضمن الملفات المفحوصة.** لا توجد شاشة Flutter مقابلة لإدخال تقرير المهمة واستدعاء `mobile_submit_task_report`، ولا محرر snapshot متعدد الأنواع. إذا كانت هذه المرحلة تشمل الموظف المرسل، فهذه فجوة مسار كاملة؛ أما إذا كان النطاق إدارة التقارير فقط فيجب توثيق الاستبعاد صراحة.
5. **مسار تقارير الأدوار لا يحمّل تعريف الدور ديناميكيًا.** `role_report_screen.dart` يكرر خريطة `_configs` ثابتة، بينما Expo يضع التعريف في `employeeRoleReports.ts` أيضًا، وBackend لا يفرض مخطط الحقول/القيم. يجب توحيد مصدر التعريف أو إضافة طبقة مشتركة/اختبارات تمنع اختلاف المفاتيح والعناوين بين التطبيقات.

### أولوية متوسطة

6. **عدم عرض `repeatable` و`description` و`validation` في بعض عناصر Flutter.** `_ReportField` يقرأ key/label/type/required/longText/options/config فقط؛ الوصف وقواعد التحقق والتكرار تصل من RPC لكنها لا تدخل نموذج العرض بشكل كامل.
7. **الـ defaults لا تُطبق في Flutter.** Expo يستخدم `reportDefaultDraft` لتهيئة القيم الافتراضية. Flutter يقرأ الإجابات المحفوظة فقط؛ القيمة الافتراضية المعلنة في `config.default_value` لا تملأ الحقل عند بدء نموذج جديد.
8. **المرفقات تُخزّن Base64 داخل `answers`.** هذا يطابق ملاحظة الشاشة الحالية لكنه ليس عقد تخزين منفصلًا، وقد ينتج payload كبيرًا رغم حد 2MB لكل ملف. لا يوجد bucket/upload URL أو إزالة Base64 قبل الإدراج. ينبغي إما اعتماد هذا كحد مؤقت مع حد إجمالي واضح، أو إضافة عقد تخزين قبل توسيع الاستخدام.
9. **المسودة في التقارير الديناميكية ليست ضمن العقد الديناميكي.** `073_employee_dynamic_reports.sql` لا يعرّف `draft`؛ Flutter يستخدم draft فقط في `report_submissions`. يلزم عدم خلط التسميتين، وتوضيح أن dynamic reports تُرسل مباشرة إلى `submitted` ولا تحفظ مسودة مستقلة.
10. **تقارير الأدوار تعرض/تجلب حسب الدور والتاريخ دون تضييق الفرع في `role_report_screen.dart`.** RLS يمنع تسريب الصفوف لغير صاحبها/المراجع، لكن الاستعلام لا يضيف `branch_id`؛ الأفضل مطابقة Expo (`branchId` أو null) لتقليل البيانات وتعزيز الاتساق.
11. **عدم وجود اختبارات Flutter للتقارير.** الموجود في `apps/flutter/test` لا يغطي report schema، حالات الانتقال، parsing، JSON للجدول/التوقيع/المرفقات، أو صلاحيات العرض. يلزم اختبارات unit/widget، واختبار contract payloads مع fixtures من migrations.

## حواجز عقد Backend أو الأدوات

1. **التحقق في Backend غير موحد بين المسارات.** `084` يتحقق من الحقول المطلوبة فقط للتقارير المستقلة؛ `030/031` يحققان مجموعة أوسع لتقارير المهام؛ و`073` يتحقق من required بصيغة أبسط ولا يطبق قواعد `reportSchema.ts` كاملة. لا يستطيع Flutter سد اختلاف العقد من طرفه وحده؛ يلزم توحيد validator أو توثيق الفروق.
2. **عقد `report_submissions` يسمح بتحديث الجدول مباشرة، لكن انتقالات الحالة محكومة trigger/RLS.** هذا صالح وظيفيًا، إلا أن الأخطاء القادمة من trigger عربية عامة أو غير مصنفة، وFlutter يحولها إلى رسالة عامة. تحسين error codes/رسائل RPC سيحسن قابلية الإصلاح دون تجاوز الحماية.
3. **تقارير الدور لا تملك جدول schema للحقول.** `employee_role_reports.values` مجرد JSON object؛ Backend يتحقق من النوع العام فقط ومن assignment، ولا يتحقق من مفاتيح/أنواع الحقول الثابتة. هذا يجعل توحيد Flutter وExpo مسؤولية تطبيقية قابلة للانحراف.
4. **تشغيل أداة Flutter غير متاح في بيئة التدقيق.** الأمر `flutter analyze --no-pub` لم ينفذ لأن executable `flutter` غير مثبت (`flutter: command not found`). لذلك لم يمكن تأكيد compile/analyzer أو اختبارات widget، ولا ينبغي اعتبار غياب نتيجة التحليل نجاحًا.
5. **مسار Expo المحدد غير موجود.** عدم وجود `apps/mobile/app/reports.tsx` يمنع مقارنة route-to-route حرفية؛ المقارنة تمت مع المكونات والمكتبات الفعلية فقط.
6. **المجلد `apps/flutter/` ظاهر كـ untracked في `git status --short`.** لم يتم تعديل أو حذف أو commit أي ملف، لكن حالة التتبع الحالية تجعل إثبات diff دقيقًا من Git غير ممكن في هذه الجلسة.

## خطة تنفيذ مقترحة داخل Flutter

1. استخراج validator مشترك في Dart يحاكي contract `reportSchema.ts` للأنواع والقواعد، مع رسائل عربية قبل الإرسال.
2. إضافة محررات `date/date_range/datetime/system_reference/barcode/calculated`، وربط calculated بـ formula evaluator و`sum_rows`، وإخفاء الحقول وفق visibility.
3. توسيع `_ReportField` ليحفظ description/repeatable/validation/default، وتطبيق defaults عند إنشاء نموذج.
4. فصل payload المرفقات عن Base64 أو اعتماد حد إجمالي موثق ومتوافق مع Backend قبل الإنتاج.
5. توحيد مصدر تعريف تقارير الأدوار، وإضافة branch filter في قراءة شاشة الدور.
6. إضافة اختبارات unit/widget وfixtures تغطي الحالات `draft → submitted → reviewed → approved/returned`، required/invalid option/calculated/signature/table، وصلاحيات المراجعة.
7. تشغيل `dart format`, `flutter analyze`, والاختبارات في بيئة تحتوي Flutter SDK؛ هذه الخطوة محجوبة حاليًا بسبب الأداة.

## الملفات المرشحة للتغيير لاحقًا

- `apps/flutter/lib/features/reports/independent_reports_screen.dart`
- `apps/flutter/lib/features/reports/reports_screen.dart`
- `apps/flutter/lib/features/reports/role_report_screen.dart`
- `apps/flutter/lib/features/reports/` (إضافة validator/models/tests عند اعتماد التصميم)
- `apps/flutter/test/` (اختبارات عقود التقارير)

لم تُعدّل هذه الملفات في هذا التدقيق، ولم تُعدّل migrations أو كود Backend، ولم يُنشأ commit.
