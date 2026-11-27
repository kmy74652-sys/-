begin;

create or replace function public.issue_approved_task_cycle(
  p_cycle_id uuid,
  p_issue_date date
) returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_cycle public.approved_task_cycles%rowtype;
  v_org public.organizations%rowtype;
  v_source public.tasks%rowtype;
  v_task_id uuid;
  v_snapshot_id uuid;
  v_snapshot jsonb;
  v_local_due timestamp;
  v_due_at timestamptz;
  v_creator uuid;
  v_idempotency text;
begin
  select * into v_cycle
  from public.approved_task_cycles
  where id = p_cycle_id and active
  for update;
  if not found then return null; end if;

  if exists (
    select 1
    from public.approved_task_cycle_issues i
    where i.cycle_id = p_cycle_id and i.issue_date = p_issue_date
  ) then
    select issued_task_id into v_task_id
    from public.approved_task_cycle_issues
    where cycle_id = p_cycle_id and issue_date = p_issue_date;
    return v_task_id;
  end if;

  -- لا تصدر نسخة جديدة ما دام أي إصدار سابق غير مكتمل أو تقريره غير معتمد.
  if exists (
    select 1
    from public.approved_task_cycle_issues i
    join public.tasks t on t.id = i.issued_task_id
    where i.cycle_id = p_cycle_id
      and i.issue_date < p_issue_date
      and (
        t.status not in ('completed_approved', 'completed')
        or (
          t.report_required
          and not exists (
            select 1 from public.task_reports r
            where r.task_id = t.id and r.status = 'approved'
          )
        )
      )
  ) then
    return null;
  end if;

  select * into v_org from public.organizations where id = v_cycle.organization_id;
  select * into v_source from public.tasks where id = v_cycle.source_task_id;
  v_creator := coalesce(v_cycle.approved_by, v_source.created_by);
  v_local_due := timezone(
    coalesce(nullif(v_org.timezone, ''), 'Asia/Aden'),
    coalesce(v_source.due_at, now())
  );
  v_due_at := make_timestamptz(
    extract(year from p_issue_date)::integer,
    extract(month from p_issue_date)::integer,
    extract(day from p_issue_date)::integer,
    extract(hour from v_local_due)::integer,
    extract(minute from v_local_due)::integer,
    extract(second from v_local_due)::double precision,
    coalesce(nullif(v_org.timezone, ''), 'Asia/Aden')
  );
  v_idempotency := 'approved-cycle:' || p_cycle_id::text || ':' || p_issue_date::text;

  insert into public.tasks (
    organization_id, branch_id, title, description, expected_result,
    priority, status, assigned_to, created_by, assigned_at, due_at,
    starts_at, task_instructions, report_required, position_code,
    report_flow, idempotency_key
  ) values (
    v_cycle.organization_id, v_cycle.branch_id, v_cycle.title,
    v_cycle.description, v_cycle.expected_result, v_cycle.priority,
    'new', v_cycle.employee_user_id, v_creator, now(), v_due_at,
    v_due_at, v_cycle.task_instructions, v_cycle.report_required,
    v_cycle.position_code, v_cycle.report_flow, v_idempotency
  ) returning id into v_task_id;

  for v_snapshot in select value from jsonb_array_elements(v_cycle.report_snapshots) loop
    insert into public.task_report_form_snapshots (
      task_id, template_id, version_id, report_required, schema,
      published_by, published_at, title, sort_order, is_required,
      organization_id
    ) values (
      v_task_id,
      nullif(v_snapshot->>'template_id', '')::uuid,
      nullif(v_snapshot->>'version_id', '')::uuid,
      coalesce((v_snapshot->>'report_required')::boolean, v_cycle.report_required),
      coalesce(v_snapshot->'schema', '[]'::jsonb), v_cycle.approved_by,
      now(), v_snapshot->>'title', coalesce((v_snapshot->>'sort_order')::integer, 0),
      coalesce((v_snapshot->>'is_required')::boolean, true), v_cycle.organization_id
    ) returning id into v_snapshot_id;
    if v_snapshot_id is not null and v_snapshot->>'source_order' = '0' then
      update public.tasks set report_form_snapshot_id = v_snapshot_id where id = v_task_id;
    end if;
  end loop;

  insert into public.approved_task_cycle_issues (cycle_id, issued_task_id, issue_date)
  values (p_cycle_id, v_task_id, p_issue_date);

  insert into public.task_activity_log (task_id, actor_id, action, details)
  values (
    v_task_id, v_cycle.approved_by, 'approved_cycle_task_issued',
    jsonb_build_object('cycle_id', p_cycle_id, 'issue_date', p_issue_date,
      'source_task_id', v_cycle.source_task_id, 'source_report_id', v_cycle.source_report_id)
  );

  update public.approved_task_cycles
  set last_issued_date = p_issue_date,
      next_issue_date = p_issue_date + 1,
      updated_at = now()
  where id = p_cycle_id;

  insert into public.notifications (
    organization_id, recipient_user_id, task_id, title, body, severity
  ) values (
    v_cycle.organization_id, v_cycle.employee_user_id, v_task_id,
    'مهمة معتمدة جديدة',
    'تم إصدار مهمة جديدة من المهمة والتقرير المعتمدين ليوم ' || to_char(p_issue_date, 'DD/MM/YYYY') || '.',
    'info'
  );
  return v_task_id;
end;
$$;

commit;
