begin;

-- Explicitly destructive operation approved by the user: remove a report
-- template and all database records owned by that template. Tasks themselves
-- are retained; their snapshot reference is cleared by the existing FK rule.
create or replace function public.admin_delete_report_template(
  p_organization_id uuid,
  p_template_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_version_ids uuid[];
  v_snapshot_ids uuid[];
  v_task_report_ids uuid[];
  v_count integer;
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

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_version_ids
  from public.report_form_versions
  where template_id = p_template_id;

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_snapshot_ids
  from public.task_report_form_snapshots
  where template_id = p_template_id;

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_task_report_ids
  from public.task_reports
  where report_form_snapshot_id = any(v_snapshot_ids);

  -- Remove attachments before their RESTRICT foreign keys are reached.
  if cardinality(v_snapshot_ids) > 0 then
    delete from public.task_report_signature_attachments
    where report_form_snapshot_id = any(v_snapshot_ids);
  end if;
  if cardinality(v_task_report_ids) > 0 then
    delete from public.task_report_signature_attachments
    where report_id = any(v_task_report_ids);
  end if;

  -- Remove all submitted/reviewed report records owned by the snapshots.
  if cardinality(v_task_report_ids) > 0 then
    delete from public.task_reports
    where id = any(v_task_report_ids);
  end if;
  if cardinality(v_snapshot_ids) > 0 then
    delete from public.task_report_drafts
    where snapshot_id = any(v_snapshot_ids);
    delete from public.task_report_fields
    where source_snapshot_id = any(v_snapshot_ids);
  end if;

  -- The template's independent/dynamic reports and legacy submissions are
  -- historical data owned by this template and are removed by this operation.
  delete from public.employee_dynamic_reports
  where template_id = p_template_id;
  delete from public.report_submissions
  where form_id = p_template_id;

  if cardinality(v_snapshot_ids) > 0 then
    delete from public.task_report_form_snapshots
    where id = any(v_snapshot_ids);
  end if;

  -- Keep compatibility with an optional retired association table without
  -- failing when that table is absent from the current production schema.
  if to_regclass('public.task_template_report_forms') is not null
     and cardinality(v_version_ids) > 0 then
    execute 'delete from public.task_template_report_forms where version_id = any($1)'
      using v_version_ids;
  end if;

  if cardinality(v_version_ids) > 0 then
    delete from public.report_form_versions
    where id = any(v_version_ids);
  end if;

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
