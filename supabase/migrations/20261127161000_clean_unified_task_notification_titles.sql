begin;

create or replace function public.clean_task_notification_title(raw_title text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  cleaned text;
begin
  cleaned := btrim(coalesce(raw_title, ''));
  cleaned := regexp_replace(
    cleaned,
    '^الجدول الموحد\s*-\s*[^·]+·\s*',
    '',
    'i'
  );
  cleaned := regexp_replace(
    cleaned,
    '^الجدول الموحد\s*-\s*',
    '',
    'i'
  );
  return coalesce(nullif(btrim(cleaned), ''), 'مهمة');
end;
$$;

create or replace function public.notify_task_assignee()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.assigned_to is not null then
    insert into public.notifications(
      organization_id,
      recipient_user_id,
      task_id,
      title,
      body,
      severity
    )
    values (
      new.organization_id,
      new.assigned_to,
      new.id,
      'مهمة جديدة من الإدارة',
      'تم إسناد المهمة «' || public.clean_task_notification_title(new.title) || '» إليك. افتح تبويب المهام لبدء التنفيذ'
        || case when coalesce(new.report_required, false)
          then ' وتعبئة التقرير المطلوب.'
          else '.'
        end,
      'info'
    );
  end if;
  return new;
end;
$$;

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
    select t.id, t.organization_id, t.assigned_to, t.title
    from public.tasks t
    where t.assigned_to is not null
      and t.deleted_at is null
      and t.due_at < now()
      and t.status not in (
        'completed_approved'::public.task_status,
        'report_submitted'::public.task_status
      )
  loop
    v_logged_task := null;
    insert into public.notification_reminder_log(
      task_id,
      recipient_user_id,
      reminder_date
    )
    values (v_task.id, v_task.assigned_to, current_date)
    on conflict (task_id, recipient_user_id, reminder_date)
    do nothing
    returning task_id into v_logged_task;

    if v_logged_task is not null then
      insert into public.notifications(
        organization_id,
        recipient_user_id,
        task_id,
        title,
        body,
        severity
      )
      values (
        v_task.organization_id,
        v_task.assigned_to,
        v_task.id,
        'تذكير بمهمة متأخرة',
        'المهمة «' || public.clean_task_notification_title(v_task.title) || '» تجاوزت موعدها المحدد. افتح تبويب المهام لاستكمالها.',
        'warning'
      );
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$$;

-- تنظيف الإشعارات القديمة التي خزنت الاسم الداخلي للجدول الموحد.
update public.notifications
set body = regexp_replace(
  body,
  'المهمة «الجدول الموحد\s*-\s*[^·»]+·\s*([^»]+)»',
  'المهمة «\1»'
)
where body like '%المهمة «الجدول الموحد - %';

revoke all on function public.clean_task_notification_title(text) from public, anon, authenticated;
revoke all on function public.notify_task_assignee() from public, anon, authenticated;
revoke all on function public.dispatch_overdue_task_reminders() from public, anon, authenticated;

grant execute on function public.notify_task_assignee() to postgres, service_role;
grant execute on function public.dispatch_overdue_task_reminders() to postgres, service_role;

commit;
