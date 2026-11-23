begin;

create or replace function public.mobile_mark_task_opened(p_task_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_task public.tasks%rowtype;
  v_active_member boolean;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;

  select * into v_task
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;

  if not found or v_task.assigned_to <> auth.uid() then
    raise exception using errcode = 'P0002', message = 'task_not_found';
  end if;

  select exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = v_task.organization_id
      and m.user_id = auth.uid()
      and m.is_active
  ) into v_active_member;

  if not v_active_member
     and not public.has_org_permission(v_task.organization_id, 'tasks.read', null::uuid) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  update public.tasks
  set status = case when status = 'new' then 'received' else status end,
      received_at = coalesce(received_at, now()),
      opened_at = coalesce(opened_at, now()),
      updated_at = now()
  where id = v_task.id;

  insert into public.task_activity_log(task_id, actor_id, action, details)
  values (
    v_task.id,
    auth.uid(),
    'task_opened',
    jsonb_build_object(
      'previous_status', v_task.status,
      'new_status', case when v_task.status = 'new' then 'received' else v_task.status end
    )
  );

  return v_task.id;
end;
$$;

revoke all on function public.mobile_mark_task_opened(uuid) from public, anon, authenticated;
grant execute on function public.mobile_mark_task_opened(uuid) to authenticated;

commit;
