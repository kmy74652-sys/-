begin;

-- task_activity_log is append-only. Retire tasks instead of physically
-- deleting them so the audit trail remains intact.
create or replace function public.admin_delete_task(p_organization_id uuid, p_task_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.management_role_allowed(p_organization_id) then
    raise exception using errcode = '42501', message = 'management_role_required';
  end if;

  update public.tasks
  set deleted_at = now(), updated_at = now()
  where id = p_task_id
    and organization_id = p_organization_id
    and deleted_at is null;

  if not found then
    raise exception using errcode = 'P0002', message = 'task_not_found';
  end if;

  return p_task_id;
end;
$$;

commit;
