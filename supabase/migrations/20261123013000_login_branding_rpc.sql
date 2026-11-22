begin;

-- The login screen is shown before a Supabase session exists. Return only the
-- public branding for the organization identified by the employee number;
-- never return employee, membership, or authentication data.
create or replace function public.get_login_branding(p_employee_no text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'name', o.name,
    'tagline', coalesce(o.settings #>> '{branding,tagline}', 'معًا .. نحو إدارة أفضل'),
    'logo_url', nullif(o.settings #>> '{branding,logo_url}', '')
  )
  from public.organization_memberships m
  join public.organizations o on o.id = m.organization_id
  where m.employee_no = trim(p_employee_no)
    and m.is_active
    and o.is_active
  limit 1;
$$;

revoke all on function public.get_login_branding(text) from public;
grant execute on function public.get_login_branding(text) to anon, authenticated;

commit;
