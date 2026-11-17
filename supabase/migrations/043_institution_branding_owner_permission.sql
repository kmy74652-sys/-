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
