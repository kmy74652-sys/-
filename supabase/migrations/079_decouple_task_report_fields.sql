begin;

-- Task-designer report fields are embedded in the task template. They are not
-- report-designer forms and must not create rows in report_form_templates.
create table if not exists public.task_template_report_fields (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.task_templates(id) on delete cascade,
  field_key text,
  label text not null,
  field_type text not null,
  is_required boolean not null default false,
  options jsonb not null default '[]'::jsonb,
  sort_order integer not null default 0,
  description text,
  repeatable boolean not null default false,
  validation jsonb not null default '{}'::jsonb,
  config jsonb not null default '{}'::jsonb
);
alter table public.task_template_report_fields add column if not exists description text;
alter table public.task_template_report_fields add column if not exists repeatable boolean not null default false;
alter table public.task_template_report_fields add column if not exists validation jsonb not null default '{}'::jsonb;
alter table public.task_template_report_fields add column if not exists config jsonb not null default '{}'::jsonb;
create index if not exists task_template_report_fields_template_order_idx on public.task_template_report_fields(template_id, sort_order);
alter table public.task_template_report_fields drop constraint if exists task_template_report_fields_field_type_check;

-- Migrate existing organizational task fields out of generated report-designer
-- forms before the RPCs below stop using those forms.
insert into public.task_template_report_fields(template_id, field_key, label, field_type, is_required, options, sort_order, description, repeatable, validation, config)
select distinct on (tt.id, f.field_key)
  tt.id, f.field_key, f.label,
  case f.field_type
    when 'short_text' then 'text'
    when 'integer' then 'number'
    when 'quantity' then 'number'
    when 'money' then 'number'
    when 'decimal' then 'number'
    when 'percentage' then 'number'
    when 'datetime' then 'date'
    when 'date_range' then 'date'
    when 'multiselect' then 'multi_select'
    when 'image' then 'attachment'
    when 'multi_image' then 'attachment'
    when 'file' then 'attachment'
    when 'boolean' then 'select'
    else f.field_type
  end,
  f.is_required, f.options, f.sort_order,
  f.description, f.repeatable, f.validation, f.config
from public.task_templates tt
join public.task_template_report_forms l on l.template_id=tt.id
join public.report_form_version_fields f on f.version_id=l.version_id
where tt.task_type='administrative'
  and not exists (select 1 from public.task_template_report_fields existing where existing.template_id=tt.id)
order by tt.id, f.field_key, f.sort_order;

delete from public.task_template_report_forms l
using public.task_templates tt
where l.template_id=tt.id and tt.task_type='administrative';

create or replace function public.save_task_designer_template(p_organization_id uuid,p_template_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare
  v_id uuid:=coalesce(p_template_id,gen_random_uuid());
  v_role text; v_step jsonb; v_field jsonb;
  v_key text; v_label text; v_type text;
begin
  if auth.uid() is null or not alshaari_private.has_permission(p_organization_id,'task_library.manage',null::uuid) then raise exception using errcode='42501',message='permission_denied'; end if;
  if jsonb_typeof(p_payload)<>'object' or jsonb_typeof(coalesce(p_payload->'steps','[]'))<>'array' or jsonb_typeof(coalesce(p_payload->'report_fields','[]'))<>'array' then raise exception using errcode='22023',message='invalid_template_payload'; end if;
  v_role:=p_payload->>'role_code';
  if not exists(select 1 from public.roles where code=v_role) then raise exception using errcode='22023',message='invalid_task_role'; end if;
  if p_payload->>'category_id' is not null and not exists(select 1 from public.task_categories c where c.id=(p_payload->>'category_id')::uuid and c.organization_id=p_organization_id and c.parent_id is null) then raise exception using errcode='22023',message='invalid_task_category'; end if;
  if p_payload->>'subcategory_id' is not null and not exists(select 1 from public.task_categories c join public.task_categories p on p.id=c.parent_id where c.id=(p_payload->>'subcategory_id')::uuid and c.organization_id=p_organization_id and p.id=(p_payload->>'category_id')::uuid) then raise exception using errcode='22023',message='invalid_task_subcategory'; end if;
  insert into public.task_templates(id,organization_id,code,title,description,role_code,task_type,default_priority,category_id,subcategory_id,instructions,default_duration_minutes,is_active)
  values(v_id,p_organization_id,'td_'||substr(replace(v_id::text,'-',''),1,20),trim(p_payload->>'title'),nullif(p_payload->>'description',''),v_role,coalesce(nullif(p_payload->>'task_type',''), 'operational'),coalesce(nullif(p_payload->>'default_priority',''),'normal'),nullif(p_payload->>'category_id','')::uuid,nullif(p_payload->>'subcategory_id','')::uuid,p_payload->>'instructions',nullif(p_payload->>'default_duration_minutes','')::integer,coalesce((p_payload->>'is_active')::boolean,true))
  on conflict(id) do update set title=excluded.title,description=excluded.description,role_code=excluded.role_code,task_type=excluded.task_type,default_priority=excluded.default_priority,category_id=excluded.category_id,subcategory_id=excluded.subcategory_id,instructions=excluded.instructions,default_duration_minutes=excluded.default_duration_minutes,is_active=excluded.is_active,version=public.task_templates.version+1,updated_at=now()
  where public.task_templates.organization_id=p_organization_id;
  if not found then raise exception using errcode='22023',message='task_template_not_found'; end if;
  delete from public.task_template_steps where template_id=v_id;
  for v_step in select value from jsonb_array_elements(coalesce(p_payload->'steps','[]')) loop
    insert into public.task_template_steps(template_id,title,instructions,sort_order,is_required,evidence_required,evidence_instructions)
    values(v_id,trim(v_step->>'title'),v_step->>'instructions',coalesce((v_step->>'sort_order')::int,0),coalesce((v_step->>'is_required')::boolean,true),coalesce((v_step->>'evidence_required')::boolean,false),v_step->>'evidence_instructions');
  end loop;
  delete from public.task_template_report_fields where template_id=v_id;
  for v_field in select value from jsonb_array_elements(coalesce(p_payload->'report_fields','[]')) loop
    v_key:=lower(trim(v_field->>'field_key')); v_label:=trim(v_field->>'label'); v_type:=trim(v_field->>'field_type');
    if v_key !~ '^[a-z][a-z0-9_]{0,63}$' then raise exception using errcode='22023',message='invalid_task_report_field_key'; end if;
    if length(v_label) < 1 or length(v_label) > 200 then raise exception using errcode='22023',message='invalid_task_report_field_label'; end if;
    insert into public.task_template_report_fields(template_id,field_key,label,field_type,is_required,options,sort_order,description,repeatable,validation,config)
    values(v_id,v_key,v_label,v_type,coalesce((v_field->>'is_required')::boolean,false),coalesce(v_field->'options','[]'::jsonb),coalesce((v_field->>'sort_order')::int,0),nullif(v_field->>'description',''),coalesce((v_field->>'repeatable')::boolean,false),coalesce(v_field->'validation','{}'::jsonb),coalesce(v_field->'config','{}'::jsonb));
  end loop;
  return v_id;
end $$;

create or replace function public.assign_task_from_template(p_organization_id uuid,p_template_id uuid,p_assigned_to uuid,p_branch_id uuid,p_starts_at timestamptz,p_due_at timestamptz,p_priority text default null,p_instructions text default null,p_report_overrides jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare
  v_user uuid:=auth.uid(); v_t public.task_templates%rowtype; v_task uuid; v_snap uuid; v_schema jsonb;
begin
  if v_user is null or not alshaari_private.has_permission(p_organization_id,'tasks.manage',null::uuid) then raise exception using errcode='42501',message='permission_denied'; end if;
  select * into v_t from public.task_templates where id=p_template_id and organization_id=p_organization_id and is_active;
  if not found then raise exception using errcode='22023',message='task_template_not_found'; end if;
  if p_starts_at is null or p_due_at is null or p_due_at<p_starts_at then raise exception using errcode='22023',message='invalid_task_schedule'; end if;
  if p_priority is not null and p_priority not in ('normal','important','urgent','critical') then raise exception using errcode='22023',message='invalid_task_priority'; end if;
  if not exists(select 1 from public.organization_memberships m join public.role_assignments r on r.organization_id=m.organization_id and r.membership_id=m.id where m.organization_id=p_organization_id and m.user_id=p_assigned_to and m.is_active and r.role_code=v_t.role_code and (p_branch_id is null or r.branch_id=p_branch_id)) then raise exception using errcode='22023',message='no_employee_for_role_branch'; end if;
  if p_branch_id is not null and not exists(select 1 from public.branches where id=p_branch_id and organization_id=p_organization_id and is_active) then raise exception using errcode='22023',message='invalid_task_branch'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('key',f.field_key,'label',f.label,'type',f.field_type,'required',f.is_required,'repeatable',f.repeatable,'validation',f.validation,'options',f.options,'config',f.config) order by f.sort_order),'[]'::jsonb) into v_schema from public.task_template_report_fields f where f.template_id=v_t.id;
  insert into public.tasks(organization_id,branch_id,title,description,expected_result,assigned_to,created_by,due_at,starts_at,priority,template_id,position_code,report_flow,task_instructions,category_id,subcategory_id,proof_required,proof_instructions,template_version,report_required)
  values(p_organization_id,p_branch_id,v_t.title,v_t.description,v_t.expected_result,p_assigned_to,v_user,p_due_at,p_starts_at,coalesce(nullif(p_priority,''),v_t.default_priority)::task_priority,p_template_id,v_t.role_code,'multi_form',coalesce(nullif(trim(p_instructions),''),v_t.instructions),v_t.category_id,v_t.subcategory_id,false,null,v_t.version,jsonb_array_length(v_schema)>0) returning id into v_task;
  insert into public.task_execution_steps(task_id,source_template_step_id,title,instructions,sort_order,is_required,evidence_required,evidence_instructions)
  select v_task,s.id,s.title,s.instructions,s.sort_order,s.is_required,s.evidence_required,s.evidence_instructions from public.task_template_steps s where s.template_id=v_t.id order by s.sort_order;
  if jsonb_array_length(v_schema)>0 then
    insert into public.task_report_form_snapshots(task_id,template_id,version_id,report_required,schema,published_by,title,sort_order,is_required,organization_id,task_report_form_id)
    values(v_task,null,null,true,v_schema,v_user,v_t.title||' — تقرير المهمة',0,true,p_organization_id,null) returning id into v_snap;
  end if;
  insert into public.task_activity_log(task_id,actor_id,action,details) values(v_task,v_user,'task_assigned',jsonb_build_object('template_id',v_t.id,'template_version',v_t.version,'report_flow','multi_form','embedded_report_fields',jsonb_array_length(v_schema)));
  return v_task;
end $$;

revoke all on function public.save_task_designer_template(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.assign_task_from_template(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.save_task_designer_template(uuid,uuid,jsonb) to authenticated;
grant execute on function public.assign_task_from_template(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,text,jsonb) to authenticated;

commit;
