BEGIN;

CREATE TABLE IF NOT EXISTS public.approved_task_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  source_task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL,
  source_report_id uuid REFERENCES public.task_reports(id) ON DELETE SET NULL,
  employee_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  branch_id uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  position_code text,
  title text NOT NULL,
  description text,
  expected_result text,
  priority public.task_priority NOT NULL DEFAULT 'normal',
  task_instructions text,
  report_required boolean NOT NULL DEFAULT false,
  report_flow text NOT NULL DEFAULT 'legacy',
  report_schema jsonb NOT NULL DEFAULT '[]'::jsonb,
  report_snapshots jsonb NOT NULL DEFAULT '[]'::jsonb,
  recurrence_type text NOT NULL DEFAULT 'daily' CHECK (recurrence_type = 'daily'),
  active boolean NOT NULL DEFAULT true,
  approved_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_at timestamptz NOT NULL DEFAULT now(),
  next_issue_date date NOT NULL,
  last_issued_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_report_id),
  CHECK (jsonb_typeof(report_schema) = 'array'),
  CHECK (jsonb_typeof(report_snapshots) = 'array')
);

CREATE TABLE IF NOT EXISTS public.approved_task_cycle_issues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES public.approved_task_cycles(id) ON DELETE CASCADE,
  issued_task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  issue_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cycle_id, issue_date),
  UNIQUE (issued_task_id)
);

CREATE INDEX IF NOT EXISTS approved_task_cycles_due_idx
  ON public.approved_task_cycles (active, next_issue_date)
  WHERE active;
CREATE INDEX IF NOT EXISTS approved_task_cycles_employee_idx
  ON public.approved_task_cycles (employee_user_id, active);
CREATE INDEX IF NOT EXISTS approved_task_cycle_issues_cycle_date_idx
  ON public.approved_task_cycle_issues (cycle_id, issue_date DESC);

ALTER TABLE public.approved_task_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approved_task_cycle_issues ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS approved_task_cycles_management_read ON public.approved_task_cycles;
CREATE POLICY approved_task_cycles_management_read
  ON public.approved_task_cycles FOR SELECT TO authenticated
  USING (public.has_org_permission(organization_id, 'tasks.review', NULL::uuid));

DROP POLICY IF EXISTS approved_task_cycle_issues_management_read ON public.approved_task_cycle_issues;
CREATE POLICY approved_task_cycle_issues_management_read
  ON public.approved_task_cycle_issues FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public.approved_task_cycles c
    WHERE c.id = cycle_id
      AND public.has_org_permission(c.organization_id, 'tasks.review', NULL::uuid)
  ));

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
    SELECT 1 FROM public.approved_task_cycle_issues
    WHERE cycle_id = p_cycle_id AND issue_date = p_issue_date
  ) THEN
    SELECT issued_task_id INTO v_task_id
    FROM public.approved_task_cycle_issues
    WHERE cycle_id = p_cycle_id AND issue_date = p_issue_date;
    RETURN v_task_id;
  END IF;

  SELECT * INTO v_org FROM public.organizations WHERE id = v_cycle.organization_id;
  SELECT * INTO v_source FROM public.tasks WHERE id = v_cycle.source_task_id;
  v_creator := coalesce(v_cycle.approved_by, v_source.created_by);
  v_local_due := timezone(coalesce(nullif(v_org.timezone, ''), 'Asia/Aden'), coalesce(v_source.due_at, now()));
  v_due_at := make_timestamptz(
    extract(year from p_issue_date)::integer,
    extract(month from p_issue_date)::integer,
    extract(day from p_issue_date)::integer,
    extract(hour from v_local_due)::double precision,
    extract(minute from v_local_due)::double precision,
    extract(second from v_local_due),
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
      UPDATE public.tasks SET report_form_snapshot_id = v_snapshot_id WHERE id = v_task_id;
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

  INSERT INTO public.notifications (organization_id, recipient_user_id, task_id, title, body, severity)
  VALUES (
    v_cycle.organization_id, v_cycle.employee_user_id, v_task_id,
    'مهمة معتمدة جديدة',
    'تم إصدار مهمة جديدة من المهمة والتقرير المعتمدين ليوم ' || to_char(p_issue_date, 'DD/MM/YYYY') || '.',
    'info'
  );
  RETURN v_task_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_daily_approved_task_cycles()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_cycle public.approved_task_cycles%ROWTYPE;
  v_today date;
  v_count integer := 0;
BEGIN
  FOR v_cycle IN
    SELECT c.*
    FROM public.approved_task_cycles c
    JOIN public.organizations o ON o.id = c.organization_id
    WHERE c.active
      AND c.next_issue_date <= (now() AT TIME ZONE coalesce(nullif(o.timezone, ''), 'Asia/Aden'))::date
    FOR UPDATE OF c SKIP LOCKED
  LOOP
    v_today := (now() AT TIME ZONE coalesce((SELECT timezone FROM public.organizations WHERE id = v_cycle.organization_id), 'Asia/Aden'))::date;
    IF public.issue_approved_task_cycle(v_cycle.id, v_today) IS NOT NULL THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.capture_approved_task_cycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_task public.tasks%ROWTYPE;
  v_snapshots jsonb;
  v_approved_by uuid;
  v_next_date date;
BEGIN
  IF NEW.status <> 'approved' OR OLD.status = 'approved' THEN RETURN NEW; END IF;
  SELECT * INTO v_task FROM public.tasks WHERE id = NEW.task_id;
  IF NOT FOUND OR v_task.deleted_at IS NOT NULL THEN RETURN NEW; END IF;
  v_approved_by := coalesce(NEW.reviewed_by, v_task.created_by);
  v_next_date := (now() AT TIME ZONE coalesce((SELECT timezone FROM public.organizations WHERE id = v_task.organization_id), 'Asia/Aden'))::date + 1;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'source_order', row_number,
    'template_id', s.template_id,
    'version_id', s.version_id,
    'report_required', s.report_required,
    'schema', s.schema,
    'title', s.title,
    'sort_order', s.sort_order,
    'is_required', s.is_required
  ) ORDER BY s.sort_order, s.id), '[]'::jsonb)
  INTO v_snapshots
  FROM (
    SELECT s.*, row_number() OVER (ORDER BY s.sort_order, s.id) - 1 AS row_number
    FROM public.task_report_form_snapshots s
    WHERE s.task_id = v_task.id
  ) s;

  INSERT INTO public.approved_task_cycles (
    organization_id, source_task_id, source_report_id, employee_user_id,
    branch_id, position_code, title, description, expected_result, priority,
    task_instructions, report_required, report_flow, report_schema,
    report_snapshots, approved_by, approved_at, next_issue_date
  ) VALUES (
    v_task.organization_id, v_task.id, NEW.id, v_task.assigned_to,
    v_task.branch_id, v_task.position_code, v_task.title, v_task.description,
    v_task.expected_result, v_task.priority, v_task.task_instructions,
    v_task.report_required, v_task.report_flow, '[]'::jsonb,
    v_snapshots, v_approved_by, coalesce(NEW.reviewed_at, now()), v_next_date
  ) ON CONFLICT (source_report_id) DO NOTHING;
  RETURN NEW;
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
    'priority', c.priority,
    'report_required', c.report_required,
    'active', c.active,
    'approved_at', c.approved_at,
    'next_issue_date', c.next_issue_date,
    'last_issued_date', c.last_issued_date,
    'issued_count', (SELECT count(*) FROM public.approved_task_cycle_issues i WHERE i.cycle_id = c.id)
  )
  FROM public.approved_task_cycles c
  LEFT JOIN public.organization_memberships m ON m.organization_id = c.organization_id AND m.user_id = c.employee_user_id
  LEFT JOIN public.branches b ON b.id = c.branch_id
  WHERE public.has_org_permission(c.organization_id, 'tasks.review', NULL::uuid)
  ORDER BY c.active DESC, c.next_issue_date, c.approved_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_approved_task_cycle_active(p_cycle_id uuid, p_active boolean)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE v_org uuid;
BEGIN
  SELECT organization_id INTO v_org FROM public.approved_task_cycles WHERE id = p_cycle_id;
  IF v_org IS NULL OR NOT public.has_org_permission(v_org, 'tasks.review', NULL::uuid) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'cycle_management_not_allowed';
  END IF;
  UPDATE public.approved_task_cycles SET active = p_active, updated_at = now() WHERE id = p_cycle_id;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_approved_task_cycle_now(p_cycle_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE v_org uuid; v_task_id uuid;
BEGIN
  SELECT organization_id INTO v_org FROM public.approved_task_cycles WHERE id = p_cycle_id;
  IF v_org IS NULL OR NOT public.has_org_permission(v_org, 'tasks.review', NULL::uuid) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'cycle_management_not_allowed';
  END IF;
  v_task_id := public.issue_approved_task_cycle(p_cycle_id, (now() AT TIME ZONE coalesce((SELECT timezone FROM public.organizations WHERE id = v_org), 'Asia/Aden'))::date);
  RETURN v_task_id;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_approved_task_cycle(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.issue_daily_approved_task_cycles() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.capture_approved_task_cycle() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_approved_task_cycles() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_approved_task_cycle_active(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.issue_approved_task_cycle_now(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_approved_task_cycles() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_approved_task_cycle_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_approved_task_cycle_now(uuid) TO authenticated;

DROP TRIGGER IF EXISTS task_reports_capture_approved_cycle ON public.task_reports;
CREATE TRIGGER task_reports_capture_approved_cycle
after update of status on public.task_reports
for each row execute function public.capture_approved_task_cycle();

DO $$
BEGIN
  IF to_regnamespace('cron') IS NOT NULL THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'alshaeri-approved-task-daily-reissue';
    PERFORM cron.schedule(
      'alshaeri-approved-task-daily-reissue',
      '55 20 * * *',
      $job$SELECT public.issue_daily_approved_task_cycles();$job$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Daily approved task scheduler was not installed: %', SQLERRM;
END;
$$;

COMMIT;
