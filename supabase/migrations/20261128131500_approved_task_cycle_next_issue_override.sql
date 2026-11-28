BEGIN;

ALTER TABLE public.approved_task_cycles
  ADD COLUMN IF NOT EXISTS next_issue_overrides jsonb NOT NULL DEFAULT '{}'::jsonb;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'approved_task_cycles_next_issue_overrides_object'
      AND conrelid = 'public.approved_task_cycles'::regclass
  ) THEN
    ALTER TABLE public.approved_task_cycles
      ADD CONSTRAINT approved_task_cycles_next_issue_overrides_object
      CHECK (jsonb_typeof(next_issue_overrides) = 'object');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_approved_task_cycle_next_issue(
  p_cycle_id uuid,
  p_title text,
  p_description text,
  p_expected_result text,
  p_priority text,
  p_task_instructions text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org uuid;
  v_title text := nullif(trim(coalesce(p_title, '')), '');
  v_priority public.task_priority;
  v_overrides jsonb;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.approved_task_cycles
  WHERE id = p_cycle_id AND active;

  IF v_org IS NULL OR NOT public.has_org_permission(v_org, 'tasks.review', NULL::uuid) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'cycle_management_not_allowed';
  END IF;
  IF v_title IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'cycle_title_required';
  END IF;

  BEGIN
    v_priority := coalesce(nullif(trim(p_priority), ''), 'normal')::public.task_priority;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'invalid_task_priority';
  END;

  v_overrides := jsonb_build_object(
    'title', v_title,
    'description', nullif(trim(coalesce(p_description, '')), ''),
    'expected_result', nullif(trim(coalesce(p_expected_result, '')), ''),
    'priority', v_priority::text,
    'task_instructions', nullif(trim(coalesce(p_task_instructions, '')), '')
  );

  UPDATE public.approved_task_cycles
  SET next_issue_overrides = v_overrides,
      updated_at = now()
  WHERE id = p_cycle_id;

  RETURN jsonb_build_object(
    'id', p_cycle_id,
    'next_issue_overrides', v_overrides,
    'updated_at', now()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_approved_task_cycle_next_issue(
  p_cycle_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE v_org uuid;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.approved_task_cycles
  WHERE id = p_cycle_id AND active;
  IF v_org IS NULL OR NOT public.has_org_permission(v_org, 'tasks.review', NULL::uuid) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'cycle_management_not_allowed';
  END IF;
  UPDATE public.approved_task_cycles
  SET next_issue_overrides = '{}'::jsonb, updated_at = now()
  WHERE id = p_cycle_id;
  RETURN FOUND;
END;
$$;

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
  v_title text;
  v_description text;
  v_expected_result text;
  v_priority public.task_priority;
  v_task_instructions text;
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
  v_title := coalesce(nullif(v_cycle.next_issue_overrides->>'title', ''), v_cycle.title);
  v_description := coalesce(nullif(v_cycle.next_issue_overrides->>'description', ''), v_cycle.description);
  v_expected_result := coalesce(nullif(v_cycle.next_issue_overrides->>'expected_result', ''), v_cycle.expected_result);
  v_priority := coalesce(nullif(v_cycle.next_issue_overrides->>'priority', '')::public.task_priority, v_cycle.priority);
  v_task_instructions := coalesce(nullif(v_cycle.next_issue_overrides->>'task_instructions', ''), v_cycle.task_instructions);
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
    v_cycle.organization_id, v_cycle.branch_id, v_title,
    v_description, v_expected_result, v_priority,
    'new', v_cycle.employee_user_id, v_creator, now(), v_due_at,
    v_due_at, v_task_instructions, v_cycle.report_required,
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
      'source_task_id', v_cycle.source_task_id, 'source_report_id', v_cycle.source_report_id,
      'used_next_issue_overrides', v_cycle.next_issue_overrides <> '{}'::jsonb)
  );
  UPDATE public.approved_task_cycles
  SET last_issued_date = p_issue_date,
      next_issue_date = p_issue_date + 1,
      next_issue_overrides = '{}'::jsonb,
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

CREATE OR REPLACE FUNCTION public.list_approved_task_cycles()
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', c.id,
    'organization_id', c.organization_id,
    'source_task_id', c.source_task_id,
    'source_report_id', c.source_report_id,
    'employee_user_id', c.employee_user_id,
    'employee_name', coalesce(m.display_name, 'موظف'),
    'branch_id', c.branch_id,
    'branch_name', coalesce(b.name, 'كل الفروع'),
    'title', c.title,
    'description', c.description,
    'expected_result', c.expected_result,
    'priority', c.priority,
    'task_instructions', c.task_instructions,
    'report_required', c.report_required,
    'active', c.active,
    'approved_at', c.approved_at,
    'next_issue_date', c.next_issue_date,
    'last_issued_date', c.last_issued_date,
    'issued_count', (SELECT count(*) FROM public.approved_task_cycle_issues i WHERE i.cycle_id = c.id),
    'next_issue_overrides', c.next_issue_overrides,
    'next_issue_title', coalesce(nullif(c.next_issue_overrides->>'title', ''), c.title),
    'next_issue_description', coalesce(nullif(c.next_issue_overrides->>'description', ''), c.description),
    'next_issue_expected_result', coalesce(nullif(c.next_issue_overrides->>'expected_result', ''), c.expected_result),
    'next_issue_priority', coalesce(nullif(c.next_issue_overrides->>'priority', ''), c.priority),
    'next_issue_instructions', coalesce(nullif(c.next_issue_overrides->>'task_instructions', ''), c.task_instructions),
    'has_next_issue_override', c.next_issue_overrides <> '{}'::jsonb
  )
  FROM public.approved_task_cycles c
  LEFT JOIN public.organization_memberships m ON m.organization_id = c.organization_id AND m.user_id = c.employee_user_id
  LEFT JOIN public.branches b ON b.id = c.branch_id
  WHERE public.has_org_permission(c.organization_id, 'tasks.review', NULL::uuid)
  ORDER BY c.active DESC, c.next_issue_date, c.approved_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.update_approved_task_cycle_next_issue(uuid, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_approved_task_cycle_next_issue(uuid, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.clear_approved_task_cycle_next_issue(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_approved_task_cycle_next_issue(uuid) TO authenticated;

COMMIT;
