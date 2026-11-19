begin;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  recipient_user_id uuid not null,
  task_id uuid references public.tasks(id) on delete cascade,
  title text not null,
  body text not null,
  severity text not null default 'info' check (severity in ('info', 'success', 'warning', 'error')),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_recipient_unread_idx
  on public.notifications (recipient_user_id, read_at, created_at desc);

alter table public.notifications enable row level security;
drop policy if exists notifications_select_recipient on public.notifications;
create policy notifications_select_recipient on public.notifications
  for select to authenticated
  using (recipient_user_id = auth.uid());

grant select on public.notifications to authenticated;

create or replace function public.notify_task_assignee()
returns trigger language plpgsql security definer set search_path = public, auth as $$
begin
  if new.assigned_to is not null then
    insert into public.notifications(organization_id, recipient_user_id, task_id, title, body, severity)
    values (
      new.organization_id,
      new.assigned_to,
      new.id,
      'مهمة جديدة من الإدارة',
      'تم إسناد المهمة «' || coalesce(new.title, 'مهمة جديدة') || '» إليك. افتح تبويب المهام لبدء التنفيذ' || case when coalesce(new.report_required, false) then ' وتعبئة التقرير المطلوب.' else '.' end,
      'info'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_notify_assignee on public.tasks;
create trigger tasks_notify_assignee
after insert on public.tasks
for each row execute function public.notify_task_assignee();

commit;
