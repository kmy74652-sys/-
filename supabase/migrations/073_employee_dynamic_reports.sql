BEGIN;

CREATE TABLE IF NOT EXISTS public.employee_dynamic_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES public.report_form_templates(id) ON DELETE RESTRICT,
  version_id uuid NOT NULL REFERENCES public.report_form_versions(id) ON DELETE RESTRICT,
  employee_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_code text NOT NULL,
  branch_id uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  report_date date NOT NULL,
  status text NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted','approved','returned')),
  values jsonb NOT NULL DEFAULT '{}'::jsonb,
  review_note text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (template_id, version_id, employee_user_id, report_date)
);

CREATE INDEX IF NOT EXISTS employee_dynamic_reports_employee_date_idx
  ON public.employee_dynamic_reports (employee_user_id, report_date DESC);

ALTER TABLE public.employee_dynamic_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employee_dynamic_reports_employee_read ON public.employee_dynamic_reports;
CREATE POLICY employee_dynamic_reports_employee_read ON public.employee_dynamic_reports
  FOR SELECT TO authenticated
  USING (employee_user_id = auth.uid());

DROP POLICY IF EXISTS employee_dynamic_reports_management_read ON public.employee_dynamic_reports;
CREATE POLICY employee_dynamic_reports_management_read ON public.employee_dynamic_reports
  FOR SELECT TO authenticated
  USING (public.report_designer_allowed_for_org(organization_id));

CREATE OR REPLACE FUNCTION public.list_my_dynamic_report_forms()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION USING errcode = '28000', message = 'not_authenticated';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(row_data ORDER BY title)
    FROM (
      SELECT DISTINCT ON (t.id)
        jsonb_build_object(
          'template_id', t.id,
          'version_id', v.id,
          'title', t.title,
          'description', t.description,
          'role_code', t.role_code,
          'report_date', (now() AT TIME ZONE 'Asia/Aden')::date,
          'status', current_report.status,
          'review_note', current_report.review_note,
          'values', COALESCE(current_report.values, '{}'::jsonb),
          'fields', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
              'key', f.field_key,
              'label', f.label,
              'description', f.description,
              'type', f.field_type,
              'required', f.is_required,
              'repeatable', f.repeatable,
              'options', f.options,
              'validation', f.validation,
              'config', f.config
            ) ORDER BY f.sort_order)
            FROM public.report_form_version_fields f
            WHERE f.version_id = v.id
          ), '[]'::jsonb)
        ) AS row_data,
        t.title
      FROM public.report_form_templates t
      JOIN public.report_form_versions v
        ON v.template_id = t.id
       AND v.status = 'published'
       AND v.approved_by IS NOT NULL
       AND v.approved_at IS NOT NULL
       AND v.version_no = (
         SELECT max(v2.version_no)
         FROM public.report_form_versions v2
         WHERE v2.template_id = t.id
           AND v2.status = 'published'
           AND v2.approved_by IS NOT NULL
           AND v2.approved_at IS NOT NULL
       )
      JOIN public.organization_memberships m
        ON m.organization_id = t.organization_id
       AND m.user_id = v_user
       AND m.is_active
      JOIN public.role_assignments ra
        ON ra.organization_id = m.organization_id
       AND ra.membership_id = m.id
       AND ra.role_code = t.role_code
      LEFT JOIN LATERAL (
        SELECT r.status, r.review_note, r.values
        FROM public.employee_dynamic_reports r
        WHERE r.template_id = t.id
          AND r.version_id = v.id
          AND r.employee_user_id = v_user
          AND r.report_date = (now() AT TIME ZONE 'Asia/Aden')::date
        LIMIT 1
      ) current_report ON true
      WHERE t.is_active
      ORDER BY t.id, ra.branch_id NULLS LAST
    ) forms
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_my_dynamic_report(
  p_template_id uuid,
  p_version_id uuid,
  p_report_date date,
  p_values jsonb,
  p_branch_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_report_id uuid;
  v_status text;
  v_field jsonb;
  v_key text;
  v_value jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION USING errcode = '28000', message = 'not_authenticated';
  END IF;
  IF p_values IS NULL OR jsonb_typeof(p_values) <> 'object' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'invalid_dynamic_report_payload';
  END IF;

  SELECT t.organization_id, t.role_code INTO v_org, v_role
  FROM public.report_form_templates t
  JOIN public.report_form_versions v ON v.template_id = t.id
  WHERE t.id = p_template_id
    AND v.id = p_version_id
    AND t.is_active
    AND v.status = 'published'
    AND v.approved_by IS NOT NULL
    AND v.approved_at IS NOT NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'dynamic_report_form_not_available';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organization_memberships m
    JOIN public.role_assignments ra ON ra.organization_id = m.organization_id AND ra.membership_id = m.id
    WHERE m.organization_id = v_org AND m.user_id = v_user AND m.is_active AND ra.role_code = v_role
      AND (p_branch_id IS NULL OR ra.branch_id = p_branch_id)
  ) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'dynamic_report_assignment_invalid';
  END IF;

  SELECT id, status INTO v_report_id, v_status
  FROM public.employee_dynamic_reports
  WHERE template_id = p_template_id AND version_id = p_version_id
    AND employee_user_id = v_user AND report_date = p_report_date
  FOR UPDATE;
  IF v_status IN ('submitted', 'approved') THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'dynamic_report_already_submitted';
  END IF;

  FOR v_field IN SELECT value FROM jsonb_array_elements(
    COALESCE((SELECT jsonb_agg(jsonb_build_object('key', f.field_key, 'required', f.is_required))
      FROM public.report_form_version_fields f WHERE f.version_id = p_version_id), '[]'::jsonb)
  ) LOOP
    v_key := v_field->>'key';
    v_value := p_values->v_key;
    IF (v_field->>'required')::boolean AND (v_value IS NULL OR (jsonb_typeof(v_value) = 'string' AND btrim(v_value #>> '{}') = '')) THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'dynamic_report_required_field:' || v_key;
    END IF;
  END LOOP;

  IF v_report_id IS NULL THEN
    INSERT INTO public.employee_dynamic_reports (organization_id, template_id, version_id, employee_user_id, role_code, branch_id, report_date, status, values, submitted_at)
    VALUES (v_org, p_template_id, p_version_id, v_user, v_role, p_branch_id, p_report_date, 'submitted', p_values, now())
    RETURNING id INTO v_report_id;
  ELSE
    UPDATE public.employee_dynamic_reports
    SET values = p_values, status = 'submitted', review_note = NULL, submitted_at = now(), reviewed_at = NULL, updated_at = now(), branch_id = p_branch_id
    WHERE id = v_report_id;
  END IF;
  RETURN v_report_id;
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_dynamic_report_forms() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_dynamic_report_forms() TO authenticated;
REVOKE ALL ON FUNCTION public.submit_my_dynamic_report(uuid,uuid,date,jsonb,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_my_dynamic_report(uuid,uuid,date,jsonb,uuid) TO authenticated;

COMMIT;
