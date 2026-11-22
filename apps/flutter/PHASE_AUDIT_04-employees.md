# تدقيق المرحلة 04 — الموظفون والفروع

## نطاق التدقيق

تم فحص المرحلة المحددة فقط: **الموظفون والفروع**. تمت مقارنة:

- Expo: `apps/mobile/app/admin.tsx`
- Expo: `apps/mobile/lib/adminData.ts`
- Expo المرتبط بإدارة حسابات الموظفين: `apps/mobile/app/settings.tsx`
- Flutter: `apps/flutter/lib/features/admin/admin_screen.dart`
- Flutter: `apps/flutter/lib/features/settings/settings_screen.dart`
- العقود ذات الصلة في `supabase/migrations`، إضافة إلى عقد Edge Function `supabase/functions/employee-code-auth/index.ts` لأنه مسار التنفيذ الفعلي لإنشاء وتحديث حسابات الموظفين وإدارة الفروع.

لم يتم تعديل أي كود تطبيق أو Backend، ولم يتم إنشاء commit.

## خلاصة الحالة

المرحلة **منفذة جزئياً وبنية الفروع أقرب إلى الاكتمال من بنية الموظفين**.

في Flutter، لوحة الإدارة تحمل نفس مصادر بيانات Expo الأساسية من Supabase، وتعرض الموظفين والفروع وفق صلاحيات RLS/permissions. كما أن إدارة دورة حياة الفرع (إنشاء، تعديل الاسم، أرشفة، إعادة تفعيل، حذف نهائي) موصولة بعقد Backend موجودة. أما إدارة حسابات الموظفين ورموز الدخول فهي موجودة في `SettingsScreen`، لكنها غير متاحة للمدير التنفيذي (`admin_followup`) بسبب شرط Flutter محلي يقصر السماح على وجود دور `owner`، في حين أن Expo وBackend يسمحان بالمدير التنفيذي المخوّل بصلاحية `employees.manage`.

كذلك، قسم الموظفين داخل `AdminScreen` في Flutter للقراءة فقط؛ لا يوفر من القائمة نفسها إنشاء/تعديل/تعليق/رمز دخول/سجل تدقيق. هذا ليس خللاً في عقد Backend، لكنه فجوة قابلـة للتنفيذ في طبقة Flutter إذا كان المطلوب تكافؤ تجربة Expo.

## ما هو منفذ في Flutter

### 1. تحميل لوحة الإدارة والبيانات الأساسية

`AdminScreen` ينفذ `mobile_my_profile` ويتحقق من الجلسة ووجود ملف موظف نشط ومن permission `tasks.manage`. بعد ذلك يقرأ، بحدود صريحة، الجداول نفسها التي يقرأها Expo في `adminData.ts`:

- `tasks` بحد 200 مع استبعاد `deleted_at`.
- `branches` بحد 100 وترتيب الكود.
- `organization_memberships` بحد 200.
- `task_reports` بحد 100.
- `employee_role_reports` بحد 100.
- `task_activity_log` بحد 100.

هذا متسق مع طبقة Expo من ناحية أسماء الجداول والأعمدة وعقود القراءة. Flutter يعرض الموظفين والفروع الخام، بينما Expo يطبع أسماء الفروع والأدوار ويربط `role_assignments` بالموظف؛ لذلك Flutter أقل ثراءً في العرض لكنه لا يستخدم عقداً مختلفة للقراءة.

### 2. صلاحيات العرض

Flutter يطبق فحوصاً منفصلة تقريباً عن Expo:

- الفروع: `branches.read_all` أو `branches.manage`.
- الموظفون: `employees.read` أو `employees.manage`.
- النشاط: `audit.read`.
- التقارير والأداء: `reports.read_all` أو `tasks.review`.

وتتطابق هذه القاعدة مع منطق Expo في `admin.tsx` بالنسبة لعرض الموظفين والفروع.

### 3. إدارة الفروع

في `AdminScreen` توجد واجهة كاملة نسبياً لـ:

- إنشاء فرع بكود واسم.
- تعديل اسم فرع نشط.
- أرشفة الفرع.
- إعادة تفعيل فرع مؤرشف.
- حذف نهائي مع تأكيد إضافي باسم الفرع.
- إعادة تحميل القائمة بعد نجاح العملية.
- منع عمليات الإدارة إذا لم توجد `branches.manage` أو لم يتم تحديد المؤسسة.

العمليات غير الحذْف تستخدم Edge Function `employee-code-auth` بالحمولة المتوافقة مع Expo:

```text
{ action: 'manage_branch', branchAction, branchId, code, name }
```

والحذف يستخدم `admin_delete_branch` مع `p_organization_id` و`p_branch_id`، وهو متوافق مع migration `055_management_mutations_rbac.sql`.

### 4. إدارة الموظفين ورموز الدخول الموجودة في Flutter

`SettingsScreen` يحتوي فعلياً على:

- تحميل قائمة الموظفين والفروع النشطة من `employee-code-auth` action `list`.
- إنشاء موظف عبر `create_employee`.
- تعديل الاسم والرقم والدور والفرع والحالة عبر `update_employee`.
- تعيين أو تغيير رمز الدخول عبر `set_code`.
- إلغاء الرمز عبر `revoke_code`.
- تحميل سجل التعديلات عبر `audit`.
- حذف الموظف غير المالك عبر `admin_delete_employee_record`.
- حماية ذاتية جزئية في الواجهة، وحماية المالك نهائياً في Backend.

هذه الأفعال متطابقة في شكلها مع `apps/mobile/app/settings.tsx`، كما أن Flutter لا يحاول حفظ رمز الدخول أو قراءته بعد الحفظ.

### 5. هوية المؤسسة المرتبطة بالمرحلة

Flutter ينفذ رفع الشعار إلى bucket `organization-branding` ثم RPC `save_organization_branding`. هذا متوافق مع migrations `075_organization_branding_storage.sql` و`077_save_organization_branding_rpc.sql` من حيث bucket، صيغ الصور، حد 5MB، ومعلمات RPC.

## الفجوات القابلة للتنفيذ داخل Flutter

### فجوة 1 — المدير التنفيذي المخوّل ممنوع محلياً من شاشة إعدادات الموظفين

في `settings_screen.dart` يتم حساب:

```dart
_owner = roles.any((r) => r['code'] == 'owner');
_allowed = _owner && permissions.contains('employees.manage');
```

هذا يختلف عن Expo الذي يسمح بالمالك **أو** `admin_followup` مع `employees.manage`، ويختلف عن Backend أيضاً: `verifyOwner` في Edge Function يقبل الدور التنفيذي مع permission `employees.manage`، و`admin_update_employee` في migration `046` يقبل `owner` أو `admin_followup`.

**الأثر:** المدير التنفيذي المخوّل يرى رسالة عدم الإتاحة ولا يستطيع إنشاء/تعديل الموظفين أو إدارة الرموز من Flutter، رغم أن العقد الخلفي يسمح بذلك.

**الإصلاح القابل للتنفيذ:** فصل `isOwner` عن `canManageEmployees`؛ اجعل السماح الإداري يعتمد على وجود `owner` أو `admin_followup` مع `employees.manage`. أبقِ صلاحيات الهوية/الشعار محصورة بالمالك كما يفعل Expo (`canEditBrand = actualOwner`).

### فجوة 2 — قسم الموظفين في `AdminScreen` للعرض فقط

عند اختيار `employees`، يعرض Flutter سجلات مختصرة عبر `_record` فقط. لا توجد أزرار أو انتقال مباشر إلى إدارة الموظف/رمزه/سجل تدقيقه، ولا يوجد في شاشة الإدارة نفسها إنشاء موظف أو تحديث حالة.

Expo يفصل عرض الموظفين في `admin.tsx` عن الإدارة الكاملة في `/settings?tab=employees`، لكنه يوفر مساراً واضحاً من لوحة الإدارة (`navigateFromHome`). Flutter لديه مسار `/settings` من Home، لكن عنصر الموظفين داخل `AdminScreen` لا يقود إلى إعدادات الموظفين ولا يوضح أن التعديل موجود في شاشة أخرى.

**الإصلاح القابل للتنفيذ:** إما إضافة CTA واضح من قسم الموظفين إلى `/settings`، أو توسيع القسم ليستخدم مكونات إدارة الموظفين نفسها. الحد الأدنى المطلوب لتكافؤ Expo هو زر "إدارة الموظفين والحسابات" يظهر لمن لديه `employees.manage` وينقل إلى `/settings`.

### فجوة 3 — خيار دور المالك ظاهر للمدير التنفيذي في تعديل موظف

في `_edit`، قائمة الأدوار تتضمن `owner` لكل مستخدم، دون تصفيتها حسب صلاحية الممثل الحالي. Backend سيرفض هذا عبر `owner_role_requires_owner`، لكن المستخدم سيصل إلى خيار غير قابل للتنفيذ ويحصل على خطأ عام.

**الإصلاح القابل للتنفيذ:** إظهار `owner` فقط إذا كان المستخدم الحالي مالكاً، كما يفعل Expo عبر `roleOptions.filter(([code]) => code !== 'owner' || canAssignOwner)`.

### فجوة 4 — رسائل أخطاء Flutter أقل دقة من عقد Expo

Flutter يحول معظم أخطاء Edge Function إلى رسائل عامة، ولا يميز 401/403/404/503 أو أخطاء مثل `employee_no_exists`, `branch_not_found`, `employee_auth_not_linked`, `branch_code_exists`. Expo لديه `functionErrorText` يميز هذه الحالات ويشرح أن migration أو خدمة الرموز غير جاهزة.

**الإصلاح القابل للتنفيذ:** إضافة تطبيع لأخطاء `FunctionException` حسب status وmessage، خصوصاً أخطاء الصلاحية، عدم ربط حساب Auth، تكرار الرقم الوظيفي/كود الفرع، وعدم تطبيق migration.

### فجوة 5 — حالة فشل تأكيد حذف الفرع غير واضحة

الحوار يطلب كتابة اسم الفرع، لكن زر التأكيد لا يعرض للمستخدم حالة عدم تطابق الاسم؛ عند الخطأ يغلق الحوار بصمت. هذا لا يكسر العقد، لكنه يسبب التباساً تشغيلياً.

**الإصلاح القابل للتنفيذ:** تعطيل زر الحذف حتى يطابق النص، أو عرض رسالة تحقق داخل الحوار.

### فجوة 6 — إنشاء `TextEditingController` أثناء بناء بطاقة الفرع

`_branchCard` ينشئ `TextEditingController` داخل `build` لكل بطاقة. هذا قد يفقد حالة الإدخال عند إعادة البناء ويزيد التسريبات/التكلفة، خصوصاً أثناء `_load` أو تغيّر حالة الفرع.

**الإصلاح القابل للتنفيذ:** استخدام controller مستمر لكل فرع أو `TextFormField(initialValue)` مع حالة rename مستقرة. هذه فجوة جودة Flutter وليست حاجز عقد Backend.

### فجوة 7 — لا يوجد تحقق محلي مطابق بالكامل لعقد الفرع

Edge Function وRPC يفرضان كوداً من النمط `^[A-Z0-9_-]{2,24}$` واسماً بين 2 و120 حرفاً. Flutter يتحقق فقط من عدم الفراغ، ثم يعتمد على Backend. هذا آمن من ناحية السلطة، لكنه يسبب رحلة خطأ غير ضرورية.

**الإصلاح القابل للتنفيذ:** إضافة نفس التحقق المحلي قبل الإرسال، مع تحويل الكود إلى uppercase كما يفعل Expo.

## حواجز عقود Backend أو الأدوات

### 1. يجب نشر Edge Function مع متغيرات الأسرار المطلوبة

كل عمليات إدارة الموظفين والفروع غير الحذف تمر عبر `employee-code-auth`. الدالة تتطلب `SUPABASE_URL` ومفتاحاً publishable وsecret/service-role وفق آلية الأسماء البديلة الموجودة في المصدر. إذا لم تكن الدالة منشورة أو كانت أسرارها ناقصة، فستفشل العمليات حتى لو كانت واجهة Flutter صحيحة.

### 2. صلاحيات RPC مقصودة وليست قابلة للاستدعاء المباشر من Flutter

`admin_manage_branch` و`admin_update_employee` في migration `036` ثم `046` ممنوحان لـ `service_role` فقط. هذا ليس نقصاً في Flutter؛ المسار الصحيح هو Edge Function التي تتحقق من هوية المستخدم ثم تستدعي RPC عبر عميل إداري. لا ينبغي إعطاء Flutter service-role أو تحويل هذه RPC إلى استدعاء مباشر.

أما `admin_delete_branch` و`admin_delete_employee_record` في migration `055/056` فهما متاحان للمستخدم authenticated، لكنهما محميان بـ `management_role_allowed` وبنطاق المؤسسة. Flutter يستخدمهما بالطريقة الصحيحة مع `p_organization_id`.

### 3. ترتيب migrations ضروري لدورة حياة الفروع والموظفين

يجب أن تكون migrations ذات الصلة مطبقة بالترتيب، لا سيما:

- `033_employee_management_scope.sql` لإذن `employees.manage` وتدقيق الموظفين.
- `036_admin_management_atomicity.sql` لإجراءات الإدارة الأساسية.
- `042_allow_branch_audit_actions.sql` لإضافة أحداث `branch_created/updated/archived/reactivated` إلى قيد سجل التدقيق.
- `044_allow_employee_archive_audit.sql` للسماح بحدث `archived` عند تعليق الموظف.
- `046_preserve_owner_organization_scope.sql` للنسخة النهائية التي تجعل المالك بلا فرع وتتحقق من الفرع النشط لغير المالك.
- `055_management_mutations_rbac.sql` و`056_management_employee_auth_delete.sql` للحذف المحمي وحذف مستخدم Auth.

إذا طُبقت `036` دون `042/044` فقد تفشل معاملات أرشفة فرع أو تعليق موظف بسبب قيد audit action، وإذا غابت `046` فسيظهر تعارض في عقد المالك/الفرع.

### 4. عقد تحديث الموظف يفرض فرعاً نشطاً لكل دور غير المالك

النسخة النهائية في `046` ترفض `p_branch_id = null` لغير المالك (`branch_not_found`) وتحوّل فرع المالك إلى null. شاشة Flutter صحيحة في أغلب الحالات لأنها تشترط الفرع لغير المالك، لكن عند وجود موظف قديم بلا assignment أو فرع مؤرشف ستفشل عملية التحديث حتى يختار المستخدم فرعاً نشطاً.

### 5. أرشفة الفرع ممنوعة عند وجود موظفين نشطين

`admin_manage_branch` يرفض الأرشفة إذا وجد `role_assignments` مرتبطة بموظفين نشطين (`branch_has_active_employees`). الواجهة تعرض رسالة عامة فقط. هذا حاجز عمل مقصود للحفاظ على سلامة النطاق؛ الحل التشغيلي هو نقل الموظفين إلى فرع نشط أو تعليقهم أولاً، وليس تجاوز RPC.

### 6. حفظ الهوية يعتمد على عقدين مستقلين

حفظ الشعار يحتاج bucket وسياسات storage من `075`، وحفظ الاسم/العبارة/الرابط يحتاج RPC من `077` مع permission `organizations.update`. Flutter يسمح بالهوية للمالك فقط، وهو أضيق من permission العام لكنه متسق مع Expo. إذا لم تطبق migrations `075/077` يجب أن تبقى رسالة "تحديث قاعدة البيانات غير جاهز" ولا يعتبر ذلك فجوة في إدارة الموظفين نفسها.

## مصفوفة مقارنة مختصرة

| capability | Expo | Flutter الحالي | الحكم |
|---|---|---|---|
| عرض الموظفين من لوحة الإدارة | نعم، مع الاسم/الرقم/الدور/الفرع | نعم، عرض خام مختصر | منفذ، أقل ثراءً |
| إنشاء/تعديل الموظف | نعم من Settings | نعم من Settings | منفذ للمالك فقط فعلياً |
| إدارة المدير التنفيذي للموظفين | نعم إذا `admin_followup` + `employees.manage` | محجوبة بشرط `_owner` | فجوة Flutter مؤكدة |
| رموز الدخول والتدقيق | نعم | نعم | منفذ |
| إنشاء الفرع | نعم عبر Edge Function | نعم عبر Edge Function | منفذ |
| تعديل اسم الفرع | نعم عبر Edge Function | نعم عبر Edge Function | منفذ |
| أرشفة/تفعيل الفرع | نعم | نعم | منفذ مع حاجز الموظفين النشطين من Backend |
| حذف الفرع | نعم عبر `admin_delete_branch` | نعم عبر نفس RPC | منفذ |
| منع دور owner لغير المالك | Expo يخفي الخيار | Flutter يعرضه ثم Backend يرفضه | فجوة UX قابلة للإصلاح |
| هوية المؤسسة | نعم | نعم | منفذ بشرط migrations 075/077 |

## الملفات المتوقع تغييرها عند التنفيذ لاحقاً

هذه ليست تغييرات نُفذت في هذا التدقيق؛ هي قائمة تنفيذ مقترحة فقط:

1. `apps/flutter/lib/features/settings/settings_screen.dart` — تصحيح أهلية `admin_followup`، تصفية دور `owner`، وتحسين رسائل الأخطاء.
2. `apps/flutter/lib/features/admin/admin_screen.dart` — إضافة CTA إلى إعدادات الموظفين أو دمج إجراءات إدارة الموظف، وتحسين تحقق/تأكيد الفروع وحالة controllers.
3. قد يلزم اختبار Flutter خاص بالمسارات والصلاحيات، إن كان إطار الاختبارات متاحاً في المستودع.

## الحكم النهائي

- **الفروع:** منفذة وظيفياً في Flutter ومتوافقة مع عقود Expo/Backend، مع فجوات UX والتحقق المحلي ورسائل الأخطاء.
- **عرض الموظفين:** منفذ.
- **إدارة حسابات الموظفين:** موجودة في Flutter Settings لكنها ليست مكافئة لـ Expo بسبب حجب المدير التنفيذي المخوّل محلياً.
- **Backend:** العقود المطلوبة موجودة، لكن نجاح التشغيل مشروط بتطبيق سلسلة migrations كاملة ونشر `employee-code-auth` بإعداداته. لا يوجد مبرر لتعديل Backend لمعالجة الفجوة الأساسية؛ الإصلاح الأولي داخل Flutter.
