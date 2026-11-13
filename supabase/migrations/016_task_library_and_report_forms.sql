begin;

-- تصنيف الوظائف وربط الموظف بها دون تغيير الموظفين الحاليين.
create table if not exists public.job_titles (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  code text not null check (code ~ '^[a-z0-9][a-z0-9_-]{1,63}$'),
  name_ar text not null check (length(trim(name_ar)) >= 2),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id)
);

alter table public.employees add column if not exists job_title_id uuid;

do $$ begin
  alter table public.employees
    add constraint employees_job_title_fk
    foreign key (institution_id, job_title_id)
    references public.job_titles(institution_id, id);
exception when duplicate_object then null;
end $$;

-- مستوى الفرع 1/2/3 مع علاقة اختيارية بالأب؛ القيم الحالية تبقى كما هي بالمستوى 1.
alter table public.branches add column if not exists branch_level smallint not null default 1;
alter table public.branches add column if not exists parent_branch_id uuid;
alter table public.branches drop constraint if exists branches_branch_level_check;
alter table public.branches add constraint branches_branch_level_check check (branch_level between 1 and 3);

do $$ begin
  alter table public.branches
    add constraint branches_parent_fk
    foreign key (institution_id, parent_branch_id)
    references public.branches(institution_id, id);
exception when duplicate_object then null;
end $$;

-- منشئ التقرير المرئي؛ تعديل الحقول يتم من لوحة الإدارة لا من الكود.
create table if not exists public.report_forms (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  code text not null check (code ~ '^[a-z0-9][a-z0-9_-]{1,63}$'),
  name_ar text not null check (length(trim(name_ar)) >= 2),
  description text,
  version integer not null default 1 check (version > 0),
  is_active boolean not null default true,
  created_by uuid not null,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  foreign key (institution_id, updated_by) references public.employees(institution_id, id)
);

create table if not exists public.report_form_fields (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  form_id uuid not null,
  field_key text not null check (field_key ~ '^[a-zA-Z][a-zA-Z0-9_]{1,63}$'),
  label_ar text not null check (length(trim(label_ar)) >= 2),
  field_type text not null check (field_type in ('text', 'textarea', 'number', 'date', 'select', 'multiselect', 'checkbox', 'attachment')),
  is_required boolean not null default false,
  sort_order integer not null default 0 check (sort_order >= 0),
  options jsonb not null default '[]'::jsonb,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, form_id, field_key),
  unique (institution_id, id),
  foreign key (institution_id, form_id) references public.report_forms(institution_id, id) on delete cascade,
  check (jsonb_typeof(options) = 'array'),
  check (jsonb_typeof(config) = 'object')
);

-- مكتبة المهام: القالب لا ينشئ مهمة تنفيذية بذاته حتى يحوله مسؤول المتابعة.
create table if not exists public.task_library_templates (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  code text not null check (code ~ '^[a-z0-9][a-z0-9_-]{1,63}$'),
  title text not null check (length(trim(title)) >= 2),
  description text,
  task_type text not null default 'general' check (length(trim(task_type)) >= 2),
  job_title_id uuid,
  recurrence public.recurrence_type,
  week_day smallint,
  month_day smallint,
  default_duration_minutes integer check (default_duration_minutes is null or default_duration_minutes between 1 and 10080),
  report_form_id uuid,
  version integer not null default 1 check (version > 0),
  is_active boolean not null default true,
  created_by uuid not null,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id),
  foreign key (institution_id, job_title_id) references public.job_titles(institution_id, id),
  foreign key (institution_id, report_form_id) references public.report_forms(institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  foreign key (institution_id, updated_by) references public.employees(institution_id, id),
  check ((recurrence = 'weekly' and week_day between 1 and 7) or recurrence <> 'weekly' or recurrence is null),
  check ((recurrence = 'monthly' and month_day between 1 and 31) or recurrence <> 'monthly' or recurrence is null)
);

create table if not exists public.task_library_branches (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  template_id uuid not null,
  branch_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (institution_id, template_id, branch_id),
  foreign key (institution_id, template_id) references public.task_library_templates(institution_id, id) on delete cascade,
  foreign key (institution_id, branch_id) references public.branches(institution_id, id) on delete cascade
);

create table if not exists public.task_library_employees (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  template_id uuid not null,
  employee_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (institution_id, template_id, employee_id),
  foreign key (institution_id, template_id) references public.task_library_templates(institution_id, id) on delete cascade,
  foreign key (institution_id, employee_id) references public.employees(institution_id, id) on delete cascade
);

-- ربط المهمة التنفيذية بمصدرها مع الاحتفاظ بلقطة report_schema الحالية.
alter table public.tasks add column if not exists library_template_id uuid;
alter table public.tasks add column if not exists library_template_version integer;
do $$ begin
  alter table public.tasks
    add constraint tasks_library_template_fk
    foreign key (institution_id, library_template_id)
    references public.task_library_templates(institution_id, id);
exception when duplicate_object then null;
end $$;

-- استيراد Excel/CSV على مرحلتين: مسودة، ثم مراجعة، ثم اعتماد.
create table if not exists public.task_library_import_batches (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  source_filename text not null,
  source_type text not null check (source_type in ('csv', 'xlsx', 'xls')),
  status text not null default 'draft' check (status in ('draft', 'reviewed', 'imported', 'cancelled')),
  total_rows integer not null default 0 check (total_rows >= 0),
  valid_rows integer not null default 0 check (valid_rows >= 0),
  invalid_rows integer not null default 0 check (invalid_rows >= 0),
  created_by uuid not null,
  reviewed_by uuid,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  foreign key (institution_id, reviewed_by) references public.employees(institution_id, id)
);

create table if not exists public.task_library_import_rows (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  batch_id uuid not null,
  row_number integer not null check (row_number > 0),
  raw_data jsonb not null,
  normalized_data jsonb,
  validation_errors jsonb not null default '[]'::jsonb,
  source_template_id uuid,
  created_at timestamptz not null default now(),
  unique (institution_id, batch_id, row_number),
  foreign key (institution_id, batch_id) references public.task_library_import_batches(institution_id, id) on delete cascade,
  foreign key (institution_id, source_template_id) references public.task_library_templates(institution_id, id),
  check (jsonb_typeof(raw_data) = 'object'),
  check (jsonb_typeof(validation_errors) = 'array')
);

-- حقول التقرير الإضافية المطلوبة للتقارير التشغيلية الحالية.
alter table public.task_reports add column if not exists branch_id uuid;
alter table public.task_reports add column if not exists execution_date date;
do $$ begin
  alter table public.task_reports
    add constraint task_reports_branch_fk
    foreign key (institution_id, branch_id)
    references public.branches(institution_id, id);
exception when duplicate_object then null;
end $$;

-- السماح بتخزين صور ومستندات التقرير عبر جدول المرفقات الحالي.
alter table public.attachments drop constraint if exists attachments_entity_type_check;
alter table public.attachments
  add constraint attachments_entity_type_check check (entity_type in ('task', 'task_evidence', 'task_report', 'invoice', 'stocktake', 'audit'));

create index if not exists task_library_templates_filter_idx
  on public.task_library_templates (institution_id, is_active, task_type, recurrence, job_title_id);
create index if not exists task_library_branches_branch_idx
  on public.task_library_branches (institution_id, branch_id, template_id);
create index if not exists task_library_employees_employee_idx
  on public.task_library_employees (institution_id, employee_id, template_id);
create index if not exists report_form_fields_order_idx
  on public.report_form_fields (institution_id, form_id, sort_order);
create index if not exists task_library_import_rows_batch_idx
  on public.task_library_import_rows (institution_id, batch_id, row_number);

create trigger job_titles_set_updated_at before update on public.job_titles
for each row execute function app.set_updated_at();
create trigger report_forms_set_updated_at before update on public.report_forms
for each row execute function app.set_updated_at();
create trigger report_form_fields_set_updated_at before update on public.report_form_fields
for each row execute function app.set_updated_at();
create trigger task_library_templates_set_updated_at before update on public.task_library_templates
for each row execute function app.set_updated_at();

-- RLS جديدة: لا تمنح الموظفين صلاحية قراءة مكتبة المؤسسة أو نماذجها إلا عبر tasks.read.
alter table public.job_titles enable row level security;
alter table public.report_forms enable row level security;
alter table public.report_form_fields enable row level security;
alter table public.task_library_templates enable row level security;
alter table public.task_library_branches enable row level security;
alter table public.task_library_employees enable row level security;
alter table public.task_library_import_batches enable row level security;
alter table public.task_library_import_rows enable row level security;

create policy job_titles_read on public.job_titles for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('tasks.read'));
create policy job_titles_manage on public.job_titles for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('task_library.manage'));

create policy report_forms_read on public.report_forms for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('tasks.read'));
create policy report_forms_manage on public.report_forms for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('report_forms.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('report_forms.manage'));
create policy report_form_fields_read on public.report_form_fields for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('tasks.read'));
create policy report_form_fields_manage on public.report_form_fields for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('report_forms.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('report_forms.manage'));

create policy task_library_templates_read on public.task_library_templates for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.read'));
create policy task_library_templates_manage on public.task_library_templates for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('task_library.manage'));
create policy task_library_branches_read on public.task_library_branches for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.read'));
create policy task_library_branches_manage on public.task_library_branches for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('task_library.manage'));
create policy task_library_employees_read on public.task_library_employees for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.read'));
create policy task_library_employees_manage on public.task_library_employees for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('task_library.manage'));

create policy task_library_import_batches_read on public.task_library_import_batches for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.read'));
create policy task_library_import_batches_manage on public.task_library_import_batches for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.import'))
with check (institution_id = app.current_institution_id() and app.has_permission('task_library.import'));
create policy task_library_import_rows_read on public.task_library_import_rows for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.read'));
create policy task_library_import_rows_manage on public.task_library_import_rows for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('task_library.import'))
with check (institution_id = app.current_institution_id() and app.has_permission('task_library.import'));


-- صلاحيات النظام اللازمة للمكتبة ومنشئ النماذج؛ لا تنشئ أي قالب أو موظف.
insert into public.permissions (code, name_ar, domain, action, description) values
  ('task_library.read', 'قراءة مكتبة المهام', 'task_library', 'read', 'عرض قوالب المهام وتصنيفاتها'),
  ('task_library.manage', 'إدارة مكتبة المهام', 'task_library', 'manage', 'إضافة وتعديل وأرشفة قوالب المهام'),
  ('task_library.import', 'استيراد مكتبة المهام', 'task_library', 'import', 'رفع ملفات Excel وCSV ومراجعة صفوفها'),
  ('task_library.convert', 'تحويل قالب إلى مهمة', 'task_library', 'convert', 'إنشاء مهمة فعلية من قالب المكتبة'),
  ('report_forms.manage', 'إدارة نماذج التقارير', 'reports', 'manage', 'إنشاء وتعديل حقول نماذج التقارير'),
  ('reports.read_all', 'قراءة تقارير الرقابة', 'reports', 'read_all', 'عرض تقارير الموظفين والتنبيهات والمراجعات')
on conflict (code) do update set name_ar = excluded.name_ar, domain = excluded.domain, action = excluded.action, description = excluded.description;

insert into public.role_permissions (institution_id, role_id, permission_code)
select r.institution_id, r.id, p.code
from public.roles r
cross join public.permissions p
where r.code = 'owner'
  and p.code in ('task_library.read', 'task_library.manage', 'task_library.import', 'task_library.convert', 'report_forms.manage', 'reports.read_all')
on conflict do nothing;

insert into public.role_permissions (institution_id, role_id, permission_code)
select r.institution_id, r.id, p.code
from public.roles r
join public.permissions p on p.code in ('task_library.read', 'task_library.manage', 'task_library.import', 'task_library.convert', 'report_forms.manage', 'reports.read_all')
where r.code = 'admin_followup'
on conflict do nothing;

commit;
