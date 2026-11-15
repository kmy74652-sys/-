begin;

-- Make the report workflow columns explicit and idempotent for every environment.
alter table public.task_reports add column if not exists status text not null default 'submitted';
alter table public.task_reports add column if not exists progress_percent numeric;
alter table public.task_reports add column if not exists notes text;
alter table public.task_reports add column if not exists submitted_at timestamptz not null default now();
alter table public.task_reports add column if not exists reviewed_by uuid;
alter table public.task_reports add column if not exists reviewed_at timestamptz;
alter table public.task_reports add column if not exists review_action text;
alter table public.task_reports add column if not exists review_note text;
alter table public.task_reports add column if not exists updated_at timestamptz not null default now();

alter table public.task_reports drop constraint if exists task_reports_status_check;
alter table public.task_reports add constraint task_reports_status_check check (status in ('submitted', 'returned', 'approved'));
alter table public.task_reports drop constraint if exists task_reports_progress_percent_check;
alter table public.task_reports add constraint task_reports_progress_percent_check check (progress_percent is null or (progress_percent >= 0 and progress_percent <= 100));

-- Modern task activity log used by the mobile workflow functions.
create table if not exists public.task_activity_log (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null check (length(trim(action)) >= 2),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (jsonb_typeof(details) = 'object')
);

create index if not exists task_activity_log_task_date_idx
  on public.task_activity_log (task_id, created_at desc);

create or replace function public.prevent_task_activity_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception using errcode = '42501', message = 'task_activity_log_append_only';
end;
$$;

drop trigger if exists task_activity_log_no_update on public.task_activity_log;
create trigger task_activity_log_no_update
before update or delete on public.task_activity_log
for each row execute function public.prevent_task_activity_mutation();

alter table public.task_activity_log enable row level security;
drop policy if exists task_activity_log_read on public.task_activity_log;
create policy task_activity_log_read on public.task_activity_log for select to authenticated
using (
  exists (
    select 1 from public.tasks t
    where t.id = task_activity_log.task_id
      and (
        t.assigned_to = auth.uid()
        or t.created_by = auth.uid()
        or exists (
          select 1
          from public.organization_memberships m
          join public.role_assignments ra
            on ra.organization_id = m.organization_id
           and ra.membership_id = m.id
          where m.user_id = auth.uid()
            and m.is_active
            and ra.role_code in ('owner', 'admin_followup')
        )
      )
  )
);

-- Review metadata references the authenticated reviewer.
do $$ begin
  alter table public.task_reports
    add constraint task_reports_reviewed_by_fk
    foreign key (reviewed_by) references auth.users(id) on delete set null;
exception when duplicate_object then null;
end $$;

commit;
