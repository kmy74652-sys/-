-- Restore the permission helper required by task RPCs.
-- This matches the production authorization model and changes no tables,
-- role assignments, permissions, or RLS policies.
create or replace function public.has_org_permission(
  p_organization_id uuid,
  p_permission text,
  p_branch_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.organization_memberships m
      join public.role_assignments ra
        on ra.organization_id = m.organization_id
       and ra.membership_id = m.id
      join public.role_permissions rp
        on rp.role_code = ra.role_code
       and rp.permission_code = p_permission
      where m.organization_id = p_organization_id
        and m.user_id = auth.uid()
        and m.is_active = true
        and (p_branch_id is null or ra.branch_id = p_branch_id)
    );
$$;

revoke all on function public.has_org_permission(uuid, text, uuid)
from public, anon, authenticated;
grant execute on function public.has_org_permission(uuid, text, uuid)
to authenticated;
