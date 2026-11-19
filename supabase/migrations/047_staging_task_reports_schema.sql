begin;

-- Additive task/report foundation for the existing organization_memberships identity model.
-- The employee-code-auth login flow, auth.users, memberships, and existing organization RLS are untouched.

-- Seed supported roles for each existing organization; IDs are shared with institutions
-- in this staging schema, and this lets the designer target roles before employees are assigned.
insert into public.roles(institution_id, code, name_ar, is_system)
select i.id, supported.code,
  case supported.code
    when 'owner' then 'صاحب المؤسسة'
    when 'admin_followup' then 'المدير التنفيذي'
    when 'accountant' then 'المحاسب'
    when 'warehouse_keeper' then 'أمين المخازن'
    when 'warehouse_worker' then 'عامل المستودع'
    else supported.code
  end, true
from public.institutions i
cross join (values ('owner'),('admin_followup'),('accountant'),('warehouse_keeper'),('warehouse_worker')) as supported(code)
on conflict (institution_id, code) do nothing;

insert into public.permissions(code,name_ar,domain,action,description) values
 ('employees.manage','إدارة الموظفين','employees','manage','إدارة حسابات وعضويات الموظفين'),
 ('tasks.read','قراءة المهام','tasks','read','عرض المهام المعيّنة للمستخدم'),
 ('tasks.manage','إدارة المهام','tasks','manage','إنشاء وإسناد ومتابعة المهام'),
 ('tasks.read_all','قراءة جميع المهام','tasks','read_all','قراءة مهام المؤسسة'),
 ('tasks.review','مراجعة المهام','tasks','review','مراجعة تقارير المهام'),
 ('task_library.read','قراءة مكتبة المهام','task_library','read','عرض قوالب المهام والتقارير المعتمدة'),
 ('task_library.manage','إدارة مكتبة المهام','task_library','manage','إنشاء وتعديل قوالب المهام'),
 ('task_library.import','استيراد مكتبة المهام','task_library','import','استيراد قوالب المهام'),
 ('task_library.convert','تحويل قالب إلى مهمة','task_library','convert','إنشاء مهمة فعلية من قالب'),
 ('report_forms.manage','إدارة نماذج التقارير','reports','manage','إنشاء ونشر وإدارة نماذج التقارير'),
 ('reports.read_all','قراءة تقارير المؤسسة','reports','read_all','قراءة تقارير الموظفين'),
 ('task_reports.read','قراءة تقارير المهام','tasks','report_read','قراءة تقارير المهام ومرفقاتها')
on conflict(code) do update set name_ar=excluded.name_ar,domain=excluded.domain,action=excluded.action,description=excluded.description;

-- Every supported employee role can read their own tasks. Only owner/follow-up
-- managers receive task-library/report-design/review privileges by default.
insert into public.role_permissions(institution_id,role_id,permission_code)
select r.institution_id,r.id,p.code
from public.roles r
join public.permissions p on p.code='tasks.read'
where r.code in ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker')
on conflict do nothing;
insert into public.role_permissions(institution_id,role_id,permission_code)
select r.institution_id,r.id,p.code
from public.roles r
cross join public.permissions p
where r.code in ('owner','admin_followup')
  and p.code in ('employees.manage','tasks.manage','tasks.read_all','tasks.review','task_library.read','task_library.manage','task_library.import','task_library.convert','report_forms.manage','reports.read_all','task_reports.read')
on conflict do nothing;

create or replace function public.has_org_permission(p_organization_id uuid,p_permission text,p_branch_id uuid default null)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select auth.uid() is not null and exists (
   select 1 from public.organization_memberships m
   join public.role_assignments ra on ra.organization_id=m.organization_id and ra.membership_id=m.id
   join public.roles r on r.institution_id=m.organization_id and r.code=ra.role_code
   join public.role_permissions rp on rp.institution_id=r.institution_id and rp.role_id=r.id
   where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.is_active
     and rp.permission_code=p_permission
     and (p_branch_id is null or ra.branch_id is null or ra.branch_id=p_branch_id)
 );
$$;
revoke all on function public.has_org_permission(uuid,text,uuid) from public,anon;
grant execute on function public.has_org_permission(uuid,text,uuid) to authenticated;

create or replace function public.task_library_allowed_for_org(p_organization_id uuid,p_required_permission text default 'task_library.read')
returns boolean language sql security definer set search_path=public,auth as $$
 select p_required_permission in ('task_library.read','task_library.manage')
   and public.has_org_permission(p_organization_id,p_required_permission,null::uuid)
$$;
revoke all on function public.task_library_allowed_for_org(uuid,text) from public,anon;
grant execute on function public.task_library_allowed_for_org(uuid,text) to authenticated;

create or replace function public.report_designer_allowed_for_org(p_organization_id uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select public.has_org_permission(p_organization_id,'report_forms.manage',null::uuid)
     or public.has_org_permission(p_organization_id,'task_library.manage',null::uuid)
$$;
revoke all on function public.report_designer_allowed_for_org(uuid) from public,anon;
grant execute on function public.report_designer_allowed_for_org(uuid) to authenticated;

create or replace function public.report_can_review_in_org(p_organization_id uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select public.has_org_permission(p_organization_id,'tasks.review',null::uuid)
$$;
revoke all on function public.report_can_review_in_org(uuid) from public,anon;
grant execute on function public.report_can_review_in_org(uuid) to authenticated;

-- Preserve the existing employee-code-auth profile shape while returning permissions
-- from the current institution role tables, so the existing UI can authorize task screens.
create or replace function public.mobile_my_profile()
returns jsonb language sql stable security definer set search_path=public,auth as $$
 select jsonb_build_object('employee',jsonb_build_object(
   'id',m.id,'institutionId',m.organization_id,'employeeNo',m.employee_no,'fullName',m.display_name,
   'email',u.email,'phone',u.phone,'status',case when m.is_active then 'active' else 'inactive' end,
   'lastLoginAt',u.last_sign_in_at,
   'roles',coalesce((select jsonb_agg(jsonb_build_object('code',ra.role_code) order by ra.role_code) from public.role_assignments ra where ra.organization_id=m.organization_id and ra.membership_id=m.id),'[]'::jsonb),
   'permissions',coalesce((select jsonb_agg(distinct rp.permission_code order by rp.permission_code)
     from public.role_assignments ra join public.roles r on r.institution_id=m.organization_id and r.code=ra.role_code
     join public.role_permissions rp on rp.institution_id=r.institution_id and rp.role_id=r.id
     where ra.organization_id=m.organization_id and ra.membership_id=m.id),'[]'::jsonb),
   'branches',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'code',b.code,'name',b.name,'isDefault',false) order by b.name)
     from public.branches b where b.organization_id=m.organization_id and b.is_active),'[]'::jsonb)
 )) from public.organization_memberships m left join auth.users u on u.id=m.user_id
 where m.user_id=auth.uid() and m.is_active order by m.created_at limit 1;
$$;
revoke all on function public.mobile_my_profile() from public,anon;
grant execute on function public.mobile_my_profile() to authenticated;

create table if not exists public.task_templates (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 code text not null, title text not null check(length(trim(title)) between 2 and 200), description text,
 expected_result text, branch_level text, job_title text, task_type text not null default 'operational',
 recurrence_type text not null default 'one_time', recurrence_config jsonb not null default '{}'::jsonb,
 default_priority text not null default 'normal' check(default_priority in ('normal','important','urgent','critical')),
 is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 role_code text not null, instructions text, category_id uuid, subcategory_id uuid,
 default_duration_minutes integer check(default_duration_minutes is null or default_duration_minutes between 1 and 10080),
 version integer not null default 1 check(version>0), unique(organization_id,code), unique(organization_id,id),
 check(jsonb_typeof(recurrence_config)='object')
);

create table if not exists public.tasks (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 branch_id uuid references public.branches(id) on delete set null,
 title text not null check(length(trim(title)) between 2 and 200), description text,
 expected_result text, priority text not null default 'normal' check(priority in ('normal','important','urgent','critical')),
 status text not null default 'new' check(status in ('new','received','in_progress','on_hold','report_submitted','needs_revision','completed_approved','cancelled','late','pending','submitted','approved','rejected')),
 assigned_to uuid not null references auth.users(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict,
 assigned_at timestamptz not null default now(), due_at timestamptz not null, starts_at timestamptz,
 started_at timestamptz, report_submitted_at timestamptz, approved_at timestamptz, hold_reason text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 template_id uuid references public.task_templates(id) on delete set null, report_required boolean not null default false, report_form_snapshot_id uuid,
 position_code text check(position_code is null or position_code in ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker')),
 task_instructions text, category_id uuid, subcategory_id uuid, report_flow text not null default 'legacy' check(report_flow in ('legacy','multi_form')),
 proof_required boolean not null default false, proof_instructions text, template_version integer,
 report_schema jsonb not null default '[]'::jsonb,
 check(starts_at is null or due_at>=starts_at), check(jsonb_typeof(report_schema)='array'), unique(organization_id,id)
);

create table if not exists public.task_activity_log (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null, action text not null check(length(trim(action))>=2),
 details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), check(jsonb_typeof(details)='object')
);
create table if not exists public.task_reports (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
 submitted_by uuid not null references auth.users(id) on delete restrict,
 status text not null default 'submitted' check(status in ('submitted','returned','approved')),
 progress_percent numeric check(progress_percent is null or progress_percent between 0 and 100), notes text,
 values jsonb not null default '{}'::jsonb, submitted_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id) on delete set null, reviewed_at timestamptz,
 review_action text, review_note text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 report_form_snapshot_id uuid, idempotency_key text, organization_id uuid references public.organizations(id) on delete cascade,
 check(jsonb_typeof(values)='object')
);
create table if not exists public.task_report_fields (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
 label text not null, field_type text not null, is_required boolean not null default false,
 options jsonb not null default '[]'::jsonb, sort_order integer not null default 0,
 created_at timestamptz not null default now(), field_key text, source_snapshot_id uuid
);
create table if not exists public.task_attachments (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
 report_id uuid references public.task_reports(id) on delete set null,
 uploaded_by uuid not null references auth.users(id) on delete restrict, file_name text not null,
 storage_path text not null unique, mime_type text, size_bytes bigint check(size_bytes is null or size_bytes>0),
 created_at timestamptz not null default now(), execution_step_id uuid
);
create table if not exists public.report_form_templates (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 code text not null, title text not null check(length(trim(title)) between 2 and 160), description text,
 role_code text not null, is_active boolean not null default true, created_by uuid not null references auth.users(id),
 updated_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(organization_id,code)
);
create table if not exists public.report_form_versions (
 id uuid primary key default gen_random_uuid(), template_id uuid not null references public.report_form_templates(id) on delete cascade,
 version_no integer not null check(version_no>0), status text not null default 'draft' check(status in ('draft','published','archived')),
 report_required boolean not null default true, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 published_at timestamptz, approved_by uuid references auth.users(id), approved_at timestamptz, unique(template_id,version_no)
);
create table if not exists public.report_form_version_fields (
 id uuid primary key default gen_random_uuid(), version_id uuid not null references public.report_form_versions(id) on delete cascade,
 field_key text not null check(field_key ~ '^[a-z][a-z0-9_]{0,63}$'), label text not null check(length(trim(label)) between 1 and 200),
 description text, field_type text not null, is_required boolean not null default false, repeatable boolean not null default false,
 sort_order integer not null default 0, validation jsonb not null default '{}'::jsonb, options jsonb not null default '[]'::jsonb,
 config jsonb not null default '{}'::jsonb, unique(version_id,field_key), check(jsonb_typeof(validation)='object'),
 check(jsonb_typeof(options)='array'),check(jsonb_typeof(config)='object')
);
create table if not exists public.task_template_report_fields (
 id uuid primary key default gen_random_uuid(), template_id uuid not null references public.task_templates(id) on delete cascade,
 field_key text, label text not null, field_type text not null, is_required boolean not null default false,
 options jsonb not null default '[]'::jsonb, sort_order integer not null default 0
);
create table if not exists public.task_template_steps (
 id uuid primary key default gen_random_uuid(), template_id uuid not null references public.task_templates(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 200), instructions text, sort_order integer not null check(sort_order>=0),
 is_required boolean not null default true, evidence_required boolean not null default false, evidence_instructions text,
 unique(template_id,sort_order)
);
create table if not exists public.task_template_report_forms (
 id uuid primary key default gen_random_uuid(), template_id uuid not null references public.task_templates(id) on delete cascade,
 version_id uuid not null references public.report_form_versions(id) on delete restrict,
 sort_order integer not null check(sort_order>=0), is_required boolean not null default true,
 unique(template_id,version_id),unique(template_id,sort_order)
);
create table if not exists public.task_report_form_snapshots (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
 template_id uuid references public.report_form_templates(id) on delete set null,
 version_id uuid references public.report_form_versions(id) on delete set null,
 report_required boolean not null default false, schema jsonb not null default '[]'::jsonb,
 published_by uuid not null references auth.users(id), published_at timestamptz not null default now(),
 title text, sort_order integer not null default 0, is_required boolean not null default true,
 organization_id uuid references public.organizations(id) on delete cascade,
 task_report_form_id uuid references public.task_template_report_forms(id) on delete set null,
 check(jsonb_typeof(schema)='array')
);
create table if not exists public.task_execution_steps (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
 source_template_step_id uuid references public.task_template_steps(id) on delete set null,
 title text not null, instructions text, sort_order integer not null,
 is_required boolean not null default true, evidence_required boolean not null default false, evidence_instructions text,
 completed_by uuid references auth.users(id) on delete set null, completed_at timestamptz,
 unique(task_id,sort_order), unique(task_id,id)
);
create table if not exists public.task_report_drafts (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
 snapshot_id uuid not null references public.task_report_form_snapshots(id) on delete cascade,
 employee_id uuid not null references auth.users(id) on delete cascade,
 values jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now(),
 unique(task_id,snapshot_id,employee_id),check(jsonb_typeof(values)='object')
);
create table if not exists public.task_report_signature_attachments (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete restrict,
 report_id uuid not null references public.task_reports(id) on delete restrict,
 report_form_snapshot_id uuid not null references public.task_report_form_snapshots(id) on delete restrict,
 field_key text not null, signed_by uuid not null references auth.users(id), consent_text text not null default '',
 acknowledged boolean not null default false, stroke_paths jsonb not null, signed_at timestamptz not null default now(),
 created_at timestamptz not null default now(), unique(report_id,field_key),
 check(jsonb_typeof(stroke_paths)='array' and jsonb_array_length(stroke_paths) between 1 and 200)
);

alter table public.tasks add constraint tasks_report_form_snapshot_fk foreign key(report_form_snapshot_id) references public.task_report_form_snapshots(id) on delete set null;
alter table public.task_report_fields add constraint task_report_fields_snapshot_fk foreign key(source_snapshot_id) references public.task_report_form_snapshots(id) on delete set null;

create index if not exists tasks_assignee_due_idx on public.tasks(assigned_to,due_at) where deleted_at is null;
create index if not exists tasks_org_status_idx on public.tasks(organization_id,status,due_at);
create index if not exists task_reports_task_date_idx on public.task_reports(task_id,submitted_at desc);
create unique index if not exists task_reports_submit_idempotency_uq on public.task_reports(submitted_by,idempotency_key) where idempotency_key is not null;
create index if not exists task_activity_log_task_date_idx on public.task_activity_log(task_id,created_at desc);
create index if not exists task_execution_steps_task_order_idx on public.task_execution_steps(task_id,sort_order);
create index if not exists task_template_report_forms_order_idx on public.task_template_report_forms(template_id,sort_order);
create index if not exists task_report_form_snapshots_task_order_idx on public.task_report_form_snapshots(task_id,sort_order);
create index if not exists report_form_templates_org_idx on public.report_form_templates(organization_id,role_code,is_active,title);
create index if not exists report_form_versions_template_idx on public.report_form_versions(template_id,version_no desc);
create index if not exists report_form_fields_order_idx on public.report_form_version_fields(version_id,sort_order);

commit;
