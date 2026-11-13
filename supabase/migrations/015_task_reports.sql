begin;

alter table public.tasks
  add column if not exists report_schema jsonb not null default '[]'::jsonb;

alter table public.tasks
  drop constraint if exists tasks_report_schema_array_check;
alter table public.tasks
  add constraint tasks_report_schema_array_check check (jsonb_typeof(report_schema) = 'array');

create table if not exists public.task_reports (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  task_id uuid not null,
  submitted_by uuid not null,
  values jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (institution_id, task_id) references public.tasks(institution_id, id) on delete cascade,
  foreign key (institution_id, submitted_by) references public.employees(institution_id, id),
  check (jsonb_typeof(values) = 'object'),
  unique (institution_id, id)
);

create index if not exists task_reports_task_date_idx
  on public.task_reports (institution_id, task_id, created_at desc);

alter table public.task_reports enable row level security;

drop policy if exists task_reports_select on public.task_reports;
create policy task_reports_select on public.task_reports for select to authenticated
using (
  institution_id = app.current_institution_id()
  and exists (
    select 1 from public.tasks t
    where t.institution_id = task_reports.institution_id
      and t.id = task_reports.task_id
      and (t.assignee_employee_id = app.current_employee_id()
        or t.created_by = app.current_employee_id()
        or app.has_permission('tasks.read_all'))
  )
);

drop policy if exists task_reports_insert on public.task_reports;
create policy task_reports_insert on public.task_reports for insert to authenticated
with check (
  institution_id = app.current_institution_id()
  and submitted_by = app.current_employee_id()
  and exists (
    select 1 from public.tasks t
    where t.institution_id = task_reports.institution_id
      and t.id = task_reports.task_id
      and t.assignee_employee_id = app.current_employee_id()
      and t.status in ('in_progress', 'rejected')
  )
);

create or replace function app.record_task_update(
  p_task_id uuid,
  p_author_employee_id uuid,
  p_status public.task_status,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  current_task public.tasks%rowtype;
begin
  select * into current_task from public.tasks where id = p_task_id for update;
  if not found then raise exception 'task_not_found'; end if;
  if current_task.assignee_employee_id <> p_author_employee_id and current_task.created_by <> p_author_employee_id then raise exception 'task_actor_not_allowed'; end if;
  if p_status not in ('pending', 'in_progress', 'submitted', 'rejected') then raise exception 'invalid_progress_status'; end if;
  if p_status = 'submitted' and not exists (select 1 from public.task_reports r where r.institution_id = current_task.institution_id and r.task_id = p_task_id) then raise exception 'task_report_required'; end if;
  if p_status = 'submitted' and current_task.proof_required and not exists (select 1 from public.attachments a where a.institution_id = current_task.institution_id and a.entity_type = 'task_evidence' and a.entity_id = p_task_id and not a.is_deleted) then raise exception 'task_proof_required'; end if;
  if p_status = 'submitted' and current_task.status not in ('in_progress', 'rejected') then raise exception 'task_must_be_in_progress'; end if;
  if p_status = 'in_progress' and current_task.status not in ('pending', 'in_progress', 'rejected') then raise exception 'invalid_progress_transition'; end if;
  if p_status = 'rejected' then raise exception 'rejected_is_review_decision'; end if;
  insert into public.task_updates (institution_id, task_id, author_employee_id, status, note)
  values (current_task.institution_id, p_task_id, p_author_employee_id, p_status, nullif(trim(p_note), ''));
  update public.tasks set status = p_status where id = p_task_id;
  return p_task_id;
end;
$$;

revoke all on function app.record_task_update(uuid, uuid, public.task_status, text) from public, anon, authenticated;
grant execute on function app.record_task_update(uuid, uuid, public.task_status, text) to service_role;

commit;
