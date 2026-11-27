begin;

create or replace function public.notify_report_cycle()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_task public.tasks%rowtype;
  v_recipient uuid;
  v_title text;
  v_body text;
  v_sender_name text;
  v_event_at timestamptz;
  v_local_event timestamp;
  v_period text;
begin
  select * into v_task from public.tasks where id = new.task_id;
  if not found then return new; end if;

  select m.display_name into v_sender_name
    from public.organization_memberships m
   where m.organization_id = v_task.organization_id
     and m.user_id = new.submitted_by
     and m.is_active;

  v_event_at := coalesce(new.submitted_at, new.created_at, now());
  v_local_event := timezone('Asia/Aden', v_event_at);
  v_period := case when extract(hour from v_local_event) < 12 then 'ص' else 'م' end;

  if tg_op = 'INSERT' then
    v_recipient := v_task.created_by;
    v_title := 'تقرير جديد للمراجعة';
    v_body := coalesce(nullif(trim(v_sender_name), ''), 'الموظف')
      || ' أرسل تقرير المهمة «' || coalesce(v_task.title, 'مهمة')
      || '» بتاريخ ' || to_char(v_local_event, 'DD/MM/YYYY')
      || ' الساعة ' || to_char(v_local_event, 'HH12:MI') || ' ' || v_period
      || '، وأصبح جاهزًا للمراجعة.';
  elsif new.status is distinct from old.status and new.status in ('approved', 'returned') then
    v_recipient := v_task.assigned_to;
    v_title := case when new.status = 'approved' then 'تم اعتماد التقرير' else 'أُعيد التقرير للتعديل' end;
    v_body := case
      when new.status = 'approved' then 'تم اعتماد تقرير مهمة «' || coalesce(v_task.title, 'مهمة') || '». '
      else 'أُعيد تقرير مهمة «' || coalesce(v_task.title, 'مهمة') || '» للتعديل. '
    end
      || 'أرسله ' || coalesce(nullif(trim(v_sender_name), ''), 'الموظف')
      || ' بتاريخ ' || to_char(v_local_event, 'DD/MM/YYYY')
      || ' الساعة ' || to_char(v_local_event, 'HH12:MI') || ' ' || v_period || '.';
  else
    return new;
  end if;

  if v_recipient is not null then
    insert into public.notifications(organization_id, recipient_user_id, task_id, title, body, severity)
    values (v_task.organization_id, v_recipient, v_task.id, v_title, v_body,
      case when new.status = 'returned' then 'warning' else 'info' end);
  end if;
  return new;
end;
$$;

drop trigger if exists task_reports_notify_cycle on public.task_reports;
create trigger task_reports_notify_cycle
after insert or update of status on public.task_reports
for each row execute function public.notify_report_cycle();

commit;
