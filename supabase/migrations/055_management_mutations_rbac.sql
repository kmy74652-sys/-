begin;

create or replace function public.management_role_allowed(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1
    from public.organization_memberships m
    join public.role_assignments r on r.organization_id = m.organization_id and r.membership_id = m.id
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.is_active
      and r.role_code in ('owner', 'admin_followup')
  );
$$;
revoke all on function public.management_role_allowed(uuid) from public, anon;
grant execute on function public.management_role_allowed(uuid) to authenticated;

create or replace function public.admin_update_task(p_organization_id uuid, p_task_id uuid, p_title text, p_description text, p_due_at timestamptz)
returns uuid language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.management_role_allowed(p_organization_id) then raise exception using errcode='42501', message='management_role_required'; end if;
  update public.tasks set title=coalesce(nullif(trim(p_title),''),title), description=nullif(trim(coalesce(p_description,'')),''), due_at=coalesce(p_due_at,due_at), updated_at=now()
  where id=p_task_id and organization_id=p_organization_id and deleted_at is null;
  if not found then raise exception using errcode='P0002', message='task_not_found'; end if;
  return p_task_id;
end;
$$;

create or replace function public.admin_delete_task(p_organization_id uuid, p_task_id uuid)
returns uuid language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.management_role_allowed(p_organization_id) then raise exception using errcode='42501', message='management_role_required'; end if;
  delete from public.tasks where id=p_task_id and organization_id=p_organization_id;
  if not found then raise exception using errcode='P0002', message='task_not_found'; end if;
  return p_task_id;
end;
$$;

create or replace function public.admin_update_branch(p_organization_id uuid, p_branch_id uuid, p_code text, p_name text)
returns uuid language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.management_role_allowed(p_organization_id) then raise exception using errcode='42501', message='management_role_required'; end if;
  update public.branches set code=coalesce(nullif(trim(p_code),''),code), name=coalesce(nullif(trim(p_name),''),name)
  where id=p_branch_id and organization_id=p_organization_id;
  if not found then raise exception using errcode='P0002', message='branch_not_found'; end if;
  return p_branch_id;
end;
$$;

create or replace function public.admin_delete_branch(p_organization_id uuid, p_branch_id uuid)
returns uuid language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.management_role_allowed(p_organization_id) then raise exception using errcode='42501', message='management_role_required'; end if;
  if exists(select 1 from public.tasks where organization_id=p_organization_id and branch_id=p_branch_id and deleted_at is null)
     or exists(select 1 from public.role_assignments where organization_id=p_organization_id and branch_id=p_branch_id) then
    raise exception using errcode='23514', message='branch_in_use';
  end if;
  delete from public.branches where id=p_branch_id and organization_id=p_organization_id;
  if not found then raise exception using errcode='P0002', message='branch_not_found'; end if;
  return p_branch_id;
end;
$$;

create or replace function public.admin_update_report_template(p_organization_id uuid, p_template_id uuid, p_title text, p_description text, p_is_active boolean default null)
returns uuid language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.management_role_allowed(p_organization_id) then raise exception using errcode='42501', message='management_role_required'; end if;
  update public.report_form_templates set title=coalesce(nullif(trim(p_title),''),title), description=nullif(trim(coalesce(p_description,'')),''), is_active=coalesce(p_is_active,is_active), updated_at=now(), updated_by=auth.uid()
  where id=p_template_id and organization_id=p_organization_id;
  if not found then raise exception using errcode='P0002', message='report_template_not_found'; end if;
  return p_template_id;
end;
$$;

create or replace function public.admin_delete_report(p_organization_id uuid, p_report_id uuid)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare v_task uuid;
begin
  if not public.management_role_allowed(p_organization_id) then raise exception using errcode='42501', message='management_role_required'; end if;
  select task_id into v_task from public.task_reports where id=p_report_id and organization_id=p_organization_id;
  if not found then raise exception using errcode='P0002', message='report_not_found'; end if;
  delete from public.task_reports where id=p_report_id and organization_id=p_organization_id;
  update public.tasks set status=case when status in ('report_submitted','completed_approved') then 'in_progress'::text else status::text end::public.task_status, report_submitted_at=null, approved_at=null, updated_at=now() where id=v_task and organization_id=p_organization_id;
  return p_report_id;
end;
$$;

create or replace function public.admin_delete_employee_record(p_organization_id uuid, p_membership_id uuid)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare v_user uuid;
begin
  if not public.management_role_allowed(p_organization_id) then raise exception using errcode='42501', message='management_role_required'; end if;
  select user_id into v_user from public.organization_memberships where id=p_membership_id and organization_id=p_organization_id;
  if not found then raise exception using errcode='P0002', message='employee_not_found'; end if;
  if exists(select 1 from public.role_assignments where organization_id=p_organization_id and membership_id=p_membership_id and role_code='owner') then raise exception using errcode='42501', message='owner_account_protected'; end if;
  delete from public.employee_access_credentials where membership_id=p_membership_id;
  delete from public.role_assignments where organization_id=p_organization_id and membership_id=p_membership_id;
  delete from public.organization_memberships where id=p_membership_id and organization_id=p_organization_id;
  return v_user;
end;
$$;

revoke all on function public.admin_update_task(uuid,uuid,text,text,timestamptz) from public, anon;
revoke all on function public.admin_delete_task(uuid,uuid) from public, anon;
revoke all on function public.admin_update_branch(uuid,uuid,text,text) from public, anon;
revoke all on function public.admin_delete_branch(uuid,uuid) from public, anon;
revoke all on function public.admin_update_report_template(uuid,uuid,text,text,boolean) from public, anon;
revoke all on function public.admin_delete_report(uuid,uuid) from public, anon;
revoke all on function public.admin_delete_employee_record(uuid,uuid) from public, anon;
grant execute on function public.admin_update_task(uuid,uuid,text,text,timestamptz), public.admin_delete_task(uuid,uuid), public.admin_update_branch(uuid,uuid,text,text), public.admin_delete_branch(uuid,uuid), public.admin_update_report_template(uuid,uuid,text,text,boolean), public.admin_delete_report(uuid,uuid), public.admin_delete_employee_record(uuid,uuid) to authenticated;

commit;
