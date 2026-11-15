begin;

create table if not exists public.employee_access_credentials (
  membership_id uuid primary key references public.organization_memberships(id) on delete cascade,
  code_salt text not null,
  code_hash text not null,
  auth_bridge_password text not null,
  updated_at timestamptz not null default now()
);

alter table public.employee_access_credentials enable row level security;
revoke all on public.employee_access_credentials from public, anon, authenticated;
grant all on public.employee_access_credentials to service_role;

commit;
