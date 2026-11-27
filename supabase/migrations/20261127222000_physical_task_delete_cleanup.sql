begin;

-- Keep the activity log append-only for normal callers, but allow the
-- privileged task-delete RPC to remove all history for a task as part of the
-- same transaction. All task-owned child tables use ON DELETE CASCADE,
-- including notifications and notification_reminder_log.
create or replace function public.prevent_task_activity_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE'
     and current_setting('app.allow_task_delete', true) = 'on' then
    return old;
  end if;

  raise exception using errcode = '42501', message = 'task_activity_log_append_only';
end;
$$;

create or replace function public.admin_delete_task(
  p_organization_id uuid,
  p_task_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.management_role_allowed(p_organization_id) then
    raise exception using errcode = '42501', message = 'management_role_required';
  end if;

  if not exists (
    select 1
    from public.tasks
    where id = p_task_id
      and organization_id = p_organization_id
  ) then
    raise exception using errcode = 'P0002', message = 'task_not_found';
  end if;

  -- This setting is transaction-local and is recognized only by the
  -- append-only activity trigger during this privileged cascade.
  perform set_config('app.allow_task_delete', 'on', true);

  delete from public.tasks
  where id = p_task_id
    and organization_id = p_organization_id;

  return p_task_id;
end;
$$;

commit;
