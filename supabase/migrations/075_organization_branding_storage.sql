begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('organization-branding', 'organization-branding', true, 5242880, array['image/jpeg','image/png','image/webp']::text[])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists organization_branding_read on storage.objects;
create policy organization_branding_read on storage.objects
for select to public
using (bucket_id = 'organization-branding');

drop policy if exists organization_branding_insert on storage.objects;
create policy organization_branding_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'organization-branding'
  and split_part(name, '/', 1) <> ''
  and alshaari_private.has_permission(split_part(name, '/', 1)::uuid, 'employees.manage', null::uuid)
);

drop policy if exists organization_branding_update on storage.objects;
create policy organization_branding_update on storage.objects
for update to authenticated
using (
  bucket_id = 'organization-branding'
  and alshaari_private.has_permission(split_part(name, '/', 1)::uuid, 'employees.manage', null::uuid)
)
with check (
  bucket_id = 'organization-branding'
  and alshaari_private.has_permission(split_part(name, '/', 1)::uuid, 'employees.manage', null::uuid)
);

drop policy if exists organization_branding_delete on storage.objects;
create policy organization_branding_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'organization-branding'
  and alshaari_private.has_permission(split_part(name, '/', 1)::uuid, 'employees.manage', null::uuid)
);

commit;
