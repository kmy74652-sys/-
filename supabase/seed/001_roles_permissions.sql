insert into public.permissions (code, name_ar, domain, action, description) values
  ('institutions.update', 'تعديل إعدادات المؤسسة', 'institutions', 'update', 'تعديل إعدادات المؤسسة العامة'),
  ('branches.read_all', 'عرض جميع الفروع', 'branches', 'read_all', 'الوصول إلى بيانات جميع الفروع'),
  ('branches.manage', 'إدارة الفروع', 'branches', 'manage', 'إنشاء وتعديل وأرشفة الفروع'),
  ('employees.read', 'عرض الموظفين', 'employees', 'read', 'عرض ملفات الموظفين ضمن النطاق'),
  ('employees.manage', 'إدارة الموظفين', 'employees', 'manage', 'إنشاء وتعديل وإيقاف الموظفين'),
  ('roles.read', 'عرض الأدوار والصلاحيات', 'roles', 'read', 'عرض الأدوار والصلاحيات'),
  ('roles.manage', 'إدارة الأدوار والصلاحيات', 'roles', 'manage', 'تعديل الأدوار وربط الصلاحيات'),
  ('tasks.read', 'عرض المهام', 'tasks', 'read', 'عرض المهام والتحديثات'),
  ('tasks.read_all', 'عرض جميع المهام', 'tasks', 'read_all', 'عرض مهام جميع الموظفين والفروع'),
  ('tasks.manage', 'إدارة المهام', 'tasks', 'manage', 'إنشاء وتوزيع ومتابعة المهام'),
  ('tasks.review', 'مراجعة واعتماد المهام', 'tasks', 'review', 'مراجعة تقرير الإنجاز واعتماده أو إرجاعه'),
  ('customers.read', 'عرض العملاء', 'customers', 'read', 'الوصول إلى العملاء وكشوفهم'),
  ('customers.manage', 'إدارة العملاء', 'customers', 'manage', 'إنشاء وتعديل العملاء'),
  ('credit_limits.propose', 'اقتراح حدود ائتمانية', 'credit_limits', 'propose', 'اقتراح حد ائتماني'),
  ('credit_limits.approve', 'اعتماد حدود ائتمانية', 'credit_limits', 'approve', 'اعتماد حد ائتماني'),
  ('finance.read', 'عرض البيانات المالية', 'finance', 'read', 'عرض القيود والسندات'),
  ('finance.receipts.create', 'إنشاء سند قبض', 'finance', 'receipts_create', 'إنشاء سند قبض'),
  ('finance.receipts.approve', 'اعتماد سند قبض', 'finance', 'receipts_approve', 'اعتماد سند قبض'),
  ('finance.payments.create', 'إنشاء سند سداد', 'finance', 'payments_create', 'إنشاء سند سداد'),
  ('finance.payments.approve', 'اعتماد سند سداد', 'finance', 'payments_approve', 'اعتماد سند سداد'),
  ('audit.read', 'عرض سجل التدقيق', 'audit', 'read', 'قراءة سجل التدقيق'),
  ('audit.write', 'إضافة سجل تدقيق', 'audit', 'write', 'إضافة أحداث تدقيق'),
  ('notifications.read_all', 'عرض إشعارات الجميع', 'notifications', 'read_all', 'عرض الإشعارات الإدارية'),
  ('attachments.read', 'عرض المرفقات', 'attachments', 'read', 'عرض المرفقات المصرح بها')
on conflict (code) do update set name_ar = excluded.name_ar, domain = excluded.domain, action = excluded.action, description = excluded.description;

create or replace function app.seed_institution_defaults(target_institution_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  owner_role uuid;
  followup_role uuid;
  accountant_role uuid;
  warehouse_keeper_role uuid;
  warehouse_worker_role uuid;
begin
  if not exists (select 1 from public.institutions where id = target_institution_id) then
    raise exception 'institution_not_found';
  end if;

  insert into public.roles (institution_id, code, name_ar, description) values
    (target_institution_id, 'owner', 'صاحب المؤسسة', 'تحكم كامل وإشراف واعتماد نهائي'),
    (target_institution_id, 'admin_followup', 'مسؤول المتابعة الإدارية والتنفيذية', 'إدارة ومراجعة المهام والتقارير التشغيلية'),
    (target_institution_id, 'accountant', 'المحاسب', 'الحسابات والعملاء والموردون والتحصيل والمبيعات'),
    (target_institution_id, 'warehouse_keeper', 'أمين المخزن', 'إدارة المخزون والاستلام والصرف والجرد'),
    (target_institution_id, 'warehouse_worker', 'عامل المخزن', 'تنفيذ التحميل والتنزيل وتجهيز الطلبات')
  on conflict (institution_id, code) do update set name_ar = excluded.name_ar, description = excluded.description;

  select id into owner_role from public.roles where institution_id = target_institution_id and code = 'owner';
  select id into followup_role from public.roles where institution_id = target_institution_id and code = 'admin_followup';
  select id into accountant_role from public.roles where institution_id = target_institution_id and code = 'accountant';
  select id into warehouse_keeper_role from public.roles where institution_id = target_institution_id and code = 'warehouse_keeper';
  select id into warehouse_worker_role from public.roles where institution_id = target_institution_id and code = 'warehouse_worker';

  insert into public.role_permissions (institution_id, role_id, permission_code)
    select target_institution_id, owner_role, p.code from public.permissions p
  on conflict do nothing;

  insert into public.role_permissions (institution_id, role_id, permission_code)
    select target_institution_id, followup_role, p.code from public.permissions p
    where p.code in ('branches.read_all', 'employees.read', 'tasks.read', 'tasks.read_all', 'tasks.manage', 'tasks.review', 'audit.read', 'attachments.read', 'notifications.read_all')
  on conflict do nothing;

  insert into public.role_permissions (institution_id, role_id, permission_code)
    select target_institution_id, accountant_role, p.code from public.permissions p
    where p.code in ('branches.read_all', 'employees.read', 'tasks.read', 'customers.read', 'customers.manage', 'credit_limits.propose', 'finance.read', 'finance.receipts.create', 'finance.payments.create', 'audit.read', 'attachments.read')
  on conflict do nothing;

  insert into public.role_permissions (institution_id, role_id, permission_code)
    select target_institution_id, warehouse_keeper_role, p.code from public.permissions p
    where p.code in ('branches.read_all', 'employees.read', 'tasks.read', 'tasks.read_all', 'audit.read', 'attachments.read')
  on conflict do nothing;

  insert into public.role_permissions (institution_id, role_id, permission_code)
    select target_institution_id, warehouse_worker_role, p.code from public.permissions p
    where p.code in ('tasks.read', 'attachments.read')
  on conflict do nothing;
end;
$$;

revoke all on function app.seed_institution_defaults(uuid) from public, anon, authenticated;
grant execute on function app.seed_institution_defaults(uuid) to service_role;
