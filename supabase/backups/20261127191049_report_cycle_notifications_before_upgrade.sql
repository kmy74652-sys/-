-- Pre-upgrade backup of the database objects changed by
-- 20261127191000_report_notification_sender_and_time.sql
-- Project: إدارة الشاعري (fjmryqhdwxsocdzswnkq)
-- Captured: 2026-11-27

begin;

create or replace function public.notify_report_cycle()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'auth'
 as $function$
declare v_task public.tasks%rowtype; v_recipient uuid; v_title text; v_body text;
begin
  select * into v_task from public.tasks where id = new.task_id;
  if not found then return new; end if;
  if tg_op = 'INSERT' then v_recipient := v_task.created_by; v_title := 'تقرير جديد للمراجعة'; v_body := 'أرسل الموظف تقرير المهمة «' || coalesce(v_task.title, 'مهمة') || '» وأصبح جاهزًا للمراجعة.';
  elsif new.status is distinct from old.status and new.status in ('approved', 'returned') then v_recipient := v_task.assigned_to; v_title := case when new.status = 'approved' then 'تم اعتماد التقرير' else 'أُعيد التقرير للتعديل' end; v_body := case when new.status = 'approved' then 'تم اعتماد تقرير مهمة «' || coalesce(v_task.title, 'مهمة') || '».' else 'أُعيد تقرير مهمة «' || coalesce(v_task.title, 'مهمة') || '» للتعديل.' end;
  else return new; end if;
  if v_recipient is not null then insert into public.notifications(organization_id, recipient_user_id, task_id, title, body, severity) values (v_task.organization_id, v_recipient, v_task.id, v_title, v_body, case when new.status = 'returned' then 'warning' else 'info' end); end if;
  return new;
end;
$function$;

drop trigger if exists task_reports_notify_cycle on public.task_reports;
create trigger task_reports_notify_cycle
  after insert or update of status on public.task_reports
  for each row execute function notify_report_cycle();

commit;
