begin;

create table if not exists public.task_report_attachments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  task_id uuid not null references public.tasks(id) on delete restrict,
  report_id uuid not null references public.task_reports(id) on delete restrict,
  uploaded_by uuid not null,
  storage_path text not null,
  file_name text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size > 0 and byte_size <= 20971520),
  created_at timestamptz not null default now(),
  unique (institution_id, storage_path)
);

create index if not exists task_report_attachments_task_idx
  on public.task_report_attachments (institution_id, task_id, created_at desc);

alter table public.task_report_attachments enable row level security;
drop policy if exists task_report_attachments_read on public.task_report_attachments;
create policy task_report_attachments_read on public.task_report_attachments
  for select to authenticated
  using (
    institution_id = app.current_institution_id()
    and (uploaded_by = app.current_employee_id() or app.has_permission('tasks.read_all'))
  );

drop policy if exists task_report_attachments_insert on public.task_report_attachments;
create policy task_report_attachments_insert on public.task_report_attachments
  for insert to authenticated
  with check (
    institution_id = app.current_institution_id()
    and uploaded_by = app.current_employee_id()
    and app.has_permission('tasks.read')
  );

insert into storage.buckets (id, name, public)
values ('task-reports', 'task-reports', false)
on conflict (id) do nothing;

create or replace function public.mobile_task_timeline(p_task_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, auth, app
as $$
declare result jsonb;
begin
  if auth.uid() is null or app.current_employee_id() is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id, 'status', l.status, 'note', l.note,
    'actor_name', coalesce(e.full_name, 'النظام'), 'created_at', l.created_at
  ) order by l.created_at asc), '[]'::jsonb)
  into result
  from public.task_activity_log l
  left join public.employees e on e.id = l.actor_employee_id and e.institution_id = l.institution_id
  where l.institution_id = app.current_institution_id()
    and l.task_id = p_task_id
    and (l.actor_employee_id = app.current_employee_id()
      or app.has_permission('tasks.read_all')
      or exists (select 1 from public.tasks t where t.id = l.task_id and t.assignee_employee_id = app.current_employee_id()));
  return result;
end;
$$;

revoke all on function public.mobile_task_timeline(uuid) from public, anon, authenticated;
grant execute on function public.mobile_task_timeline(uuid) to authenticated;


create table if not exists public.mobile_operation_receipts (
  institution_id uuid not null,
  operation_key text not null,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (institution_id, operation_key)
);
alter table public.mobile_operation_receipts enable row level security;

create or replace function public.mobile_record_task_update(
  p_task_id uuid, p_status public.task_status, p_note text default null, p_idempotency_key text default null
) returns uuid language plpgsql security definer set search_path = public, auth, app as $$
declare v_employee_id uuid; v_result uuid; v_key text := nullif(trim(p_idempotency_key), '');
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'not_authenticated'; end if;
  if v_key is not null then select (result->>'id')::uuid into v_result from public.mobile_operation_receipts where institution_id = app.current_institution_id() and operation_key = v_key; if v_result is not null then return v_result; end if; end if;
  v_employee_id := app.current_employee_id();
  if v_employee_id is null or not app.has_permission('tasks.read') then raise exception using errcode = '42501', message = 'permission_denied'; end if;
  v_result := app.record_task_update(p_task_id, v_employee_id, p_status, p_note);
  if v_key is not null then insert into public.mobile_operation_receipts(institution_id, operation_key, result) values (app.current_institution_id(), v_key, jsonb_build_object('id', v_result)) on conflict do nothing; end if;
  return v_result;
end; $$;

grant execute on function public.mobile_record_task_update(uuid, public.task_status, text, text) to authenticated;

create or replace function public.mobile_submit_task_report(
  p_task_id uuid, p_values jsonb, p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path = public, auth, app as $$
declare v_result jsonb; v_key text := nullif(trim(p_idempotency_key), '');
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'not_authenticated'; end if;
  if v_key is not null then select result into v_result from public.mobile_operation_receipts where institution_id = app.current_institution_id() and operation_key = v_key; if v_result is not null then return v_result; end if; end if;
  v_result := public.mobile_submit_task_report(p_task_id, p_values);
  if v_key is not null then insert into public.mobile_operation_receipts(institution_id, operation_key, result) values (app.current_institution_id(), v_key, v_result) on conflict do nothing; end if;
  return v_result;
end; $$;

grant execute on function public.mobile_submit_task_report(uuid, jsonb, text) to authenticated;

commit;
