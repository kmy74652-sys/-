create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid,
  created_by uuid not null,
  assignee_employee_id uuid not null,
  title text not null check (length(trim(title)) >= 2),
  description text,
  starts_at timestamptz not null,
  due_at timestamptz not null,
  priority public.task_priority not null default 'normal',
  status public.task_status not null default 'pending',
  proof_required boolean not null default false,
  proof_instructions text,
  recurring_template_id uuid,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (due_at >= starts_at),
  unique (institution_id, idempotency_key),
  unique (institution_id, id)
);

create table if not exists public.task_updates (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  task_id uuid not null,
  author_employee_id uuid not null,
  status public.task_status,
  note text,
  created_at timestamptz not null default now(),
  foreign key (institution_id, task_id) references public.tasks(institution_id, id) on delete cascade,
  foreign key (institution_id, author_employee_id) references public.employees(institution_id, id)
);

create table if not exists public.task_reviews (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  task_id uuid not null,
  reviewer_employee_id uuid not null,
  decision public.task_status not null check (decision in ('approved', 'rejected')),
  note text,
  created_at timestamptz not null default now(),
  foreign key (institution_id, task_id) references public.tasks(institution_id, id) on delete cascade,
  foreign key (institution_id, reviewer_employee_id) references public.employees(institution_id, id)
);

create table if not exists public.recurring_task_templates (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid,
  created_by uuid not null,
  assignee_employee_id uuid not null,
  title text not null check (length(trim(title)) >= 2),
  description text,
  recurrence public.recurrence_type not null,
  week_day smallint check (week_day between 1 and 7),
  month_day smallint check (month_day between 1 and 31),
  starts_on date not null,
  ends_on date,
  is_active boolean not null default true,
  last_generated_for date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on),
  check ((recurrence = 'weekly' and week_day is not null) or recurrence <> 'weekly'),
  check ((recurrence = 'monthly' and month_day is not null) or recurrence <> 'monthly'),
  unique (institution_id, id)
);

alter table public.tasks
  add constraint tasks_branch_fk foreign key (institution_id, branch_id)
  references public.branches(institution_id, id);
alter table public.tasks
  add constraint tasks_creator_fk foreign key (institution_id, created_by)
  references public.employees(institution_id, id);
alter table public.tasks
  add constraint tasks_assignee_fk foreign key (institution_id, assignee_employee_id)
  references public.employees(institution_id, id);
alter table public.tasks
  add constraint tasks_template_fk foreign key (institution_id, recurring_template_id)
  references public.recurring_task_templates(institution_id, id);
alter table public.recurring_task_templates
  add constraint recurring_tasks_branch_fk foreign key (institution_id, branch_id)
  references public.branches(institution_id, id);
alter table public.recurring_task_templates
  add constraint recurring_tasks_creator_fk foreign key (institution_id, created_by)
  references public.employees(institution_id, id);
alter table public.recurring_task_templates
  add constraint recurring_tasks_assignee_fk foreign key (institution_id, assignee_employee_id)
  references public.employees(institution_id, id);

create table if not exists public.task_runs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  template_id uuid not null,
  scheduled_for date not null,
  status text not null check (status in ('started', 'completed', 'failed', 'skipped')),
  error_message text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (institution_id, template_id, scheduled_for),
  foreign key (institution_id, template_id) references public.recurring_task_templates(institution_id, id) on delete cascade
);

create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  uploaded_by uuid not null,
  entity_type text not null check (entity_type in ('task', 'task_evidence', 'invoice', 'stocktake', 'audit')),
  entity_id uuid not null,
  object_key text not null,
  stable_url text not null,
  original_name text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size > 0),
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  foreign key (institution_id, uploaded_by) references public.employees(institution_id, id),
  unique (institution_id, object_key)
);

create trigger tasks_set_updated_at before update on public.tasks
for each row execute function app.set_updated_at();
create trigger recurring_task_templates_set_updated_at before update on public.recurring_task_templates
for each row execute function app.set_updated_at();
