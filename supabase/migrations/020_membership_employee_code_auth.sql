begin;

alter table public.organization_memberships
  add column if not exists employee_no text,
  add column if not exists access_code_set_at timestamptz,
  add column if not exists access_code_updated_by uuid;

create unique index if not exists organization_memberships_employee_no_unique
  on public.organization_memberships (employee_no)
  where employee_no is not null;

alter table public.organization_memberships
  drop constraint if exists organization_memberships_access_code_updated_by_fkey;
alter table public.organization_memberships
  add constraint organization_memberships_access_code_updated_by_fkey
  foreign key (access_code_updated_by)
  references public.organization_memberships(id)
  on delete set null;

-- Assign employee number 1 only to the verified, explicitly designated owner account.
do $$
declare
  matched_count integer;
begin
  select count(*) into matched_count
  from public.organization_memberships m
  join auth.users u on u.id = m.user_id
  join public.role_assignments ra
    on ra.organization_id = m.organization_id
   and ra.membership_id = m.id
   and ra.role_code = 'owner'
  where lower(u.email) = 'als43870@gmail.com'
    and m.is_active;

  if matched_count <> 1 then
    raise exception 'expected_exactly_one_active_owner_membership_for_designated_account';
  end if;

  update public.organization_memberships m
  set employee_no = '1'
  from auth.users u
  where u.id = m.user_id
    and lower(u.email) = 'als43870@gmail.com'
    and m.is_active
    and exists (
      select 1 from public.role_assignments ra
      where ra.organization_id = m.organization_id
        and ra.membership_id = m.id
        and ra.role_code = 'owner'
    );
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

create table if not exists public.employee_access_code_bootstrap_tokens (
  token_hash text primary key,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.employee_access_code_login_attempts enable row level security;
alter table public.employee_access_code_bootstrap_tokens enable row level security;
revoke all on public.employee_access_code_login_attempts from public, anon, authenticated;
revoke all on public.employee_access_code_bootstrap_tokens from public, anon, authenticated;
grant all on public.employee_access_code_login_attempts to service_role;
grant all on public.employee_access_code_bootstrap_tokens to service_role;

create or replace function public.mobile_my_profile()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
  select jsonb_build_object(
    'employee', jsonb_build_object(
      'id', m.id,
      'institutionId', m.organization_id,
      'employeeNo', m.employee_no,
      'fullName', m.display_name,
      'email', u.email,
      'phone', u.phone,
      'status', case when m.is_active then 'active' else 'inactive' end,
      'lastLoginAt', u.last_sign_in_at,
      'roles', coalesce((
        select jsonb_agg(jsonb_build_object('code', r.code, 'nameAr', r.name_ar) order by r.name_ar)
        from public.role_assignments ra
        join public.roles r on r.code = ra.role_code
        where ra.organization_id = m.organization_id and ra.membership_id = m.id
      ), '[]'::jsonb),
      'permissions', coalesce((
        select jsonb_agg(distinct rp.permission_code order by rp.permission_code)
        from public.role_assignments ra
        join public.role_permissions rp on rp.role_code = ra.role_code
        where ra.organization_id = m.organization_id and ra.membership_id = m.id
      ), '[]'::jsonb),
      'branches', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', b.id, 'code', b.code, 'name', b.name, 'isDefault', false
        ) order by b.name)
        from public.role_assignments ra
        join public.branches b
          on b.organization_id = ra.organization_id and b.id = ra.branch_id
        where ra.organization_id = m.organization_id and ra.membership_id = m.id
      ), '[]'::jsonb)
    )
  )
  from public.organization_memberships m
  join auth.users u on u.id = m.user_id
  where m.user_id = auth.uid() and m.is_active
  order by m.created_at
  limit 1;
$$;

revoke all on function public.mobile_my_profile() from public, anon;
grant execute on function public.mobile_my_profile() to authenticated;

create or replace function public.claim_employee_access_code_bootstrap(p_token_hash text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed boolean := false;
begin
  update public.employee_access_code_bootstrap_tokens
  set consumed_at = now()
  where token_hash = p_token_hash
    and consumed_at is null
    and expires_at > now()
  returning true into claimed;
  return coalesce(claimed, false);
end;
$$;
revoke all on function public.claim_employee_access_code_bootstrap(text) from public, anon, authenticated;
grant execute on function public.claim_employee_access_code_bootstrap(text) to service_role;

commit;
