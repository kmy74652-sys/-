begin;

-- task_activity_log is append-only by design. Management deletion therefore
-- retires the task instead of attempting a physical delete that the audit
-- trigger must reject. This keeps the audit trail and removes the task from
-- active lists through the existing deleted_at scope.
create or replace function public.admin_delete_task(p_organization_id uuid, p_task_id uuid)
returns uuid language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.management_role_allowed(p_organization_id) then
    raise exception using errcode='42501', message='management_role_required';
  end if;
  update public.tasks
  set deleted_at=now(), updated_at=now()
  where id=p_task_id and organization_id=p_organization_id and deleted_at is null;
  if not found then raise exception using errcode='P0002', message='task_not_found'; end if;
  return p_task_id;
end;
$$;

commit;
