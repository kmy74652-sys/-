-- Store organization branding in the live organizations schema.
-- The current production model uses organizations/role_code, not institutions/role_id.
alter table public.organizations
  add column if not exists settings jsonb not null default '{}'::jsonb;

insert into public.permissions (code, name_ar)
values (
  'organizations.update',
  'تعديل هوية المؤسسة'
)
on conflict (code) do update
set name_ar = excluded.name_ar;

insert into public.role_permissions (role_code, permission_code)
values ('owner', 'organizations.update')
on conflict (role_code, permission_code) do nothing;

grant update (name, settings) on public.organizations to authenticated;

drop policy if exists organizations_update_owner on public.organizations;
create policy organizations_update_owner
  on public.organizations
  for update
  to authenticated
  using (alshaari_private.has_permission(id, 'organizations.update', null::uuid))
  with check (alshaari_private.has_permission(id, 'organizations.update', null::uuid));

-- These functions are trigger-only, or an unused legacy permission probe.
-- Keep trigger execution intact while removing direct API execution grants.
revoke execute on function public.guard_multi_form_task_completion() from public, anon, authenticated;
revoke execute on function public.guard_report_signature_mutation() from public, anon, authenticated;
revoke execute on function public.guard_task_report_snapshot_and_signature() from public, anon, authenticated;
revoke execute on function public.report_designer_allowed(uuid) from public, anon, authenticated;

-- Pin the non-definer activity guard's lookup path for predictable resolution.
alter function public.prevent_task_activity_mutation() set search_path = pg_catalog, public;

-- Remove the legacy organization-claim policy. It is permissive alongside
-- tasks_select_assigned_or_manager and could expose every task in an org
-- if an organization_id app_metadata claim is ever added to employee JWTs.
drop policy if exists tasks_read on public.tasks;
