begin;

alter table public.employees
  add column if not exists access_code_set_at timestamptz,
  add column if not exists access_code_updated_by uuid;

-- Ensure the explicitly designated owner account receives the owner role in its institution.
do $$
declare
  owner_row record;
  owner_role_id uuid;
begin
  for owner_row in
    select distinct e.institution_id, e.id
    from public.employees e
    left join auth.users u on u.id = e.auth_user_id
    where (
      lower(trim(coalesce(e.email, ''))) = 'als43870@gmail.com'
      or lower(trim(coalesce(u.email, ''))) = 'als43870@gmail.com'
  )
      and e.status = 'active'
  loop
    insert into public.roles (institution_id, code, name_ar, description)
    values (owner_row.institution_id, 'owner', 'صاحب المؤسسة', 'تحكم كامل وإشراف واعتماد نهائي')
    on conflict (institution_id, code) do update
      set name_ar = excluded.name_ar, description = excluded.description
    returning id into owner_role_id;

    insert into public.role_permissions (institution_id, role_id, permission_code)
    select owner_row.institution_id, owner_role_id, p.code
    from public.permissions p
    on conflict do nothing;

    insert into public.employee_roles (institution_id, employee_id, role_id)
    values (owner_row.institution_id, owner_row.id, owner_role_id)
    on conflict do nothing;
  end loop;
end $$;

create table if not exists public.employee_access_code_login_attempts (
  id uuid primary key default gen_random_uuid(),
  employee_key_hash text not null,
  ip_key_hash text not null,
  attempted_at timestamptz not null default now()
);

create index if not exists employee_access_code_attempt_employee_time_idx
  on public.employee_access_code_login_attempts (employee_key_hash, attempted_at desc);

create index if not exists employee_access_code_attempt_ip_time_idx
  on public.employee_access_code_login_attempts (ip_key_hash, attempted_at desc);

create index if not exists employee_access_code_attempt_time_idx
  on public.employee_access_code_login_attempts (attempted_at);

alter table public.employee_access_code_login_attempts enable row level security;
revoke all on public.employee_access_code_login_attempts from public, anon, authenticated;
grant all on public.employee_access_code_login_attempts to service_role;

comment on column public.employees.access_code_set_at is
  'Timestamp when the owner last set an employee access code through the trusted Supabase Edge Function. The code itself is stored only as a Supabase Auth password hash.';
comment on column public.employees.access_code_updated_by is
  'Employee id of the owner who last changed or revoked this employee access code.';

commit;
