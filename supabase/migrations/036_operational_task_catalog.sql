begin;

-- Additive operational starter catalog for Alshaeri's real work domains.
-- No report forms are linked here: managers compose and approve the report
-- schema per assignment using the existing dynamic report designer.

insert into public.task_categories (organization_id, code, title, parent_id, is_main)
select o.id, c.code, c.title, null, false
from public.organizations o
cross join (values
  ('finance_accounts','الحسابات'),
  ('finance_sales','حسابات المبيعات والتحصيل'),
  ('finance_returns','المرتجعات والفروقات'),
  ('finance_receivables','المديونيات والعملاء'),
  ('finance_purchases','حسابات المشتريات'),
  ('sales_pricing','المبيعات والتسعير'),
  ('sales_wholesale','مبيعات الجملة'),
  ('sales_delivery','التسليم والعملاء'),
  ('purchases_suppliers','المشتريات والموردون'),
  ('warehouse_receiving','الاستلام'),
  ('warehouse_issuing','الصرف والتجهيز'),
  ('warehouse_count','الجرد والفروقات'),
  ('warehouse_movement','حركة المخزون'),
  ('warehouse_loading','التحميل والنقل'),
  ('admin_followup','المتابعة الإدارية'),
  ('admin_reports','التقارير المجمعة'),
  ('admin_approvals','المراجعة والاعتماد'),
  ('admin_support','الترتيب والنظافة والمساندة')
) c(code,title)
join public.task_categories parent on parent.organization_id=o.id and parent.is_main=true and parent.code=case
  when c.code like 'finance_%' then 'finance'
  when c.code like 'sales_%' then 'sales'
  when c.code like 'purchases_%' then 'purchases'
  when c.code like 'warehouse_%' then 'warehouse'
  when c.code like 'admin_%' then 'admin'
end
where not exists (
  select 1 from public.task_categories existing
  where existing.organization_id=o.id and existing.code=c.code
);

with catalog(role_code, category_code, subcategory_code, code, title, description, expected_result, instructions, priority, duration_minutes) as (
  values
  ('accountant','finance','finance_accounts','acct_daily_close','إقفال الحسابات اليومية','مراجعة حركة النقد والمبيعات والمصروفات وإقفال يوم العمل.','رصيد يومي موثق والفروقات محددة قبل الإقفال.','طابق المستندات مع الحركة الفعلية، وسجل أي فرق مع سببه والمرفقات اللازمة.','important',120),
  ('accountant','sales','sales_pricing','acct_sales_collection','مراجعة المبيعات والتحصيل','مراجعة فواتير المبيعات والتحصيلات والذمم الناتجة عنها.','تقرير مبيعات وتحصيل متطابق مع الفواتير والسندات.','تحقق من أرقام الفواتير والعملاء والمبالغ المسددة والمتبقية قبل الإرسال.','important',180),
  ('accountant','finance','finance_returns','acct_returns_reconciliation','تسوية المرتجعات والفروقات','مطابقة المرتجعات مع الفواتير وإثبات أثرها على الحسابات والمخزون.','كشف مرتجعات معتمد والفروقات مفسرة.','اربط كل مرتجع بالفاتورة أو المستند الأصلي، وبيّن أثره المالي والكمّي.','urgent',120),
  ('accountant','finance','finance_receivables','acct_debts_followup','متابعة المديونيات والعملاء','تحديث أرصدة العملاء ومتابعة التحصيل والاستحقاقات المتأخرة.','قائمة مديونيات محدثة وخطة متابعة واضحة.','صنف العملاء حسب الاستحقاق، وسجل آخر تواصل والموعد التالي للتحصيل.','important',180),
  ('accountant','purchases','finance_purchases','acct_purchase_review','مراجعة حسابات المشتريات','مطابقة فواتير المشتريات مع الاستلام والموردين والمدفوعات.','مشتريات مسجلة بلا فواتير مكررة أو فروقات غير مبررة.','قارن الكميات والأسعار والمورد وشروط السداد مع مستند الاستلام.','important',150),
  ('warehouse_keeper','warehouse','warehouse_receiving','wh_receive_goods','استلام الأصناف من الموردين','فحص الأصناف والكميات عند الاستلام وتسجيل الفروقات والمستندات.','محضر استلام مطابق أو فروقات موثقة بالصور.','تحقق من الصنف والكمية والحالة ورقم المستند قبل إدخال الحركة.','important',120),
  ('warehouse_keeper','warehouse','warehouse_issuing','wh_issue_goods','صرف وتجهيز الأصناف','تنفيذ طلبات الصرف وتجهيز الأصناف وتسليمها حسب المستند.','حركة صرف موثقة والكميات المسلمة مطابقة للطلب.','راجع الطلب، جهز الأصناف، وأثبت الكمية الفعلية وأي نقص أو بديل.','important',120),
  ('warehouse_keeper','warehouse','warehouse_count','wh_cycle_count','جرد المخزون الدوري','عد الأصناف ومطابقة الرصيد الدفتري مع الكمية الفعلية.','كشف جرد يوضح العجز والزيادة لكل صنف.','استخدم جدول أصناف متكرر، واحسب العجز = الرصيد الدفتري - الكمية الفعلية، وأظهر الزيادة والعجز بإشارة صحيحة.','urgent',240),
  ('warehouse_keeper','warehouse','warehouse_movement','wh_stock_movement_review','مراجعة حركة المخزون','مراجعة حركات الاستلام والصرف والتحويل والمرتجعات خلال الفترة.','حركة مخزون مكتملة ومطابقة للمستندات.','تحقق من مصدر كل حركة ووجهتها والمستخدم الذي سجلها وأي فرق ظاهر.','important',180),
  ('warehouse_worker','warehouse','warehouse_loading','load_order_preparation','تجهيز الطلبات للتحميل','جمع الأصناف وترتيبها حسب طلب التسليم وتجهيزها للنقل.','طلب جاهز للتحميل ومطابق للكميات.','اقرأ الطلب بندًا بندًا، افصل الطلبات، وصور أي تلف أو نقص قبل التحميل.','important',120),
  ('warehouse_worker','warehouse','warehouse_loading','load_delivery_handover','التحميل والتسليم','تحميل الطلب وتسليمه للجهة المحددة مع توثيق الاستلام.','إثبات تحميل وتسليم مرتبط بالطلب.','طابق عدد الطرود، سجل وقت المغادرة والوصول، وأرفق صورة أو مستند التسليم عند الحاجة.','urgent',180),
  ('admin_followup','admin','admin_followup','admin_daily_branch_followup','متابعة أداء الفرع اليومية','جمع حالة المبيعات والمخزون والمهام المفتوحة والعوائق من الفرع.','ملخص يومي واضح مع إجراءات متابعة ومسؤولين.','راجع المهام والتقارير الواردة، صنف المتأخر، وحدد الإجراء والموعد التالي.','important',120),
  ('admin_followup','admin','admin_reports','admin_weekly_consolidated_report','التقرير التشغيلي الأسبوعي المجمع','تجميع مؤشرات الحسابات والمبيعات والمخزون والمشتريات والتسليم.','تقرير أسبوعي قابل للمراجعة والاعتماد.','اعتمد على التقارير المرتبطة بالتكليفات فقط، ووضح مصادر الأرقام والفروقات.','important',240),
  ('admin_followup','purchases','purchases_suppliers','admin_supplier_followup','متابعة الموردين والمشتريات','متابعة الطلبات المفتوحة ومواعيد التوريد ومشكلات الموردين.','قائمة مورّدين محدثة وإجراءات معلقة محددة.','سجل المورد والطلب وتاريخ الاستحقاق وأي تأخير أو فرق في السعر والكمية.','important',120),
  ('owner','admin','admin_approvals','owner_final_review','المراجعة والاعتماد النهائي','مراجعة التقارير الحساسة والفروقات والقرارات التي تحتاج اعتماد صاحب المؤسسة.','قرارات معتمدة أو ملاحظات إعادة واضحة.','راجع الأرقام والمرفقات والتعليقات، ولا تعتمد تقريرًا ناقصًا أو غير قابل للتتبع.','critical',120),
  ('owner','admin','admin_reports','owner_monthly_business_review','المراجعة الشهرية لأداء المؤسسة','مراجعة مجمعة للمبيعات والحسابات والمخزون والمشتريات والفروع.','قرارات شهرية موثقة وأولويات للفترة التالية.','قارن النتائج بالفترة السابقة، حدد أسباب الانحراف، ثم سجل القرارات والمسؤوليات.','critical',240)
)
insert into public.task_templates (
  organization_id, code, title, description, expected_result, job_title, task_type,
  default_priority, is_active, role_code, instructions, category_id, subcategory_id,
  default_duration_minutes, version
)
select
  o.id, c.code, c.title, c.description, c.expected_result,
  case c.role_code
    when 'accountant' then 'المحاسب'
    when 'warehouse_keeper' then 'أمين المخازن'
    when 'warehouse_worker' then 'عمال التحميل'
    when 'admin_followup' then 'المدير التنفيذي'
    when 'owner' then 'صاحب المؤسسة'
  end,
  case when c.category_code in ('finance','sales','purchases') then 'financial' else 'operational' end,
  c.priority, true, c.role_code, c.instructions, main.id, sub.id, c.duration_minutes, 1
from public.organizations o
cross join catalog c
join public.task_categories main on main.organization_id=o.id and main.is_main=true and main.code=c.category_code
join public.task_categories sub on sub.organization_id=o.id and sub.parent_id=main.id and sub.code=c.subcategory_code
where not exists (
  select 1 from public.task_templates existing
  where existing.organization_id=o.id and existing.code=c.code
);

with step_catalog(code, sort_order, title, instructions, is_required, evidence_required) as (
  values
  ('acct_daily_close',0,'جمع المستندات','اجمع الفواتير والسندات والمصروفات وحركة النقد.',true,false),
  ('acct_daily_close',1,'المطابقة','طابق الأرقام مع النظام والمستندات الأصلية.',true,false),
  ('acct_daily_close',2,'تسجيل الفرق','سجل الفرق وسببه والمرفقات إن وجد.',true,true),
  ('acct_sales_collection',0,'مطابقة الفواتير','راجع الفواتير والعملاء والمبالغ.',true,false),
  ('acct_sales_collection',1,'مطابقة التحصيل','طابق سندات التحصيل مع الأرصدة.',true,false),
  ('acct_sales_collection',2,'تحديد المتبقي','سجل المديونية والإجراء التالي.',true,false),
  ('acct_returns_reconciliation',0,'حصر المرتجعات','اجمع مستندات المرتجعات خلال الفترة.',true,false),
  ('acct_returns_reconciliation',1,'مطابقة السبب والأثر','تحقق من الكمية والقيمة وأثرها على الحسابات والمخزون.',true,false),
  ('acct_returns_reconciliation',2,'توثيق الفرق','أرفق صور أو مستندات الفروقات.',true,true),
  ('acct_debts_followup',0,'تحديث الأرصدة','استخرج رصيد كل عميل وحالة الاستحقاق.',true,false),
  ('acct_debts_followup',1,'تسجيل المتابعة','سجل آخر تواصل والموعد التالي.',true,false),
  ('acct_purchase_review',0,'مطابقة الاستلام','قارن الفاتورة بمحضر الاستلام.',true,false),
  ('acct_purchase_review',1,'مراجعة المورد','تحقق من السعر وشروط السداد.',true,false),
  ('wh_receive_goods',0,'فحص المستند','تحقق من المورد ورقم المستند.',true,false),
  ('wh_receive_goods',1,'عد الأصناف','عد الكمية وافحص الحالة.',true,false),
  ('wh_receive_goods',2,'توثيق الفروقات','سجل النقص أو التلف وارفق الإثبات.',true,true),
  ('wh_issue_goods',0,'مراجعة الطلب','تحقق من الجهة والأصناف المطلوبة.',true,false),
  ('wh_issue_goods',1,'التجهيز والعد','جهز الأصناف وسجل الكمية الفعلية.',true,false),
  ('wh_cycle_count',0,'تثبيت الرصيد الدفتري','انقل الرصيد الدفتري لكل صنف.',true,false),
  ('wh_cycle_count',1,'العد الفعلي','سجل الكمية الفعلية في الموقع.',true,false),
  ('wh_cycle_count',2,'حساب الفرق','استخدم العجز = الدفتري - الفعلي، ثم راجع إشارة الزيادة والعجز.',true,false),
  ('wh_cycle_count',3,'إرفاق الإثبات','أرفق صور الجرد والملاحظات.',true,true),
  ('wh_stock_movement_review',0,'حصر الحركات','اجمع الاستلام والصرف والتحويل والمرتجع.',true,false),
  ('wh_stock_movement_review',1,'مطابقة المستندات','طابق كل حركة بمستندها.',true,false),
  ('load_order_preparation',0,'قراءة الطلب','راجع الأصناف والكميات والوجهة.',true,false),
  ('load_order_preparation',1,'التجهيز','افصل الطلب ورتب الطرود.',true,false),
  ('load_delivery_handover',0,'مطابقة التحميل','طابق الطرود مع طلب التسليم.',true,false),
  ('load_delivery_handover',1,'التسليم','سجل المستلم ووقت التسليم.',true,true),
  ('admin_daily_branch_followup',0,'مراجعة المؤشرات','راجع المهام والتقارير والحالات المتأخرة.',true,false),
  ('admin_daily_branch_followup',1,'تحديد الإجراءات','حدد المسؤول والموعد لكل عائق.',true,false),
  ('admin_weekly_consolidated_report',0,'جمع التقارير','اجمع التقارير المعتمدة للفترة.',true,false),
  ('admin_weekly_consolidated_report',1,'تحليل الفروقات','وضح الانحرافات وأسبابها.',true,false),
  ('admin_weekly_consolidated_report',2,'رفع التقرير','أرسل التقرير للمراجعة والاعتماد.',true,false),
  ('admin_supplier_followup',0,'حصر الطلبات','اجمع أوامر الشراء المفتوحة.',true,false),
  ('admin_supplier_followup',1,'متابعة الموردين','سجل حالة التوريد والموعد القادم.',true,false),
  ('owner_final_review',0,'مراجعة البيانات','تحقق من الأرقام والمرفقات والتعليقات.',true,false),
  ('owner_final_review',1,'قرار الاعتماد','اعتمد أو أعد التقرير مع ملاحظة واضحة.',true,false),
  ('owner_monthly_business_review',0,'تجميع المؤشرات','اجمع نتائج الشهر من التقارير المعتمدة.',true,false),
  ('owner_monthly_business_review',1,'تحديد القرارات','سجل الأولويات والمسؤوليات للشهر التالي.',true,false)
)
insert into public.task_template_steps (template_id, title, instructions, sort_order, is_required, evidence_required)
select t.id, s.title, s.instructions, s.sort_order, s.is_required, s.evidence_required
from public.task_templates t
join step_catalog s on s.code=t.code
where not exists (
  select 1 from public.task_template_steps existing
  where existing.template_id=t.id and existing.sort_order=s.sort_order
);

commit;
