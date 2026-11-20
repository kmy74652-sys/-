-- Employee report workspace: a submitted/approved report is immutable for the employee.
-- The review RPC changes submitted -> returned when management explicitly reopens it.

create or replace function public.prevent_locked_task_report_draft()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_locked boolean;
begin
  select exists(
    select 1
    from public.task_reports r
    where r.task_id = new.task_id
      and r.report_form_snapshot_id = new.snapshot_id
      and r.submitted_by = new.employee_id
      and r.status in ('submitted', 'approved')
  ) into v_locked;

  if v_locked then
    raise exception using errcode = '22023', message = 'report_draft_locked_after_submission';
  end if;

  return new;
end;
$$;

drop trigger if exists task_report_drafts_lock_submitted on public.task_report_drafts;
create trigger task_report_drafts_lock_submitted
before insert or update on public.task_report_drafts
for each row execute function public.prevent_locked_task_report_draft();

revoke all on function public.prevent_locked_task_report_draft() from public, anon;
