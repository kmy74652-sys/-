begin;

-- One reminder per overdue task, recipient and calendar day.
-- The hourly scheduler below is intentionally idempotent through this key.
create table if not exists public.notification_reminder_log (
  task_id uuid not null references public.tasks(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  reminder_date date not null default current_date,
  sent_at timestamptz not null default now(),
  primary key (task_id, recipient_user_id, reminder_date)
);
create index if not exists notification_reminder_log_date_idx
  on public.notification_reminder_log (reminder_date, sent_at desc);
alter table public.notification_reminder_log enable row level security;
revoke all on public.notification_reminder_log from anon, authenticated;

create or replace function public.dispatch_overdue_task_reminders()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_task record;
  v_logged_task uuid;
  v_sent integer := 0;
begin
  for v_task in
    select t.id, t.organization_id, t.assigned_to, t.title, t.due_at
      from public.tasks t
     where t.assigned_to is not null
       and t.deleted_at is null
       and t.due_at < now()
       and t.status not in ('approved', 'completed_approved', 'cancelled', 'rejected', 'submitted', 'report_submitted')
  loop
    v_logged_task := null;
    insert into public.notification_reminder_log(task_id, recipient_user_id, reminder_date)
    values (v_task.id, v_task.assigned_to, current_date)
    on conflict (task_id, recipient_user_id, reminder_date) do nothing
    returning task_id into v_logged_task;

    if v_logged_task is not null then
      insert into public.notifications(
        organization_id, recipient_user_id, task_id, title, body, severity
      ) values (
        v_task.organization_id,
        v_task.assigned_to,
        v_task.id,
        'تذكير بمهمة متأخرة',
        'المهمة «' || coalesce(v_task.title, 'مهمة') || '» تجاوزت موعدها المحدد. افتح تبويب المهام لاستكمالها.',
        'warning'
      );
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$$;
revoke all on function public.dispatch_overdue_task_reminders() from public, anon, authenticated;

-- Run every hour. The daily primary key prevents duplicate reminders while
-- allowing a fresh reminder on the next calendar day.
create extension if not exists pg_cron;
do $$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'overdue-task-reminders-hourly' limit 1;
  if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
  perform cron.schedule(
    'overdue-task-reminders-hourly',
    '5 * * * *',
    'select public.dispatch_overdue_task_reminders();'
  );
end;
$$;

commit;
