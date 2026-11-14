begin;

-- تصنيف المهمة مستقل عن employee_roles (صلاحيات الحساب) وعن أسماء الموظفين.
-- الرموز التالية ثابتة، أما الاسم الظاهر في الواجهة فيطابق ترتيب المستخدم.
insert into public.job_titles (institution_id, code, name_ar, description, is_active)
select i.id, positions.code, positions.name_ar, 'تصنيف ثابت لمكتبة المهام والتقارير', true
from public.institutions i
cross join (values
  ('owner', 'صاحب المؤسسة'),
  ('admin_followup', 'المدير التنفيذي'),
  ('accountant', 'المحاسب'),
  ('warehouse_keeper', 'أمين المخازن'),
  ('warehouse_worker', 'عمال التحميل')
) as positions(code, name_ar)
on conflict (institution_id, code) do update
set name_ar = excluded.name_ar,
    description = excluded.description,
    is_active = true,
    updated_at = now();

alter table public.task_library_templates
  add column if not exists position_code text;
alter table public.tasks
  add column if not exists position_code text;
alter table public.recurring_task_templates
  add column if not exists position_code text;

-- انقل فقط القوالب التي يطابق رمز وظيفتها أحد الرموز الرسمية؛ لا نستنتج من اسم شخص أو عنوان حر.
update public.task_library_templates template
set position_code = title.code
from public.job_titles title
where template.institution_id = title.institution_id
  and template.job_title_id = title.id
  and template.position_code is null
  and title.code in ('owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker');

-- احتفظ بتصنيف لقطة القالب على المهام المنفذة سابقًا عند توفره.
update public.tasks task
set position_code = template.position_code
from public.task_library_templates template
where task.institution_id = template.institution_id
  and task.library_template_id = template.id
  and task.position_code is null
  and template.position_code is not null;

-- حدّث المهام المتكررة التي لها تصنيف صريح فقط؛ لا تستنتج تصنيفًا من اسم الموظف.
update public.tasks task
set position_code = template.position_code
from public.recurring_task_templates template
where task.institution_id = template.institution_id
  and task.recurring_template_id = template.id
  and task.position_code is null
  and template.position_code is not null;

-- القيم القديمة غير المعروفة تبقى NULL حتى يعيد المسؤول تصنيفها صراحةً؛ لا تُحذف سجلات.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'task_library_position_code_check' and conrelid = 'public.task_library_templates'::regclass) then
    alter table public.task_library_templates
      add constraint task_library_position_code_check
      check (position_code is null or position_code in ('owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tasks_position_code_check' and conrelid = 'public.tasks'::regclass) then
    alter table public.tasks
      add constraint tasks_position_code_check
      check (position_code is null or position_code in ('owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'recurring_task_position_code_check' and conrelid = 'public.recurring_task_templates'::regclass) then
    alter table public.recurring_task_templates
      add constraint recurring_task_position_code_check
      check (position_code is null or position_code in ('owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'));
  end if;
end $$;

create index if not exists task_library_position_filter_idx
  on public.task_library_templates (institution_id, position_code, is_active, title);
create index if not exists tasks_position_report_idx
  on public.tasks (institution_id, position_code, due_at desc);

-- تُمرّر فئة قالب التكرار إلى كل مهمة مولّدة، مع ترك القوالب التاريخية غير المصنفة كما هي.
create or replace function app.generate_recurring_tasks(p_from_date date, p_to_date date)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare
  template record;
  occurrence date;
  run_id uuid;
  institution_timezone text;
  generated_count integer := 0;
  is_due boolean;
begin
  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or p_to_date > p_from_date + 31 then
    raise exception 'invalid_recurrence_window';
  end if;
  for template in
    select t.*, i.timezone
    from public.recurring_task_templates t
    join public.institutions i on i.id = t.institution_id
    where t.is_active and t.starts_on <= p_to_date and (t.ends_on is null or t.ends_on >= p_from_date)
  loop
    institution_timezone := coalesce(template.timezone, 'UTC');
    for occurrence in
      select generate_series(greatest(p_from_date, template.starts_on), least(p_to_date, coalesce(template.ends_on, p_to_date)), interval '1 day')::date
    loop
      is_due := case
        when template.recurrence = 'daily' then true
        when template.recurrence = 'weekly' then ((((extract(dow from occurrence)::integer + 1) % 7) + 1) = template.week_day)
        when template.recurrence = 'monthly' then extract(day from occurrence)::integer = template.month_day
        else false
      end;
      if not is_due then continue; end if;
      run_id := null;
      insert into public.task_runs (institution_id, template_id, scheduled_for, status)
      values (template.institution_id, template.id, occurrence, 'started')
      on conflict (institution_id, template_id, scheduled_for) do nothing
      returning id into run_id;
      if run_id is null then continue; end if;
      begin
        insert into public.tasks (
          institution_id, branch_id, created_by, assignee_employee_id, title, description,
          starts_at, due_at, priority, proof_required, recurring_template_id, idempotency_key, position_code
        )
        values (
          template.institution_id, template.branch_id, template.created_by, template.assignee_employee_id,
          template.title, template.description,
          occurrence::timestamp at time zone institution_timezone,
          ((occurrence + 1)::timestamp at time zone institution_timezone) - interval '1 second',
          'normal', false, template.id, 'recurring:' || template.id::text || ':' || occurrence::text,
          template.position_code
        )
        on conflict (institution_id, idempotency_key) do nothing;
        update public.task_runs set status = 'completed', completed_at = now() where id = run_id;
        generated_count := generated_count + 1;
      exception when others then
        update public.task_runs set status = 'failed', error_message = sqlerrm, completed_at = now() where id = run_id;
      end;
    end loop;
    update public.recurring_task_templates
    set last_generated_for = greatest(coalesce(last_generated_for, p_from_date - 1), p_to_date)
    where id = template.id;
  end loop;
  return generated_count;
end;
$$;

revoke all on function app.generate_recurring_tasks(date, date) from public, anon, authenticated;
grant execute on function app.generate_recurring_tasks(date, date) to service_role;

commit;
