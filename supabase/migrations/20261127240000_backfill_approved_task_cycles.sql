BEGIN;

CREATE OR REPLACE FUNCTION public.backfill_approved_task_cycles()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_report record;
  v_snapshots jsonb;
  v_next_date date;
  v_count integer := 0;
BEGIN
  FOR v_report IN
    SELECT r.id AS report_id, r.reviewed_by, r.reviewed_at,
           t.*,
           coalesce(o.timezone, 'Asia/Aden') AS organization_timezone
    FROM public.task_reports r
    JOIN public.tasks t ON t.id = r.task_id
    JOIN public.organizations o ON o.id = t.organization_id
    WHERE r.status = 'approved'
      AND t.report_flow = 'multi_form'
      AND t.deleted_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.approved_task_cycles c
        WHERE c.source_report_id = r.id
      )
    ORDER BY r.reviewed_at NULLS LAST
    LIMIT 500
  LOOP
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
      WHERE s.task_id = v_report.id
    ) s;

    v_next_date := (coalesce(v_report.reviewed_at, now())
      AT TIME ZONE v_report.organization_timezone)::date + 1;

    INSERT INTO public.approved_task_cycles (
      organization_id, source_task_id, source_report_id, employee_user_id,
      branch_id, position_code, title, description, expected_result, priority,
      task_instructions, report_required, report_flow, report_schema,
      report_snapshots, approved_by, approved_at, next_issue_date
    ) VALUES (
      v_report.organization_id, v_report.id, v_report.report_id,
      v_report.assigned_to, v_report.branch_id, v_report.position_code,
      v_report.title, v_report.description, v_report.expected_result,
      v_report.priority, v_report.task_instructions, v_report.report_required,
      v_report.report_flow, '[]'::jsonb, v_snapshots,
      coalesce(v_report.reviewed_by, v_report.created_by),
      coalesce(v_report.reviewed_at, now()), v_next_date
    ) ON CONFLICT (source_report_id) DO NOTHING;

    IF FOUND THEN v_count := v_count + 1; END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.backfill_approved_task_cycles() FROM PUBLIC, anon, authenticated;

SELECT public.backfill_approved_task_cycles();

COMMIT;
