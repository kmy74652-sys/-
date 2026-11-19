begin;
create or replace function public.enforce_management_mutation() returns trigger language plpgsql security definer set search_path=public,auth as $$
declare v_org uuid;
begin
  if auth.uid() is null then return coalesce(new,old); end if;
  v_org := coalesce((to_jsonb(new)->>'organization_id')::uuid, (to_jsonb(old)->>'organization_id')::uuid);
  if v_org is not null and not public.management_role_allowed(v_org) then raise exception using errcode='42501',message='management_role_required'; end if;
  return coalesce(new,old);
end;
$$;
drop trigger if exists management_branches_mutation on public.branches;
create trigger management_branches_mutation before update or delete on public.branches for each row execute function public.enforce_management_mutation();
drop trigger if exists management_memberships_mutation on public.organization_memberships;
create trigger management_memberships_mutation before update or delete on public.organization_memberships for each row execute function public.enforce_management_mutation();
drop trigger if exists management_report_templates_mutation on public.report_form_templates;
create trigger management_report_templates_mutation before update or delete on public.report_form_templates for each row execute function public.enforce_management_mutation();
revoke all on function public.enforce_management_mutation() from public,anon;
commit;
