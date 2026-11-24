begin;

-- Delete only an unused report template. Historical reports, submissions, and
-- task snapshots are never deleted or detached by this operation.
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
  v_count integer;
begin
  if not public.management_role_allowed(p_organization_id) then
    raise exception using errcode = '42501', message = 'management_role_required';
  end if;

  if not exists (
    select 1 from public.report_form_templates
    where id = p_template_id and organization_id = p_organization_id
  ) then
    raise exception using errcode = 'P0002', message = 'report_template_not_found';
  end if;

  select count(*) into v_count
  from public.report_submissions
  where form_id = p_template_id;
  if v_count > 0 then
    raise exception using errcode = '23503', message = 'report_template_has_submissions';
  end if;

  select count(*) into v_count
  from public.employee_dynamic_reports
  where template_id = p_template_id;
  if v_count > 0 then
    raise exception using errcode = '23503', message = 'report_template_has_dynamic_reports';
  end if;

  select count(*) into v_count
  from public.task_report_form_snapshots
  where template_id = p_template_id;
  if v_count > 0 then
    raise exception using errcode = '23503', message = 'report_template_has_snapshots';
  end if;

  select coalesce(array_agg(id), '{}'::uuid[]) into v_version_ids
  from public.report_form_versions
  where template_id = p_template_id;

  -- This association is current configuration only; no task or report row is
  -- removed. It must be cleared before deleting the unused versions.
  delete from public.task_template_report_forms
  where version_id = any(v_version_ids);

  -- report_form_version_fields cascades from report_form_versions. Since all
  -- historical-reference tables were checked above, this removes only unused
  -- designer data.
  delete from public.report_form_versions
  where template_id = p_template_id;

  delete from public.report_form_templates
  where id = p_template_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'report_template_not_found';
  end if;

  return p_template_id;
end;
$$;

revoke all on function public.admin_delete_report_template(uuid, uuid) from public, anon;
grant execute on function public.admin_delete_report_template(uuid, uuid) to authenticated;

commit;
