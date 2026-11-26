begin;

create or replace function public.admin_update_task(
  p_organization_id uuid,
  p_task_id uuid,
  p_title text,
  p_description text,
  p_due_at timestamptz,
  p_priority text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.management_role_allowed(p_organization_id) then
    raise exception using errcode='42501', message='management_role_required';
  end if;

  if p_priority is not null and p_priority not in ('low', 'normal', 'high', 'urgent') then
    raise exception using errcode='22023', message='invalid_task_priority';
  end if;

  update public.tasks
  set title = coalesce(nullif(trim(p_title), ''), title),
      description = nullif(trim(coalesce(p_description, '')), ''),
      due_at = coalesce(p_due_at, due_at),
      priority = coalesce(nullif(trim(p_priority), '')::public.task_priority, priority),
      updated_at = now()
  where id = p_task_id
    and organization_id = p_organization_id
    and deleted_at is null;

  if not found then
    raise exception using errcode='P0002', message='task_not_found';
  end if;

  return p_task_id;
end;
$$;

revoke all on function public.admin_update_task(uuid, uuid, text, text, timestamptz, text) from public, anon;
grant execute on function public.admin_update_task(uuid, uuid, text, text, timestamptz, text) to authenticated;

commit;
