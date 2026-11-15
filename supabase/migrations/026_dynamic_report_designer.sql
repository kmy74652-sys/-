begin;

-- Dynamic report designer. Additive only: existing task/report/attachment data is preserved.
create table if not exists public.report_form_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code text not null check (code ~ '^[a-z0-9][a-z0-9_-]{1,63}$'),
  title text not null check (length(trim(title)) >= 2),
  description text,
  role_code text not null references public.roles(code),
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists public.report_form_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.report_form_templates(id) on delete cascade,
  version_no integer not null check (version_no > 0),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  report_required boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  unique (template_id, version_no)
);

create table if not exists public.report_form_version_fields (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.report_form_versions(id) on delete cascade,
  field_key text not null check (field_key ~ '^[a-z][a-z0-9_]{0,63}$'),
  label text not null check (length(trim(label)) >= 1),
  description text,
  field_type text not null check (field_type in ('short_text','long_text','integer','quantity','money','datetime','select','multiselect','boolean','table','image','file','signature','calculated','decision_notes')),
  is_required boolean not null default false,
  repeatable boolean not null default false,
  sort_order integer not null default 0 check (sort_order >= 0),
  validation jsonb not null default '{}'::jsonb,
  options jsonb not null default '[]'::jsonb,
  config jsonb not null default '{}'::jsonb,
  unique (version_id, field_key),
  check (jsonb_typeof(validation) = 'object'),
  check (jsonb_typeof(options) = 'array'),
  check (jsonb_typeof(config) = 'object')
);

alter table public.tasks add column if not exists report_required boolean not null default false;
alter table public.tasks add column if not exists report_form_snapshot_id uuid;
alter table public.task_report_fields add column if not exists source_snapshot_id uuid;

create table if not exists public.task_report_form_snapshots (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null unique references public.tasks(id) on delete cascade,
  template_id uuid references public.report_form_templates(id) on delete set null,
  version_id uuid references public.report_form_versions(id) on delete set null,
  report_required boolean not null default false,
  schema jsonb not null default '[]'::jsonb,
  published_by uuid not null references auth.users(id),
  published_at timestamptz not null default now(),
  check (jsonb_typeof(schema) = 'array')
);

do $$ begin
  alter table public.tasks add constraint tasks_report_form_snapshot_fk
    foreign key (report_form_snapshot_id) references public.task_report_form_snapshots(id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.task_report_fields add constraint task_report_fields_snapshot_fk
    foreign key (source_snapshot_id) references public.task_report_form_snapshots(id) on delete set null;
exception when duplicate_object then null; end $$;

create index if not exists report_form_templates_org_idx on public.report_form_templates (organization_id, role_code, is_active, title);
create index if not exists report_form_versions_template_idx on public.report_form_versions (template_id, version_no desc);
create index if not exists report_form_fields_order_idx on public.report_form_version_fields (version_id, sort_order);

insert into public.permissions (code, name_ar)
values ('report_forms.manage', 'تصميم نماذج التقارير')
on conflict (code) do update set name_ar = excluded.name_ar;
insert into public.role_permissions (role_code, permission_code)
values ('owner', 'report_forms.manage'), ('admin_followup', 'report_forms.manage')
on conflict do nothing;

create or replace function public.report_designer_allowed(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1
    from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
    join public.role_permissions rp on rp.role_code = ra.role_code and rp.permission_code = 'report_forms.manage'
    where m.user_id = p_user_id and m.is_active
  );
$$;

alter table public.report_form_templates enable row level security;
alter table public.report_form_versions enable row level security;
alter table public.report_form_version_fields enable row level security;
alter table public.task_report_form_snapshots enable row level security;

drop policy if exists report_form_templates_read on public.report_form_templates;
create policy report_form_templates_read on public.report_form_templates for select to authenticated using (
  organization_id = (select organization_id from public.organization_memberships where user_id = auth.uid() and is_active limit 1)
  and (public.report_designer_allowed(auth.uid()) or exists (select 1 from public.role_assignments ra join public.organization_memberships m on m.id=ra.membership_id where m.user_id=auth.uid() and m.is_active and ra.role_code in ('owner','admin_followup')))
);
drop policy if exists report_form_templates_manage on public.report_form_templates;
create policy report_form_templates_manage on public.report_form_templates for all to authenticated using (public.report_designer_allowed(auth.uid())) with check (public.report_designer_allowed(auth.uid()));

drop policy if exists report_form_versions_read on public.report_form_versions;
create policy report_form_versions_read on public.report_form_versions for select to authenticated using (exists (select 1 from public.report_form_templates t where t.id=template_id and public.report_designer_allowed(auth.uid())));
drop policy if exists report_form_versions_manage on public.report_form_versions;
create policy report_form_versions_manage on public.report_form_versions for all to authenticated using (public.report_designer_allowed(auth.uid())) with check (public.report_designer_allowed(auth.uid()));

drop policy if exists report_form_fields_read on public.report_form_version_fields;
create policy report_form_fields_read on public.report_form_version_fields for select to authenticated using (exists (select 1 from public.report_form_versions v where v.id=version_id and public.report_designer_allowed(auth.uid())));
drop policy if exists report_form_fields_manage on public.report_form_version_fields;
create policy report_form_fields_manage on public.report_form_version_fields for all to authenticated using (public.report_designer_allowed(auth.uid())) with check (public.report_designer_allowed(auth.uid()));

drop policy if exists task_report_snapshots_read on public.task_report_form_snapshots;
create policy task_report_snapshots_read on public.task_report_form_snapshots for select to authenticated using (exists (select 1 from public.tasks t where t.id=task_id and (t.assigned_to=auth.uid() or t.created_by=auth.uid() or public.report_designer_allowed(auth.uid()))));
drop policy if exists task_report_snapshots_insert on public.task_report_form_snapshots;
create policy task_report_snapshots_insert on public.task_report_form_snapshots for insert to authenticated with check (public.report_designer_allowed(auth.uid()) and published_by=auth.uid());

create or replace function public.publish_task_report_form(
  p_task_id uuid,
  p_template_id uuid,
  p_version_id uuid,
  p_report_required boolean default true
) returns uuid language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid(); v_task public.tasks%rowtype; v_snapshot uuid; v_schema jsonb;
begin
  if v_user is null or not public.report_designer_allowed(v_user) then raise exception using errcode='42501', message='permission_denied'; end if;
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found then raise exception using errcode='P0002', message='task_not_found'; end if;
  if not exists (select 1 from public.report_form_versions v join public.report_form_templates t on t.id=v.template_id where v.id=p_version_id and t.id=p_template_id and t.organization_id=v_task.organization_id and v.status in ('draft','published')) then raise exception using errcode='22023', message='report_form_version_not_found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('key',f.field_key,'label',f.label,'description',f.description,'type',f.field_type,'required',f.is_required,'repeatable',f.repeatable,'options',f.options,'validation',f.validation,'config',f.config) order by f.sort_order), '[]'::jsonb) into v_schema from public.report_form_version_fields f where f.version_id=p_version_id;
  insert into public.task_report_form_snapshots(task_id,template_id,version_id,report_required,schema,published_by) values(p_task_id,p_template_id,p_version_id,p_report_required,v_schema,v_user)
  on conflict(task_id) do update set template_id=excluded.template_id,version_id=excluded.version_id,report_required=excluded.report_required,schema=excluded.schema,published_by=excluded.published_by,published_at=now() returning id into v_snapshot;
  update public.tasks set report_required=p_report_required, report_form_snapshot_id=v_snapshot, updated_at=now() where id=p_task_id;
  insert into public.task_activity_log(task_id,actor_id,action,details) values(p_task_id,v_user,'report_form_published',jsonb_build_object('snapshot_id',v_snapshot,'version_id',p_version_id));
  return v_snapshot;
end $$;
revoke all on function public.publish_task_report_form(uuid,uuid,uuid,boolean) from public, anon, authenticated;
grant execute on function public.publish_task_report_form(uuid,uuid,uuid,boolean) to authenticated;

commit;
