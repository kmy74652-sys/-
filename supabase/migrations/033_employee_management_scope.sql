begin;

-- Allow the executive manager to manage employee accounts within the organization.
create table if not exists public.employee_access_audit_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid references public.organization_memberships(id) on delete set null,
  actor_membership_id uuid references public.organization_memberships(id) on delete set null,
  action text not null check (action in (
    'created', 'updated', 'code_set', 'password_reset', 'code_revoked',
    'suspended', 'reactivated', 'role_changed', 'branch_changed'
  )),
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists employee_access_audit_org_created_idx
  on public.employee_access_audit_log (organization_id, created_at desc);

alter table public.employee_access_audit_log enable row level security;
revoke all on public.employee_access_audit_log from public, anon, authenticated;
grant all on public.employee_access_audit_log to service_role;

insert into public.role_permissions (role_code, permission_code)
select r.code, 'employees.manage'
from public.roles r
where r.code = 'admin_followup'
on conflict do nothing;

alter table public.employee_access_audit_log
  drop constraint if exists employee_access_audit_log_action_check;

alter table public.employee_access_audit_log
  add constraint employee_access_audit_log_action_check
  check (action in (
    'created', 'updated', 'code_set', 'password_reset', 'code_revoked',
    'suspended', 'reactivated', 'role_changed', 'branch_changed'
  ));

commit;
