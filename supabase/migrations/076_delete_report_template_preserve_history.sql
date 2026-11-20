begin;

-- Report templates are library metadata. Historical versions and task snapshots
-- must remain readable after the library template is permanently deleted.
do $$
declare
  constraint_name text;
begin
  -- The original FK was created with ON DELETE CASCADE and would remove every
  -- version and its fields when the library template is deleted. Replace it
  -- with a nullable historical reference using ON DELETE SET NULL.
  for constraint_name in
    select con.conname
    from pg_constraint con
    where con.contype = 'f'
      and con.conrelid = 'public.report_form_versions'::regclass
      and con.confrelid = 'public.report_form_templates'::regclass
  loop
    execute format('alter table public.report_form_versions drop constraint %I', constraint_name);
  end loop;

  alter table public.report_form_versions
    alter column template_id drop not null;

  alter table public.report_form_versions
    add constraint report_form_versions_template_id_fkey
    foreign key (template_id) references public.report_form_templates(id) on delete set null;
end $$;

create or replace function public.admin_delete_report_template(
  p_organization_id uuid,
  p_template_id uuid
) returns uuid
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
    from public.report_form_templates
    where id = p_template_id
      and organization_id = p_organization_id
  ) then
    raise exception using errcode = 'P0002', message = 'report_template_not_found';
  end if;

  -- Remove only the current library-to-task-template associations. This does
  -- not delete tasks, submitted reports, snapshots, versions, or field values.
  delete from public.task_template_report_forms
  where version_id in (
    select id
    from public.report_form_versions
    where template_id = p_template_id
  );

  -- Keep snapshots and their JSON schema/value history, but sever the deleted
  -- library identity from historical rows explicitly and safely.
  update public.task_report_form_snapshots
  set template_id = null
  where template_id = p_template_id;

  -- Versions and version fields are historical records. Detach versions before
  -- deleting the library row so the versions and their fields survive.
  update public.report_form_versions
  set template_id = null
  where template_id = p_template_id;

  delete from public.report_form_templates
  where id = p_template_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'report_template_not_found';
  end if;

  return p_template_id;
end;
$$;

revoke all on function public.admin_delete_report_template(uuid, uuid) from public, anon;
grant execute on function public.admin_delete_report_template(uuid, uuid) to authenticated;

commit;
