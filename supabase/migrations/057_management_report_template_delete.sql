begin;
create or replace function public.admin_delete_report_template(p_organization_id uuid,p_template_id uuid) returns uuid language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.management_role_allowed(p_organization_id) then raise exception using errcode='42501',message='management_role_required'; end if;
  if exists(select 1 from public.tasks where organization_id=p_organization_id and template_id=p_template_id)
     or exists(select 1 from public.report_form_templates t where t.id=p_template_id and t.organization_id=p_organization_id and exists(select 1 from public.report_form_versions v where v.template_id=t.id and v.status='published')) then
    raise exception using errcode='23514',message='report_template_in_use';
  end if;
  delete from public.report_form_templates where id=p_template_id and organization_id=p_organization_id;
  if not found then raise exception using errcode='P0002',message='report_template_not_found'; end if;
  return p_template_id;
end;
$$;
revoke all on function public.admin_delete_report_template(uuid,uuid) from public,anon;
grant execute on function public.admin_delete_report_template(uuid,uuid) to authenticated;
commit;
