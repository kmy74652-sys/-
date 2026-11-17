begin;

-- The executive follow-up role is explicitly allowed to manage branches.
insert into public.role_permissions(role_code, permission_code)
values ('admin_followup', 'branches.manage')
on conflict do nothing;

create or replace function public.admin_update_employee(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_employee_id uuid,
  p_full_name text,
  p_employee_no text,
  p_role_code text,
  p_branch_id uuid,
  p_is_active boolean
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_actor_owner boolean;
  v_role_count integer;
  v_old_role text;
  v_old_branch uuid;
begin
  if not exists (
    select 1
    from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id=m.organization_id and ra.membership_id=m.id
    join public.role_permissions rp on rp.role_code=ra.role_code and rp.permission_code='employees.manage'
    where m.id=p_actor_membership_id and m.organization_id=p_organization_id and m.is_active
      and ra.role_code in ('owner','admin_followup')
  ) then
    raise exception using errcode='42501', message='employee_management_permission_required';
  end if;

  select exists (
    select 1 from public.role_assignments
    where organization_id=p_organization_id and membership_id=p_actor_membership_id and role_code='owner'
  ) into v_actor_owner;

  if p_full_name is null or length(trim(p_full_name)) < 2 or length(trim(p_full_name)) > 160
     or p_employee_no is null or p_employee_no !~ '^[0-9]{1,32}$'
     or p_role_code not in ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker')
     or p_is_active is null then
    raise exception using errcode='22023', message='invalid_employee_payload';
  end if;

  if p_role_code='owner' and not v_actor_owner then
    raise exception using errcode='42501', message='owner_role_requires_owner';
  end if;

  if not exists (
    select 1 from public.branches
    where id=p_branch_id and organization_id=p_organization_id and is_active
  ) then
    raise exception using errcode='22023', message='branch_not_found';
  end if;

  if exists (
    select 1 from public.organization_memberships
    where employee_no=p_employee_no and id<>p_employee_id
  ) then
    raise exception using errcode='23505', message='employee_no_exists';
  end if;

  perform 1 from public.organization_memberships
  where id=p_employee_id and organization_id=p_organization_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='employee_not_found';
  end if;

  select count(*), min(role_code), min(branch_id::text)::uuid
    into v_role_count, v_old_role, v_old_branch
  from public.role_assignments
  where organization_id=p_organization_id and membership_id=p_employee_id;

  if v_role_count > 1 then
    raise exception using errcode='22023', message='employee_multiple_role_assignments_need_review';
  end if;

  update public.organization_memberships
  set display_name=trim(p_full_name), employee_no=p_employee_no, is_active=p_is_active
  where id=p_employee_id and organization_id=p_organization_id;

  if v_role_count=1 then
    update public.role_assignments
    set role_code=p_role_code, branch_id=p_branch_id
    where organization_id=p_organization_id and membership_id=p_employee_id;
  else
    insert into public.role_assignments(organization_id,membership_id,role_code,branch_id)
    values(p_organization_id,p_employee_id,p_role_code,p_branch_id);
  end if;

  insert into public.employee_access_audit_log(
    organization_id,membership_id,actor_membership_id,action,metadata
  ) values (
    p_organization_id,p_employee_id,p_actor_membership_id,case when p_is_active then 'updated' else 'archived' end,
    jsonb_build_object(
      'employee_no',p_employee_no,
      'role_code',p_role_code,
      'branch_id',p_branch_id,
      'is_active',p_is_active,
      'previous_role_code',v_old_role,
      'previous_branch_id',v_old_branch
    )
  );

  return jsonb_build_object('ok',true,'employee_id',p_employee_id);
end;
$$;

create or replace function public.admin_manage_branch(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_action text,
  p_branch_id uuid default null,
  p_code text default null,
  p_name text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_branch public.branches%rowtype;
begin
  if p_action not in ('create','update','archive','activate') then
    raise exception using errcode='22023', message='invalid_branch_action';
  end if;

  if not exists (
    select 1
    from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id=m.organization_id and ra.membership_id=m.id
    join public.role_permissions rp on rp.role_code=ra.role_code and rp.permission_code='branches.manage'
    where m.id=p_actor_membership_id and m.organization_id=p_organization_id and m.is_active
      and ra.role_code in ('owner','admin_followup')
  ) then
    raise exception using errcode='42501', message='branch_management_permission_required';
  end if;

  if p_action='create' then
    if p_code is null or p_code !~ '^[A-Z0-9_-]{2,24}$'
       or p_name is null or length(trim(p_name)) < 2 or length(trim(p_name)) > 120 then
      raise exception using errcode='22023', message='invalid_branch_payload';
    end if;
    insert into public.branches(organization_id,code,name,is_active)
    values(p_organization_id,p_code,trim(p_name),true)
    returning * into v_branch;
    insert into public.employee_access_audit_log(
      organization_id,membership_id,actor_membership_id,action,metadata
    ) values (p_organization_id,null,p_actor_membership_id,'branch_created',
      jsonb_build_object('branch_id',v_branch.id,'code',v_branch.code,'name',v_branch.name));
  elsif p_action='update' then
    if p_branch_id is null or p_name is null or length(trim(p_name)) < 2 or length(trim(p_name)) > 120 then
      raise exception using errcode='22023', message='invalid_branch_payload';
    end if;
    update public.branches set name=trim(p_name)
    where id=p_branch_id and organization_id=p_organization_id
    returning * into v_branch;
    if not found then raise exception using errcode='P0002', message='branch_not_found'; end if;
    insert into public.employee_access_audit_log(
      organization_id,membership_id,actor_membership_id,action,metadata
    ) values (p_organization_id,null,p_actor_membership_id,'branch_updated',
      jsonb_build_object('branch_id',v_branch.id,'code',v_branch.code,'name',v_branch.name));
  elsif p_action='archive' then
    if p_branch_id is null then raise exception using errcode='22023', message='branch_id_required'; end if;
    if exists (
      select 1 from public.role_assignments ra
      join public.organization_memberships m on m.id=ra.membership_id and m.organization_id=ra.organization_id
      where ra.organization_id=p_organization_id and ra.branch_id=p_branch_id and m.is_active
    ) then
      raise exception using errcode='22023', message='branch_has_active_employees';
    end if;
    update public.branches set is_active=false
    where id=p_branch_id and organization_id=p_organization_id
    returning * into v_branch;
    if not found then raise exception using errcode='P0002', message='branch_not_found'; end if;
    insert into public.employee_access_audit_log(
      organization_id,membership_id,actor_membership_id,action,metadata
    ) values (p_organization_id,null,p_actor_membership_id,'branch_archived',
      jsonb_build_object('branch_id',v_branch.id,'code',v_branch.code,'name',v_branch.name));
  elsif p_action='activate' then
    if p_branch_id is null then raise exception using errcode='22023', message='branch_id_required'; end if;
    update public.branches set is_active=true
    where id=p_branch_id and organization_id=p_organization_id
    returning * into v_branch;
    if not found then raise exception using errcode='P0002', message='branch_not_found'; end if;
    insert into public.employee_access_audit_log(
      organization_id,membership_id,actor_membership_id,action,metadata
    ) values (p_organization_id,null,p_actor_membership_id,'branch_reactivated',
      jsonb_build_object('branch_id',v_branch.id,'code',v_branch.code,'name',v_branch.name));
  end if;

  return jsonb_build_object('ok',true,'branch_id',v_branch.id,'is_active',v_branch.is_active);
end;
$$;

revoke all on function public.admin_update_employee(uuid,uuid,uuid,text,text,text,uuid,boolean) from public, anon, authenticated;
revoke all on function public.admin_manage_branch(uuid,uuid,text,uuid,text,text) from public, anon, authenticated;
grant execute on function public.admin_update_employee(uuid,uuid,uuid,text,text,text,uuid,boolean) to service_role;
grant execute on function public.admin_manage_branch(uuid,uuid,text,uuid,text,text) to service_role;

commit;
