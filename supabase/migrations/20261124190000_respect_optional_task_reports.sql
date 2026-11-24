-- Respect the administrator's report_required decision when an employee
-- submits a task for review. This changes no tables, columns, RLS, or grants.
create or replace function public.mobile_record_task_update(
  p_task_id uuid,
  p_status text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_task public.tasks%rowtype;
  v_next text;
  v_action text;
begin
  if auth.uid() is null then
    raise exception using errcode='28000', message='not_authenticated';
  end if;

  select * into v_task
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;

  if not found
     or (v_task.assigned_to <> auth.uid() and v_task.created_by <> auth.uid()) then
    raise exception using errcode='P0002', message='task_not_found';
  end if;
  if not public.has_org_permission(v_task.organization_id, 'tasks.read', null::uuid) then
    raise exception using errcode='42501', message='permission_denied';
  end if;

  if p_status = 'in_progress'
     and v_task.status in ('new', 'received', 'in_progress', 'needs_revision') then
    v_next := 'in_progress';
    v_action := 'started';
  elsif p_status in ('pending', 'received') then
    v_next := 'received';
    v_action := 'received';
  elsif p_status = 'submitted' then
    -- The administrator decides whether this task needs a report. Required
    -- reports must already exist; optional-report tasks may submit directly.
    if v_task.report_required
       and not exists (
         select 1
         from public.task_reports r
         where r.task_id = v_task.id
           and r.submitted_by = auth.uid()
       ) then
      raise exception using errcode='22023', message='task_report_required';
    end if;
    v_next := 'report_submitted';
    v_action := 'report_submitted';
  else
    raise exception using errcode='22023', message='invalid_progress_status';
  end if;

  insert into public.task_activity_log(task_id, actor_id, action, details)
  values (
    v_task.id,
    auth.uid(),
    v_action,
    jsonb_build_object(
      'note', nullif(trim(p_note), ''),
      'previous_status', v_task.status,
      'new_status', v_next
    )
  );

  update public.tasks
  set status = v_next,
      started_at = case
        when v_next = 'in_progress' then coalesce(started_at, now())
        else started_at
      end,
      report_submitted_at = case
        when v_next = 'report_submitted' then coalesce(report_submitted_at, now())
        else report_submitted_at
      end,
      updated_at = now()
  where id = v_task.id;

  return v_task.id;
end;
$$;

revoke all on function public.mobile_record_task_update(uuid, text, text)
from public, anon, authenticated;
grant execute on function public.mobile_record_task_update(uuid, text, text)
to authenticated;
