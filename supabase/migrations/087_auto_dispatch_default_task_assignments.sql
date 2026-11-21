-- Automatically dispatch default employee task-template assignments on scheduled workdays.
-- The job runs at 00:05 Asia/Aden (21:05 UTC) and is idempotent per employee/template/date.
begin;

create or replace function public.dispatch_default_task_template_assignments(
  p_work_date date default (timezone('Asia/Aden', now()))::date
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_assignment record;
  v_task_id uuid;
  v_schema jsonb;
  v_created integer := 0;
  v_day integer;
  v_start timestamptz;
  v_due timestamptz;
  v_key text;
begin
  if p_work_date is null then
    raise exception using errcode='22023', message='work_date_required';
  end if;

  v_day := extract(dow from p_work_date)::integer;
  perform pg_advisory_xact_lock(hashtext('alshaairy-default-template-dispatch'));

  for v_assignment in
    select
      a.template_id, a.branch_id, a.employee_id as assigned_user_id,
      m.id as membership_id, m.organization_id,
      t.title, t.description, t.expected_result, t.default_priority,
      t.role_code, t.instructions, t.category_id, t.subcategory_id,
      t.version as template_version, s.start_time, s.end_time, s.timezone,
      coalesce(owner_user.user_id, m.user_id) as created_by
    from public.task_template_assignments a
    join public.task_templates t
      on t.id = a.template_id and t.is_active
    join public.branches b
      on b.id = a.branch_id and b.organization_id = t.organization_id and b.is_active
    join public.organization_memberships m
      on m.user_id = a.employee_id
     and m.organization_id = t.organization_id
     and m.is_active
    join public.role_assignments ra
      on ra.membership_id = m.id
     and ra.organization_id = m.organization_id
     and ra.role_code = t.role_code
     and ra.branch_id = a.branch_id
    join public.employee_work_schedules s
      on s.membership_id = m.id
     and s.organization_id = m.organization_id
     and s.is_active
     and s.effective_from <= p_work_date
     and (s.effective_to is null or s.effective_to >= p_work_date)
     and s.work_days @> jsonb_build_array(v_day)
    left join lateral (
      select om.user_id
      from public.organization_memberships om
      join public.role_assignments ora
        on ora.membership_id = om.id
       and ora.organization_id = om.organization_id
       and ora.role_code = 'owner'
      where om.organization_id = m.organization_id and om.is_active
      order by om.created_at
      limit 1
    ) owner_user on true
    where a.assignment_type = 'default'
      and a.employee_id is not null
      and a.branch_id is not null
  loop
    v_start := (p_work_date + v_assignment.start_time) at time zone coalesce(v_assignment.timezone, 'Asia/Aden');
    v_due := (p_work_date + v_assignment.end_time) at time zone coalesce(v_assignment.timezone, 'Asia/Aden');
    v_key := 'auto-template:' || v_assignment.template_id::text || ':' ||
             v_assignment.assigned_user_id::text || ':' || to_char(p_work_date, 'YYYY-MM-DD');

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'key', f.field_key, 'label', f.label, 'type', f.field_type,
          'required', f.is_required, 'repeatable', f.repeatable,
          'validation', f.validation, 'options', f.options, 'config', f.config
        ) order by f.sort_order
      ),
      '[]'::jsonb
    )
    into v_schema
    from public.task_template_report_fields f
    where f.template_id = v_assignment.template_id;

    insert into public.tasks(
      organization_id, branch_id, title, description, expected_result,
      assigned_to, created_by, due_at, starts_at, priority, template_id,
      position_code, report_flow, task_instructions, category_id, subcategory_id,
      proof_required, proof_instructions, template_version, report_required, idempotency_key
    )
    values(
      v_assignment.organization_id, v_assignment.branch_id, v_assignment.title,
      coalesce(v_assignment.description, ''), v_assignment.expected_result,
      v_assignment.assigned_user_id, v_assignment.created_by, v_due, v_start,
      v_assignment.default_priority::task_priority, v_assignment.template_id,
      v_assignment.role_code, 'multi_form', v_assignment.instructions,
      v_assignment.category_id, v_assignment.subcategory_id, false, null,
      v_assignment.template_version, jsonb_array_length(v_schema) > 0, v_key
    )
    on conflict (organization_id, idempotency_key)
      where idempotency_key is not null
      do nothing
    returning id into v_task_id;

    if v_task_id is not null then
      insert into public.task_execution_steps(
        task_id, source_template_step_id, title, instructions, sort_order,
        is_required, evidence_required, evidence_instructions
      )
      select v_task_id, st.id, st.title, st.instructions, st.sort_order,
             st.is_required, st.evidence_required, st.evidence_instructions
      from public.task_template_steps st
      where st.template_id = v_assignment.template_id
      order by st.sort_order;

      if jsonb_array_length(v_schema) > 0 then
        insert into public.task_report_form_snapshots(
          task_id, template_id, version_id, report_required, schema,
          published_by, title, sort_order, is_required, organization_id, task_report_form_id
        )
        values(
          v_task_id, null, null, true, v_schema, v_assignment.created_by,
          v_assignment.title || ' — تقرير المهمة', 0, true,
          v_assignment.organization_id, null
        );
      end if;

      insert into public.task_activity_log(task_id, actor_id, action, details)
      values(
        v_task_id, v_assignment.created_by, 'task_assigned',
        jsonb_build_object(
          'template_id', v_assignment.template_id,
          'template_version', v_assignment.template_version,
          'delivery', 'sent',
          'assignment_mode', 'automatic_default',
          'work_date', p_work_date
        )
      );
      v_created := v_created + 1;
    end if;
  end loop;

  return v_created;
end;
$$;

revoke all on function public.dispatch_default_task_template_assignments(date)
  from public, anon, authenticated;

-- pg_cron uses UTC; 21:05 UTC is 00:05 the following day in Asia/Aden.
select cron.schedule(
  'alshaairy-default-template-dispatch',
  '5 21 * * *',
  'select public.dispatch_default_task_template_assignments();'
);

commit;
