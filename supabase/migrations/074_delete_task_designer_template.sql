begin;

create or replace function public.delete_task_designer_template(
  p_organization_id uuid,
  p_template_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, alshaari_private
as $$
begin
  if auth.uid() is null
     or not alshaari_private.has_permission(p_organization_id, 'task_library.manage', null::uuid) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  if not exists (
    select 1
    from public.task_templates
    where id = p_template_id
      and organization_id = p_organization_id
  ) then
    raise exception using errcode = '22023', message = 'task_template_not_found';
  end if;

  -- Keep already assigned tasks and their reports. They no longer depend on the
  -- library record after deletion, so historical execution remains readable.
  update public.tasks
  set template_id = null,
      updated_at = now()
  where template_id = p_template_id
    and organization_id = p_organization_id;

  delete from public.task_template_assignments where template_id = p_template_id;
  delete from public.task_template_report_fields where template_id = p_template_id;
  delete from public.task_import_rows where task_template_id = p_template_id;
  delete from public.task_templates
  where id = p_template_id
    and organization_id = p_organization_id;

  return true;
end;
$$;

revoke all on function public.delete_task_designer_template(uuid, uuid) from public, anon;
grant execute on function public.delete_task_designer_template(uuid, uuid) to authenticated;

commit;
