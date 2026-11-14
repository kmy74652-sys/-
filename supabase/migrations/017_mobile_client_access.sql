begin;

-- Expose only the authenticated caller's employee profile and effective access.
-- This avoids widening roles/permissions table policies just to render the mobile home screen.
create or replace function public.mobile_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, app
as $$
declare
  current_user_id uuid := auth.uid();
  employee_row public.employees%rowtype;
begin
  if current_user_id is null then
    return null;
  end if;

  select e.*
    into employee_row
  from public.employees e
  where e.auth_user_id = current_user_id
    and e.status = 'active'
  limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'employee', jsonb_build_object(
      'id', employee_row.id,
      'institutionId', employee_row.institution_id,
      'employeeNo', employee_row.employee_no,
      'fullName', employee_row.full_name,
      'email', employee_row.email,
      'phone', employee_row.phone,
      'status', employee_row.status,
      'lastLoginAt', employee_row.last_login_at,
      'roles', coalesce((
        select jsonb_agg(jsonb_build_object('code', r.code, 'nameAr', r.name_ar) order by r.name_ar)
        from public.employee_roles er
        join public.roles r
          on r.institution_id = er.institution_id
         and r.id = er.role_id
        where er.institution_id = employee_row.institution_id
          and er.employee_id = employee_row.id
      ), '[]'::jsonb),
      'permissions', coalesce((
        select jsonb_agg(effective.permission_code order by effective.permission_code)
        from (
          select rp.permission_code
          from public.employee_roles er
          join public.role_permissions rp
            on rp.institution_id = er.institution_id
           and rp.role_id = er.role_id
          where er.institution_id = employee_row.institution_id
            and er.employee_id = employee_row.id
            and not exists (
              select 1
              from public.employee_permission_overrides override_row
              where override_row.institution_id = employee_row.institution_id
                and override_row.employee_id = employee_row.id
                and override_row.permission_code = rp.permission_code
                and not override_row.allowed
            )
          union
          select override_row.permission_code
          from public.employee_permission_overrides override_row
          where override_row.institution_id = employee_row.institution_id
            and override_row.employee_id = employee_row.id
            and override_row.allowed
        ) effective
      ), '[]'::jsonb),
      'branches', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', b.id,
          'code', b.code,
          'name', b.name,
          'isDefault', eb.is_default
        ) order by eb.is_default desc, b.name)
        from public.employee_branches eb
        join public.branches b
          on b.institution_id = eb.institution_id
         and b.id = eb.branch_id
        where eb.institution_id = employee_row.institution_id
          and eb.employee_id = employee_row.id
      ), '[]'::jsonb)
    )
  );
end;
$$;

revoke all on function public.mobile_my_profile() from public, anon, authenticated;
grant execute on function public.mobile_my_profile() to authenticated;

-- Match the former API gate before returning rows to a mobile authenticated client.
drop policy if exists tasks_read on public.tasks;
create policy tasks_read on public.tasks for select to authenticated
using (
  institution_id = app.current_institution_id()
  and app.has_permission('tasks.read')
  and (
    assignee_employee_id = app.current_employee_id()
    or created_by = app.current_employee_id()
    or app.has_permission('tasks.read_all')
  )
);

-- The existing workflow functions are service-role-only. These wrappers derive the actor
-- from auth.uid() and preserve the same database-enforced transition/review rules.
create or replace function public.mobile_record_task_update(
  p_task_id uuid,
  p_status public.task_status,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, app
as $$
declare
  v_employee_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  v_employee_id := app.current_employee_id();
  if v_employee_id is null then
    raise exception using errcode = '42501', message = 'employee_not_active';
  end if;
  if not app.has_permission('tasks.read') then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return app.record_task_update(p_task_id, v_employee_id, p_status, p_note);
end;
$$;

revoke all on function public.mobile_record_task_update(uuid, public.task_status, text) from public, anon, authenticated;
grant execute on function public.mobile_record_task_update(uuid, public.task_status, text) to authenticated;

create or replace function public.mobile_review_task(
  p_task_id uuid,
  p_decision public.task_status,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, app
as $$
declare
  v_employee_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  v_employee_id := app.current_employee_id();
  if v_employee_id is null then
    raise exception using errcode = '42501', message = 'employee_not_active';
  end if;
  if not app.has_permission('tasks.review') then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return app.review_task(p_task_id, v_employee_id, p_decision, p_note);
end;
$$;

revoke all on function public.mobile_review_task(uuid, public.task_status, text) from public, anon, authenticated;
grant execute on function public.mobile_review_task(uuid, public.task_status, text) to authenticated;

-- Submit the report and transition the task in one transaction. Actor/institution are
-- derived from the authenticated session rather than accepted from the client payload.
create or replace function public.mobile_submit_task_report(
  p_task_id uuid,
  p_values jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, app
as $$
declare
  v_employee_id uuid;
  v_institution_id uuid;
  task_row public.tasks%rowtype;
  report_row public.task_reports%rowtype;
  report_field jsonb;
  field_key text;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  v_employee_id := app.current_employee_id();
  v_institution_id := app.current_institution_id();
  if v_employee_id is null or v_institution_id is null then
    raise exception using errcode = '42501', message = 'employee_not_active';
  end if;
  if not app.has_permission('tasks.read') then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_task_report_payload';
  end if;

  select t.*
    into task_row
  from public.tasks t
  where t.id = p_task_id
    and t.institution_id = v_institution_id
  for update;

  if not found or task_row.assignee_employee_id <> v_employee_id then
    raise exception using errcode = 'P0002', message = 'task_not_found';
  end if;
  if task_row.status not in ('in_progress', 'rejected') then
    raise exception using errcode = '22023', message = 'task_report_not_allowed';
  end if;

  for report_field in
    select value from jsonb_array_elements(coalesce(task_row.report_schema, '[]'::jsonb)) as fields(value)
  loop
    if lower(coalesce(report_field ->> 'required', 'false')) = 'true' then
      field_key := nullif(report_field ->> 'key', '');
      if field_key is not null and coalesce(p_values ->> field_key, '') = '' then
        raise exception using errcode = '22023', message = 'required_report_field_missing';
      end if;
    end if;
  end loop;

  insert into public.task_reports (institution_id, task_id, submitted_by, values)
  values (v_institution_id, task_row.id, v_employee_id, p_values)
  returning * into report_row;

  perform app.record_task_update(
    task_row.id,
    v_employee_id,
    'submitted',
    'تم رفع تقرير المهمة للمراجعة'
  );

  return jsonb_build_object('report', jsonb_build_object(
    'id', report_row.id,
    'task_id', report_row.task_id,
    'submitted_by', report_row.submitted_by,
    'values', report_row.values,
    'created_at', report_row.created_at
  ));
end;
$$;

revoke all on function public.mobile_submit_task_report(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.mobile_submit_task_report(uuid, jsonb) to authenticated;

commit;
