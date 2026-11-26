BEGIN;

-- Repair only snapshots that were generated for customer-collection tasks by
-- the old broad accounting keyword rule. Existing submitted report values are
-- retained in task_reports; only the task form schema is corrected.
UPDATE public.task_report_form_snapshots AS s
SET schema = jsonb_build_array(
  jsonb_build_object('key','actual_result','label','النتيجة الفعلية','type','textarea','required',true),
  jsonb_build_object('key','execution_status','label','حالة التنفيذ','type','select','required',true,
    'options',jsonb_build_array('مكتملة','مكتملة جزئيًا','تعذر التنفيذ')),
  jsonb_build_object('key','customer_name','label','اسم العميل','type','text','required',true),
  jsonb_build_object('key','customer_phone','label','رقم العميل','type','text','required',false),
  jsonb_build_object('key','outstanding_amount','label','قيمة المستحقات','type','money','required',false),
  jsonb_build_object('key','collected_amount','label','المبلغ المحصل','type','money','required',false),
  jsonb_build_object('key','collection_status','label','حالة التحصيل','type','select','required',true,
    'options',jsonb_build_array('تم التحصيل','تحصيل جزئي','لم يتم التحصيل','وعد بالسداد','تعذر التواصل')),
  jsonb_build_object('key','contact_result','label','نتيجة المتابعة','type','textarea','required',true),
  jsonb_build_object('key','next_action','label','الإجراء التالي','type','textarea','required',false),
  jsonb_build_object('key','next_follow_up','label','موعد المتابعة القادمة','type','date','required',false),
  jsonb_build_object('key','collection_evidence','label','مرفق التحصيل أو إثبات التواصل','type','attachment','required',false),
  jsonb_build_object('key','execution_date','label','تاريخ التنفيذ','type','date','required',true),
  jsonb_build_object('key','notes','label','ملاحظات الموظف','type','textarea','required',false)
)
FROM public.tasks AS t
WHERE s.task_id = t.id
  AND t.deleted_at IS NULL
  AND (t.title ILIKE '%تحصيل%' OR t.title ILIKE '%المستحق%')
  AND (t.title ILIKE '%عميل%' OR t.title ILIKE '%عملاء%')
  AND s.schema @> '[{"key":"financial_amount"}]'::jsonb
  AND NOT s.schema @> '[{"key":"customer_name"}]'::jsonb;

COMMIT;
