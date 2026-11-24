begin;

create or replace function public.admin_update_unified_task(
  p_organization_id uuid,
  p_task_id uuid,
  p_title text,
  p_description text,
  p_due_at timestamptz,
  p_assigned_to uuid default null,
  p_branch_id uuid default null,
  p_role_code text default null
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
    from public.tasks t
    where t.id = p_task_id
      and t.organization_id = p_organization_id
      and t.deleted_at is null
      and (
        t.title like 'الجدول الموحد -%'
        or coalesce(t.description, '') like '%الجدول الموحد الرسمي:%'
      )
  ) then
    raise exception using errcode = 'P0002', message = 'unified_task_not_found';
  end if;

  update public.tasks
  set title = coalesce(nullif(trim(p_title), ''), title),
      description = nullif(trim(coalesce(p_description, '')), ''),
      due_at = coalesce(p_due_at, due_at),
      assigned_to = coalesce(p_assigned_to, assigned_to),
      branch_id = p_branch_id,
      position_code = coalesce(nullif(trim(p_role_code), ''), position_code),
      updated_at = now()
  where id = p_task_id
    and organization_id = p_organization_id
    and deleted_at is null;

  return p_task_id;
end;
$$;

revoke all on function public.admin_update_unified_task(uuid, uuid, text, text, timestamptz, uuid, uuid, text) from public, anon;
grant execute on function public.admin_update_unified_task(uuid, uuid, text, text, timestamptz, uuid, uuid, text) to authenticated;

commit;
