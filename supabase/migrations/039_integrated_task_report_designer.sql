begin;

create or replace function public.report_designer_allowed_for_org(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select auth.uid() is not null and exists (
    select 1
    from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
    join public.role_permissions rp on rp.role_code = ra.role_code
    where m.user_id = auth.uid()
      and m.organization_id = p_organization_id
      and m.is_active
      and rp.permission_code in ('report_forms.manage','task_library.manage')
  );
$$;

revoke all on function public.report_designer_allowed_for_org(uuid) from public, anon;
grant execute on function public.report_designer_allowed_for_org(uuid) to authenticated;

commit;
