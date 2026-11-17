-- Allow only the institution owner role to edit institution identity settings.
insert into public.permissions (code, name_ar, domain, action, description)
values (
  'institutions.update',
  'تعديل هوية المؤسسة',
  'institutions',
  'update',
  'تعديل اسم المؤسسة وشعارها وعبارتها التعريفية'
)
on conflict (code) do update
set name_ar = excluded.name_ar,
    domain = excluded.domain,
    action = excluded.action,
    description = excluded.description;

insert into public.role_permissions (institution_id, role_id, permission_code)
select r.institution_id, r.id, 'institutions.update'
from public.roles r
where r.code = 'owner'
on conflict (institution_id, role_id, permission_code) do nothing;
