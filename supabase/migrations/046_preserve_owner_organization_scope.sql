begin;

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
  v_effective_branch uuid;
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

  if p_employee_id=p_actor_membership_id and (not v_actor_owner or p_role_code<>'owner' or not p_is_active) then
    raise exception using errcode='42501', message='owner_self_protection';
  end if;

  if p_role_code <> 'owner' then
    if p_branch_id is null or not exists (
      select 1 from public.branches
      where id=p_branch_id and organization_id=p_organization_id and is_active
    ) then
      raise exception using errcode='22023', message='branch_not_found';
    end if;
    v_effective_branch := p_branch_id;
  else
    -- Owners have organization-wide authority; a branch would narrow their scope.
    v_effective_branch := null;
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
    set role_code=p_role_code, branch_id=v_effective_branch
    where organization_id=p_organization_id and membership_id=p_employee_id;
  else
    insert into public.role_assignments(organization_id,membership_id,role_code,branch_id)
    values(p_organization_id,p_employee_id,p_role_code,v_effective_branch);
  end if;

  insert into public.employee_access_audit_log(
    organization_id,membership_id,actor_membership_id,action,metadata
  ) values (
    p_organization_id,p_employee_id,p_actor_membership_id,case when p_is_active then 'updated' else 'archived' end,
    jsonb_build_object(
      'employee_no',p_employee_no,
      'role_code',p_role_code,
      'branch_id',v_effective_branch,
      'is_active',p_is_active,
      'previous_role_code',v_old_role,
      'previous_branch_id',v_old_branch
    )
  );

  return jsonb_build_object('ok',true,'employee_id',p_employee_id,'branch_id',v_effective_branch);
end;
$$;

revoke all on function public.admin_update_employee(uuid,uuid,uuid,text,text,text,uuid,boolean) from public, anon, authenticated;
grant execute on function public.admin_update_employee(uuid,uuid,uuid,text,text,text,uuid,boolean) to service_role;

commit;
