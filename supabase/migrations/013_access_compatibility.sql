-- Compatibility helpers for clients that expect public.is_owner/is_manager/can_access_task.
-- User identity is auth.users.id; business identity is employees.id.

create or replace function public.is_owner(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth, app
as $$
  select exists (
    select 1
    from public.employees e
    join public.employee_roles er
      on er.institution_id = e.institution_id
     and er.employee_id = e.id
    join public.roles r
      on r.institution_id = er.institution_id
     and r.id = er.role_id
    where e.auth_user_id = p_user_id
      and e.status = 'active'
      and r.code = 'owner'
  );
$$;

create or replace function public.is_manager(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth, app
as $$
  select exists (
    select 1
    from public.employees e
    join public.employee_roles er
      on er.institution_id = e.institution_id
     and er.employee_id = e.id
    join public.roles r
      on r.institution_id = er.institution_id
     and r.id = er.role_id
    where e.auth_user_id = p_user_id
      and e.status = 'active'
      and r.code in ('owner', 'admin_followup')
  );
$$;

create or replace function public.can_access_task(
  p_task_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, auth, app
as $$
  select exists (
    select 1
    from public.tasks t
    join public.employees e
      on e.institution_id = t.institution_id
     and e.auth_user_id = p_user_id
     and e.status = 'active'
    where t.id = p_task_id
      and (
        public.is_owner(p_user_id)
        or (
          public.is_manager(p_user_id)
          and t.institution_id = e.institution_id
        )
        or t.assignee_employee_id = e.id
      )
  );
$$;

revoke all on function public.is_owner(uuid) from public;
revoke all on function public.is_manager(uuid) from public;
revoke all on function public.can_access_task(uuid, uuid) from public;
grant execute on function public.is_owner(uuid) to authenticated;
grant execute on function public.is_manager(uuid) to authenticated;
grant execute on function public.can_access_task(uuid, uuid) to authenticated;
