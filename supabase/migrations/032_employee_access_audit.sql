begin;

create table if not exists public.employee_access_audit_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid references public.organization_memberships(id) on delete set null,
  actor_membership_id uuid references public.organization_memberships(id) on delete set null,
  action text not null check (action in ('created', 'code_set', 'code_revoked', 'suspended', 'reactivated')),
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists employee_access_audit_org_created_idx
  on public.employee_access_audit_log (organization_id, created_at desc);

alter table public.employee_access_audit_log enable row level security;
revoke all on public.employee_access_audit_log from public, anon, authenticated;
grant all on public.employee_access_audit_log to service_role;

commit;
