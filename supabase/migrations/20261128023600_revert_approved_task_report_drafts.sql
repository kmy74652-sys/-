BEGIN;

CREATE OR REPLACE FUNCTION public.issue_approved_task_cycle(
  p_cycle_id uuid,
  p_issue_date date
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_cycle public.approved_task_cycles%ROWTYPE;
  v_org public.organizations%ROWTYPE;
  v_source public.tasks%ROWTYPE;
  v_task_id uuid;
  v_snapshot_id uuid;
  v_snapshot jsonb;
  v_local_due timestamp;
  v_due_at timestamptz;
  v_creator uuid;
  v_idempotency text;
BEGIN
  SELECT * INTO v_cycle
  FROM public.approved_task_cycles
  WHERE id = p_cycle_id AND active
  FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;

  IF EXISTS (
    SELECT 1 FROM public.approved_task_cycle_issues i
    WHERE i.cycle_id = p_cycle_id AND i.issue_date = p_issue_date
  ) THEN
    SELECT issued_task_id INTO v_task_id
    FROM public.approved_task_cycle_issues
    WHERE cycle_id = p_cycle_id AND issue_date = p_issue_date;
    RETURN v_task_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.approved_task_cycle_issues i
    JOIN public.tasks t ON t.id = i.issued_task_id
    WHERE i.cycle_id = p_cycle_id
      AND i.issue_date < p_issue_date
      AND (
        t.status <> 'completed_approved'
        OR (
          t.report_required
          AND NOT EXISTS (
            SELECT 1 FROM public.task_reports r
            WHERE r.task_id = t.id AND r.status = 'approved'
          )
        )
      )
  ) THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_org FROM public.organizations WHERE id = v_cycle.organization_id;
  SELECT * INTO v_source FROM public.tasks WHERE id = v_cycle.source_task_id;
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

  INSERT INTO public.tasks (
    organization_id, branch_id, title, description, expected_result,
    priority, status, assigned_to, created_by, assigned_at, due_at,
    starts_at, task_instructions, report_required, position_code,
    report_flow, idempotency_key
  ) VALUES (
    v_cycle.organization_id, v_cycle.branch_id, v_cycle.title,
    v_cycle.description, v_cycle.expected_result, v_cycle.priority,
    'new', v_cycle.employee_user_id, v_creator, now(), v_due_at,
    v_due_at, v_cycle.task_instructions, v_cycle.report_required,
    v_cycle.position_code, v_cycle.report_flow, v_idempotency
  ) RETURNING id INTO v_task_id;

  FOR v_snapshot IN SELECT value FROM jsonb_array_elements(v_cycle.report_snapshots) LOOP
    INSERT INTO public.task_report_form_snapshots (
      task_id, template_id, version_id, report_required, schema,
      published_by, published_at, title, sort_order, is_required,
      organization_id
    ) VALUES (
      v_task_id,
      NULLIF(v_snapshot->>'template_id', '')::uuid,
      NULLIF(v_snapshot->>'version_id', '')::uuid,
      coalesce((v_snapshot->>'report_required')::boolean, v_cycle.report_required),
      coalesce(v_snapshot->'schema', '[]'::jsonb), v_cycle.approved_by,
      now(), v_snapshot->>'title', coalesce((v_snapshot->>'sort_order')::integer, 0),
      coalesce((v_snapshot->>'is_required')::boolean, true), v_cycle.organization_id
    ) RETURNING id INTO v_snapshot_id;
    IF v_snapshot_id IS NOT NULL AND v_snapshot->>'source_order' = '0' THEN
      PERFORM set_config('alshaari.approved_cycle_issue', 'on', true);
      UPDATE public.tasks SET report_form_snapshot_id = v_snapshot_id WHERE id = v_task_id;
      PERFORM set_config('alshaari.approved_cycle_issue', 'off', true);
    END IF;
  END LOOP;

  INSERT INTO public.approved_task_cycle_issues (cycle_id, issued_task_id, issue_date)
  VALUES (p_cycle_id, v_task_id, p_issue_date);

  INSERT INTO public.task_activity_log (task_id, actor_id, action, details)
  VALUES (
    v_task_id, v_cycle.approved_by, 'approved_cycle_task_issued',
    jsonb_build_object('cycle_id', p_cycle_id, 'issue_date', p_issue_date,
      'source_task_id', v_cycle.source_task_id, 'source_report_id', v_cycle.source_report_id)
  );

  UPDATE public.approved_task_cycles
  SET last_issued_date = p_issue_date,
      next_issue_date = p_issue_date + 1,
      updated_at = now()
  WHERE id = p_cycle_id;

  INSERT INTO public.notifications (
    organization_id, recipient_user_id, task_id, title, body, severity
  ) VALUES (
    v_cycle.organization_id, v_cycle.employee_user_id, v_task_id,
    'مهمة معتمدة جديدة',
    'تم إصدار مهمة جديدة من المهمة والتقرير المعتمدين ليوم ' || to_char(p_issue_date, 'DD/MM/YYYY') || '.',
    'info'
  );
  RETURN v_task_id;
END;
$$;

DELETE FROM public.task_report_drafts d
USING public.tasks t
WHERE t.id = d.task_id
  AND t.idempotency_key LIKE 'approved-cycle:%'
  AND d.values = '{}'::jsonb;

COMMIT;
