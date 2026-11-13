do $$
declare
  institution_row record;
  bootstrap_employee uuid;
  bootstrap_branch uuid;
  owner_role uuid;
begin
  for institution_row in select id from public.institutions loop
    perform app.seed_institution_defaults(institution_row.id);
    select id into owner_role from public.roles where institution_id = institution_row.id and code = 'owner';
    select e.id into bootstrap_employee
    from public.employees e
    where e.institution_id = institution_row.id and e.status = 'active'
    order by e.created_at, e.employee_no
    limit 1;
    if bootstrap_employee is not null then
      insert into public.employee_roles (institution_id, employee_id, role_id)
      values (institution_row.id, bootstrap_employee, owner_role)
      on conflict do nothing;
      select b.id into bootstrap_branch
      from public.branches b
      where b.institution_id = institution_row.id and b.is_active
      order by b.created_at, b.name
      limit 1;
      if bootstrap_branch is not null then
        insert into public.employee_branches (institution_id, employee_id, branch_id, is_default)
        values (institution_row.id, bootstrap_employee, bootstrap_branch, true)
        on conflict (institution_id, employee_id, branch_id) do update set is_default = true;
        update public.employees
        set base_branch_id = coalesce(base_branch_id, bootstrap_branch)
        where institution_id = institution_row.id and id = bootstrap_employee;
      end if;
    end if;
  end loop;
end $$;
