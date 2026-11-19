-- HR core: responsibilities, dual approval, contracts, schedules, attendance and payroll.
alter table public.employee_agreement_versions add column if not exists responsibilities jsonb not null default '[]'::jsonb;
update public.employee_agreement_versions set responsibilities = coalesce(terms->'responsibilities', '[]'::jsonb) where jsonb_typeof(coalesce(terms->'responsibilities', '[]'::jsonb)) = 'array' and responsibilities = '[]'::jsonb;
create or replace function public.sync_employee_agreement_responsibilities() returns trigger language plpgsql as $$ begin if new.responsibilities = '[]'::jsonb and jsonb_typeof(coalesce(new.terms->'responsibilities','[]'::jsonb)) = 'array' then new.responsibilities := coalesce(new.terms->'responsibilities','[]'::jsonb); end if; return new; end; $$;
drop trigger if exists employee_agreement_responsibilities_sync on public.employee_agreement_versions;
create trigger employee_agreement_responsibilities_sync before insert or update of terms on public.employee_agreement_versions for each row execute function public.sync_employee_agreement_responsibilities();
alter table public.employee_agreement_versions add constraint employee_agreement_versions_responsibilities_array check (jsonb_typeof(responsibilities) = 'array');
alter table public.employee_agreement_audit_log drop constraint if exists employee_agreement_audit_log_action_check;
alter table public.employee_agreement_audit_log add constraint employee_agreement_audit_log_action_check check (action in ('created','updated','submitted_for_approval','published','accepted','rejected','superseded','revoked','manager_approved','employee_approved'));

create table if not exists public.employee_agreement_approvals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agreement_id uuid not null references public.employee_agreements(id) on delete cascade,
  version_id uuid not null references public.employee_agreement_versions(id) on delete restrict,
  membership_id uuid not null references public.organization_memberships(id) on delete restrict,
  employee_status text not null default 'pending' check (employee_status in ('pending','approved','rejected')),
  manager_status text not null default 'pending' check (manager_status in ('pending','approved','rejected')),
  employee_note text,
  manager_note text,
  employee_approved_by uuid references auth.users(id),
  manager_approved_by uuid references auth.users(id),
  employee_approved_at timestamptz,
  manager_approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (version_id, membership_id)
);

create table if not exists public.employee_contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid not null references public.organization_memberships(id) on delete restrict,
  agreement_id uuid references public.employee_agreements(id) on delete set null,
  contract_no text not null,
  contract_type text not null default 'employment',
  status text not null default 'draft' check (status in ('draft','active','suspended','expired','terminated')),
  start_date date not null,
  end_date date,
  base_salary numeric(14,2),
  salary_currency text not null default 'SAR' check (length(salary_currency) between 3 and 8),
  pay_frequency text not null default 'monthly' check (pay_frequency in ('monthly','weekly','daily','hourly')),
  duties jsonb not null default '[]'::jsonb check (jsonb_typeof(duties) = 'array'),
  document_path text,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, contract_no),
  check (end_date is null or end_date >= start_date),
  check (base_salary is null or base_salary >= 0)
);

create table if not exists public.employee_work_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid not null references public.organization_memberships(id) on delete restrict,
  name text not null,
  timezone text not null default 'Asia/Riyadh',
  work_days jsonb not null default '[0,1,2,3,4]'::jsonb check (jsonb_typeof(work_days) = 'array'),
  start_time time not null,
  end_time time not null,
  break_minutes integer not null default 0 check (break_minutes between 0 and 720),
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

create table if not exists public.employee_attendance_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid not null references public.organization_memberships(id) on delete restrict,
  schedule_id uuid references public.employee_work_schedules(id) on delete set null,
  work_date date not null,
  check_in_at timestamptz,
  check_out_at timestamptz,
  status text not null default 'present' check (status in ('present','absent','late','leave','holiday','incomplete')),
  note text,
  recorded_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (membership_id, work_date),
  check (check_out_at is null or check_in_at is null or check_out_at >= check_in_at)
);

create table if not exists public.employee_payroll_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','processing','approved','paid','closed')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id, period_start, period_end),
  check (period_end >= period_start)
);

create table if not exists public.employee_payroll_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  period_id uuid not null references public.employee_payroll_periods(id) on delete cascade,
  membership_id uuid not null references public.organization_memberships(id) on delete restrict,
  base_amount numeric(14,2) not null default 0 check (base_amount >= 0),
  additions numeric(14,2) not null default 0 check (additions >= 0),
  deductions numeric(14,2) not null default 0 check (deductions >= 0),
  net_amount numeric(14,2) generated always as (base_amount + additions - deductions) stored,
  currency text not null default 'SAR' check (length(currency) between 3 and 8),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (period_id, membership_id)
);

create index if not exists employee_contracts_member_idx on public.employee_contracts (organization_id, membership_id, status);
create index if not exists employee_schedules_member_idx on public.employee_work_schedules (organization_id, membership_id, is_active);
create index if not exists employee_attendance_member_date_idx on public.employee_attendance_records (organization_id, membership_id, work_date desc);
create index if not exists employee_payroll_entries_member_idx on public.employee_payroll_entries (organization_id, membership_id, period_id);

-- Add HR permissions in either supported permission metadata layout.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='domain') then
    execute $q$insert into public.permissions(code,name_ar,domain,action,description) values
      ('employee_agreements.approve','اعتماد اتفاقيات العمل','employee_agreements','approve','اعتماد المدير لاتفاقية الموظف'),
      ('employee_hr.manage','إدارة الموارد البشرية','employee_hr','manage','إدارة العقود والدوام والرواتب'),
      ('employee_hr.read_all','قراءة الموارد البشرية','employee_hr','read_all','قراءة بيانات الموارد البشرية') on conflict(code) do nothing$q$;
  else
    execute $q$insert into public.permissions(code,name_ar) values
      ('employee_agreements.approve','اعتماد اتفاقيات العمل'),('employee_hr.manage','إدارة الموارد البشرية'),('employee_hr.read_all','قراءة الموارد البشرية') on conflict(code) do nothing$q$;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='role_permissions' and column_name='role_code') then
    insert into public.role_permissions(role_code,permission_code) select r.code,p.code from public.roles r cross join public.permissions p where r.code in ('owner','admin_followup') and p.code in ('employee_agreements.approve','employee_hr.manage','employee_hr.read_all') on conflict do nothing;
  else
    insert into public.role_permissions(institution_id,role_id,permission_code) select r.institution_id,r.id,p.code from public.roles r cross join public.permissions p where r.code in ('owner','admin_followup') and p.code in ('employee_agreements.approve','employee_hr.manage','employee_hr.read_all') on conflict do nothing;
  end if;
end $$;

alter table public.employee_agreement_approvals enable row level security;
alter table public.employee_contracts enable row level security;
alter table public.employee_work_schedules enable row level security;
alter table public.employee_attendance_records enable row level security;
alter table public.employee_payroll_periods enable row level security;
alter table public.employee_payroll_entries enable row level security;
revoke all on public.employee_agreement_approvals,public.employee_contracts,public.employee_work_schedules,public.employee_attendance_records,public.employee_payroll_periods,public.employee_payroll_entries from public,anon;
grant select on public.employee_agreement_approvals,public.employee_contracts,public.employee_work_schedules,public.employee_attendance_records,public.employee_payroll_periods,public.employee_payroll_entries to authenticated;
revoke insert,update,delete on public.employee_agreement_approvals,public.employee_contracts,public.employee_work_schedules,public.employee_attendance_records,public.employee_payroll_periods,public.employee_payroll_entries from authenticated;

create policy employee_agreement_approvals_read on public.employee_agreement_approvals for select to authenticated using (
  public.employee_agreement_can(organization_id,'employee_agreements.read_all',null::uuid)
  or exists (select 1 from public.organization_memberships m where m.id=membership_id and m.user_id=auth.uid() and m.is_active)
);
create policy employee_contracts_read on public.employee_contracts for select to authenticated using (
  public.employee_agreement_can(organization_id,'employee_hr.read_all',null::uuid)
  or exists (select 1 from public.organization_memberships m where m.id=membership_id and m.user_id=auth.uid() and m.is_active)
);
create policy employee_schedules_read on public.employee_work_schedules for select to authenticated using (
  public.employee_agreement_can(organization_id,'employee_hr.read_all',null::uuid)
  or exists (select 1 from public.organization_memberships m where m.id=membership_id and m.user_id=auth.uid() and m.is_active)
);
create policy employee_attendance_read on public.employee_attendance_records for select to authenticated using (
  public.employee_agreement_can(organization_id,'employee_hr.read_all',null::uuid)
  or exists (select 1 from public.organization_memberships m where m.id=membership_id and m.user_id=auth.uid() and m.is_active)
);
create policy employee_payroll_periods_read on public.employee_payroll_periods for select to authenticated using (public.employee_agreement_can(organization_id,'employee_hr.read_all',null::uuid));
create policy employee_payroll_entries_read on public.employee_payroll_entries for select to authenticated using (
  public.employee_agreement_can(organization_id,'employee_hr.read_all',null::uuid)
  or exists (select 1 from public.organization_memberships m where m.id=membership_id and m.user_id=auth.uid() and m.is_active)
);

create or replace function public.approve_employee_agreement(p_agreement_id uuid,p_decision text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid:=auth.uid(); v_a public.employee_agreements%rowtype; v_v public.employee_agreement_versions%rowtype; v_is_employee boolean; v_manager boolean;
begin
  if v_user is null or p_decision not in ('approved','rejected') then raise exception using errcode='22023',message='invalid_agreement_approval'; end if;
  select * into v_a from public.employee_agreements where id=p_agreement_id for update;
  if not found then raise exception using errcode='40400',message='agreement_not_found'; end if;
  select * into v_v from public.employee_agreement_versions where id=v_a.current_version_id;
  v_is_employee := exists(select 1 from public.organization_memberships m where m.id=v_a.membership_id and m.user_id=v_user and m.is_active);
  v_manager := public.employee_agreement_can(v_a.organization_id,'employee_agreements.approve',null::uuid);
  if not v_is_employee and not v_manager then raise exception using errcode='42501',message='agreement_approval_denied'; end if;
  insert into public.employee_agreement_approvals(organization_id,agreement_id,version_id,membership_id)
  values(v_a.organization_id,v_a.id,v_a.current_version_id,v_a.membership_id)
  on conflict(version_id,membership_id) do nothing;
  if v_is_employee then
    update public.employee_agreement_approvals set employee_status=p_decision,employee_note=nullif(trim(p_note),''),employee_approved_by=v_user,employee_approved_at=now(),updated_at=now() where version_id=v_a.current_version_id and membership_id=v_a.membership_id;
  else
    update public.employee_agreement_approvals set manager_status=p_decision,manager_note=nullif(trim(p_note),''),manager_approved_by=v_user,manager_approved_at=now(),updated_at=now() where version_id=v_a.current_version_id and membership_id=v_a.membership_id;
  end if;
  if p_decision='rejected' then update public.employee_agreements set status='rejected',updated_by=v_user,updated_at=now() where id=v_a.id; else
    if exists(select 1 from public.employee_agreement_approvals where version_id=v_a.current_version_id and employee_status='approved' and manager_status='approved') then update public.employee_agreements set status='accepted',updated_by=v_user,updated_at=now() where id=v_a.id; end if;
  end if;
  insert into public.employee_agreement_audit_log(organization_id,agreement_id,version_id,membership_id,actor_user_id,action,from_status,to_status,metadata)
  values(v_a.organization_id,v_a.id,v_a.current_version_id,v_a.membership_id,v_user,case when v_is_employee then 'employee_approved' else 'manager_approved' end,v_a.status,(select status from public.employee_agreements where id=v_a.id),jsonb_build_object('decision',p_decision,'note',p_note));
  return jsonb_build_object('agreement_id',v_a.id,'status',(select status from public.employee_agreements where id=v_a.id));
end; $$;
revoke all on function public.approve_employee_agreement(uuid,text,text) from public,anon,authenticated;
grant execute on function public.approve_employee_agreement(uuid,text,text) to authenticated;
