begin;
insert into public.task_templates (organization_id, code, title, description, expected_result, job_title, task_type, default_priority, is_active, role_code, instructions, category_id, subcategory_id, default_duration_minutes, version)
select o.id,'acct_purchase_review','مراجعة حسابات المشتريات','مطابقة فواتير المشتريات مع الاستلام والموردين والمدفوعات.','مشتريات مسجلة بلا فواتير مكررة أو فروقات غير مبررة.','المحاسب','financial','important',true,'accountant','قارن الكميات والأسعار والمورد وشروط السداد مع مستند الاستلام.',main.id,sub.id,150,1
from public.organizations o
join public.task_categories main on main.organization_id=o.id and main.is_main=true and main.code='finance'
join public.task_categories sub on sub.organization_id=o.id and sub.parent_id=main.id and sub.code='finance_purchases'
where not exists (select 1 from public.task_templates t where t.organization_id=o.id and t.code='acct_purchase_review');
insert into public.task_template_steps (template_id,title,instructions,sort_order,is_required,evidence_required)
select t.id,s.title,s.instructions,s.sort_order,true,false
from public.task_templates t
cross join (values (0,'مطابقة الاستلام','قارن الفاتورة بمحضر الاستلام.'),(1,'مراجعة المورد','تحقق من السعر وشروط السداد.')) s(sort_order,title,instructions)
where t.code='acct_purchase_review'
  and not exists (select 1 from public.task_template_steps x where x.template_id=t.id and x.sort_order=s.sort_order);
commit;
