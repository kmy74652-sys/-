# تحديثات Supabase للموبايل

## لماذا تظهر رسالة التحديث؟

تطبيق Android في commit `769bfb5` لم يعد يطلب ملف الموظف أو المهام من مسار API خارجي. بعد تسجيل الدخول، يتحقق من المستخدم عبر Supabase Auth، ثم يستدعي `public.mobile_my_profile()` للحصول على ملف الموظف وصلاحياته. إذا لم تكن الدالة منشورة في قاعدة البيانات المستهدفة، يعرض التطبيق رسالة تفيد بأن تحديث Supabase المطلوب لم يطبّق بعد. إعادة تثبيت APK لا تنشئ هذه الدالة؛ يلزم تطبيق migration على المشروع نفسه.

## ما الذي تضيفه migration 017؟

الملف `migrations/017_mobile_client_access.sql` يضيف:

- `mobile_my_profile()` لإرجاع ملف الموظف النشط المرتبط بـ`auth.uid()` فقط، مع الأدوار والصلاحيات والفروع التابعة لذلك الموظف.
- سياسة قراءة للمهام تحافظ على شرط الصلاحية `tasks.read` وتقيّد الصفوف بالمكلّف أو منشئ المهمة أو صلاحية `tasks.read_all`.
- دوال `mobile_record_task_update()`, `mobile_review_task()`, و`mobile_submit_task_report()`، وتشتق هوية الموظف من جلسة Auth بدل قبولها من الجهاز.
- إرسال التقرير وتغيير حالته للمراجعة ضمن معاملة واحدة، مع التحقق من الحقول المطلوبة وقواعد سير العمل الحالية.

كل الدوال المخصصة للهاتف تمنح التنفيذ للمستخدم المصادق فقط، وتبقي فحوص الصلاحيات وسياق المؤسسة داخل قاعدة البيانات. لا يضع التطبيق مفتاح `service_role` أو مفتاحًا سريًا في الحزمة؛ يستخدم فقط مفتاح Supabase publishable مع RLS.

## تطبيق migration

المشروع الصحيح هو المشروع الذي يطابق عنوان Supabase:

```text
https://fjmryqhdwxsocdzswnkq.supabase.co
```

طبّق جميع migrations غير المنفذة بالترتيب من جذر المستودع باستخدام حساب يملك المشروع، لا باستخدام مفتاح publishable:

```bash
supabase login
supabase link --project-ref fjmryqhdwxsocdzswnkq
supabase db push
```

يتطلب `supabase login` اعتماد Supabase CLI صالحًا، ويتطلب الربط/الدفع كلمة مرور قاعدة البيانات الفعلية إذا طلبها CLI. النص `[YOUR-PASSWORD]` في قالب URI ليس كلمة مرور. لا تضع كلمة المرور أو access token أو أي secret في Git أو تطبيق Android أو محادثة عامة. يمكن أيضًا تطبيق محتوى migration من SQL Editor في لوحة Supabase بواسطة مالك المشروع، مع مراعاة ترتيب migrations السابقة.

## التحقق بعد التطبيق

1. تحقق من سجل migration في Supabase أن النسخة `017_mobile_client_access` طُبّقت على المشروع الصحيح.
2. من SQL Editor، تحقق من وجود الدوال دون طباعة بيانات مستخدمين:

```sql
select
  to_regprocedure('public.mobile_my_profile()') is not null as profile_rpc_ready,
  to_regprocedure('public.mobile_record_task_update(uuid,public.task_status,text)') is not null as task_update_rpc_ready,
  to_regprocedure('public.mobile_review_task(uuid,public.task_status,text)') is not null as review_rpc_ready,
  to_regprocedure('public.mobile_submit_task_report(uuid,jsonb)') is not null as report_rpc_ready;
```

3. سجّل الدخول من APK بحساب موظف نشط مربوط بـ`auth.users`، وتأكد من ظهور الملف والمهام المسموح بها.
4. اختبر بدء مهمة وإرسال تقرير ومراجعة بمستخدمين ذوي الصلاحيات المناسبة. يجب أن تُرفض العملية عند غياب الصلاحية أو عند محاولة مراجعة المستخدم لمهمته بنفسه.

إذا بقيت رسالة تحديث قاعدة البيانات بعد التطبيق، تحقق أولًا من project ref ثم من سجل migrations. لا تُعد تشغيل SQL يدويًا على قاعدة الإنتاج قبل التأكد من حالة migration؛ الملف يستخدم بعض `create or replace` و`drop policy if exists` لكنه ليس بديلًا عن سجل نشر منضبط.

## ملفات العميل

- `../apps/mobile/lib/mobileData.ts`: قراءات Supabase المباشرة ونداءات RPC ورسائل الأخطاء.
- `../apps/mobile/lib/supabase.ts`: عميل Supabase مع حفظ جلسة Android في AsyncStorage.
- `../apps/mobile/app/index.tsx`: تدفق Auth ثم استرجاع ملف الموظف.
- `../apps/mobile/app/tasks.tsx`: المهام والتنبيهات والتقارير والمراجعات.
