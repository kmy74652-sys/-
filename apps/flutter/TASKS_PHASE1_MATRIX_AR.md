# مصفوفة تحقق المرحلة الأولى: إدارة المهام

آخر تحديث: 2026-11-22

هذه المصفوفة خاصة بالمرحلة الأولى فقط. «منفذ» تعني أن واجهة Flutter تستدعي عقدًا موجودًا في Backend. ولا تعني أن البناء أو الاختبار على جهاز Android تم؛ أدوات Flutter وDart وAndroid SDK غير متاحة في بيئة العمل الحالية.

| الإجراء | مصدر Expo | عقد Supabase الفعلي | Flutter الحالي | الحالة | النقص أو القيد |
|---|---|---|---|---|---|
| عرض المهام والبحث والمرشحات | `apps/mobile/app/tasks.tsx` و`mobileData.ts` | قراءة `tasks` مع `deleted_at is null` | `tasks_screen.dart` | منفذ جزئيًا | يحتاج اختبار RLS وبيانات حقيقية.
| فتح تفاصيل المهمة | `TaskDetail` و`listMyTasks` | قراءات `tasks`, `task_execution_steps`, التقارير | `task_detail_screen.dart` | منفذ جزئيًا | لم يُبنَ APK ولم تُجرَ تجربة جهاز.
| بدء التنفيذ وتغيير الحالة | `updateTaskStatus` | `mobile_record_task_update` | `_status` والطابور | منفذ | عقد الحالة لا يستقبل idempotency key؛ منع تكرار الحالة يعتمد على الطابور والخادم.
| إرسال التقرير legacy | `submitTaskReport` | `mobile_submit_task_report` | `_submitReport` | منفذ | يحتاج اختبار تكرار الإرسال فعليًا على Supabase.
| إرسال التقرير متعدد النماذج | `submitTaskReport` | `mobile_submit_task_report_form` | `_submitSnapshot` | منفذ | يحتاج اختبار حالات الإعادة والاعتماد.
| حفظ مسودة النموذج | `saveTaskReportDraft` | `save_task_report_draft` | `_saveSnapshotDraft` | منفذ | لا توجد مزامنة مسودة دون اتصال.
| رفع إثبات خطوة | `taskAttachments.ts` | Storage `task-attachments` ثم `task_attachments` | `_uploadEvidence` | منفذ جزئيًا | لا يوجد رفع دون اتصال؛ صلاحيات Storage تحتاج اختبار جهاز.
| إكمال خطوة بإثبات | `completeTaskExecutionStep` | `mobile_complete_task_step` | `_completeStep` | منفذ | أضيف تحقق Flutter يمنع الإكمال المحلي دون إثبات، والتحقق النهائي يظل في RPC.
| إنشاء مهمة مباشرة | `createAdministrativeTask` | `create_task_with_report_form` | `task_management_screen.dart` | منفذ | العقد المباشر لا يملك idempotency key؛ لا يجوز اختراع معامل غير موجود.
| إنشاء مهمة من قالب | `createAdministrativeTask` | `assign_task_from_template` | `task_management_screen.dart` | منفذ جزئيًا | تمت إضافة اختيار القالب ومفتاح idempotency حتمي؛ يلزم اختبار توافق الموظف/الدور والفرع على بيانات حقيقية.
| تعديل عنوان ووصف وموعد | إجراءات الإدارة في Expo | `admin_update_task` | `task_management_screen.dart` | منفذ | العقد المتاح لا يغير المكلّف أو الأولوية أو الفرع.
| الحذف/الأرشفة الآمنة | `admin_delete_task` | `admin_delete_task` بعد migration 062 | `task_management_screen.dart` | منفذ | الاسم في الواجهة يوضح أنه حذف آمن/أرشفة؛ لا يتم حذف سجل النشاط.
| إعادة التعيين | تدفقات الإدارة المرجعية | لا يوجد RPC منشور باسم إعادة تعيين | لا يوجد استدعاء مصطنع | غير منفذ، موثق | يلزم عقد Backend صريح؛ ممنوع تعديل Backend في هذه المرحلة.
| الإلغاء | حالات `cancelled` في المصدر | لا يوجد عقد إدارة إلغاء مستقل | لا يوجد استدعاء مباشر | غير منفذ، موثق | لا يجوز تحديث `tasks` مباشرة من Flutter بسبب RLS وسلامة دورة الحالة.
| الأرشفة كإجراء مستقل | إدارة المهام | لا يوجد عقد منفصل؛ الحذف الآمن يضبط `deleted_at` | ممثل بالحذف الآمن | جزئي | يلزم تحديد دلالة الأرشفة المطلوبة إن كانت مختلفة عن `deleted_at`.
| طلب نشر قالب | `taskPublication.ts` | `submit_task_publication_request` | `task_management_screen.dart` | منفذ | مفتاح idempotency حتمي بحسب القالب/الفرع/الموعد.
| عرض طلبات النشر | `listPendingTaskPublicationRequests` | قراءة `task_publication_requests` | `task_management_screen.dart` | منفذ | العرض مقيد بالطلبات المعلقة.
| اعتماد/رفض النشر | `reviewTaskPublicationRequest` | `review_and_publish_task_request` | `task_management_screen.dart` | منفذ جزئيًا | العقد يشترط مالك المؤسسة؛ الواجهة تعرض النتيجة وتترك RLS/RPC للحسم.
| منع تكرار طلب النشر | `submitTaskPublicationRequest` | unique `(organization_id, request_key)` | مفتاح ثابت في الشاشة | منفذ | يحتاج اختبار عملي على قاعدة غير إنتاجية.
| منع تكرار التقارير | `mobileData.ts` | unique `(submitted_by,idempotency_key)` | مفاتيح إرسال + `OfflineQueue` | منفذ جزئيًا | لا يمكن إثباته دون تشغيل Flutter/اتصال Supabase.
| تعارضات العمل دون اتصال | `offlineQueue.ts` | لا يوجد عقد تعارض مستقل | `offline_queue.dart` | محسن محليًا / غير مكتمل خادميًا | يتم إسقاط حالة أقدم لنفس المهمة محليًا، وتحجب أخطاء الصلاحيات/البيانات بدل تكرارها تلقائيًا، مع عداد وإعادة محاولة يدوية؛ لا توجد سياسة خادم لحالة قديمة.
| مزامنة حالة قديمة | `offlineQueue.ts` | RPC الحالة لا يحدد version/updated_at | `OfflineQueue.flush` | غير مكتمل | يلزم عقد optimistic concurrency أو سياسة خادم واضحة.
| اختبارات الطابور | اختبارات محدودة في Expo | لا ينطبق | `test/core/offline_queue_test.dart` | جزئي | توجد اختبارات serialization فقط؛ لم تُشغّل لغياب Flutter.

## ما تم تنفيذه في هذه الجولة

- إضافة `task_management_screen.dart` باللغة العربية.
- ربط الشاشة بالمسار `/admin/tasks` وإظهارها من لوحة الإدارة لمن يملك `tasks.manage`.
- تنفيذ الإنشاء المباشر عبر `create_task_with_report_form`.
- تنفيذ تعديل العنوان والوصف وموعد الاستحقاق عبر `admin_update_task`.
- تنفيذ الحذف الآمن عبر `admin_delete_task`.
- تنفيذ طلب النشر وعرضه واعتماده أو رفضه عبر العقود الموجودة.
- منع إكمال خطوة تتطلب إثباتًا في واجهة Flutter قبل وجود مرفق، مع إبقاء تحقق RPC هو المرجع النهائي.
- توسيع أزرار الحالة لتتعامل مع التسميات الفعلية `new/received/on_hold`.
- تحسين الطابور محليًا: إسقاط حالة أقدم لنفس المهمة، حجب الأخطاء غير الشبكية، وإضافة إعادة محاولة يدوية واختبار serialization للعناصر المحجوبة.

## قرارات السلامة

لم يتم إنشاء migration أو تعديل Backend أو حذف بيانات أو إنشاء commit أو push. لم يتم اعتبار المرحلة الأولى مكتملة؛ ما زالت إعادة التعيين والإلغاء المستقل والتعارضات واختبارات التشغيل الفعلية حواجز مفتوحة، كما أن الترجمة والبناء غير متحققين بسبب غياب أدوات Flutter في البيئة الحالية.
