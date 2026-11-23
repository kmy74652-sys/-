-- Link approved report templates to the employee multi-form flow.
-- Keep the existing RPC signature, tables, RLS and triggers unchanged.
-- The deployed database exposes alshaari_private.has_permission, while the
-- previous replacement referenced a non-existent public.has_org_permission.
BEGIN;

CREATE OR REPLACE FUNCTION public.create_task_with_report_form(
  p_organization_id uuid,
  p_title text,
  p_description text,
  p_due_at timestamptz,
  p_priority text,
  p_branch_id uuid,
  p_role_code text,
  p_template_id uuid,
  p_assigned_to uuid,
  p_report_template_id uuid,
  p_report_version_id uuid,
  p_report_required boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_task_id uuid;
  v_legacy_fields integer := 0;
  v_has_report boolean := false;
  v_version_role text;
  v_priority public.task_priority;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION USING errcode='28000', message='not_authenticated';
  END IF;
  IF NOT alshaari_private.has_permission(p_organization_id,'tasks.manage',NULL::uuid) THEN
    RAISE EXCEPTION USING errcode='42501', message='permission_denied';
  END IF;
  IF p_title IS NULL OR length(trim(p_title)) < 2 OR length(trim(p_title)) > 200 OR p_due_at IS NULL THEN
    RAISE EXCEPTION USING errcode='22023', message='task_title_or_due_date_invalid';
  END IF;
  IF p_role_code NOT IN ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker') THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_role';
  END IF;
  IF p_priority IS NULL OR p_priority NOT IN ('low','normal','high','urgent') THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_priority';
  END IF;
  v_priority := p_priority::public.task_priority;
  IF NOT EXISTS (
    SELECT 1
    FROM public.organization_memberships m
    JOIN public.role_assignments ra
      ON ra.organization_id=m.organization_id AND ra.membership_id=m.id
    WHERE m.organization_id=p_organization_id
      AND m.user_id=p_assigned_to
      AND m.is_active
      AND ra.role_code=p_role_code
      AND (p_branch_id IS NULL OR ra.branch_id=p_branch_id)
  ) THEN
    RAISE EXCEPTION USING errcode='22023', message='no_employee_for_role';
  END IF;
  IF p_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.branches b
    WHERE b.id=p_branch_id AND b.organization_id=p_organization_id AND b.is_active
  ) THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_branch';
  END IF;
  IF p_template_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.task_templates tt
      WHERE tt.id=p_template_id
        AND tt.organization_id=p_organization_id
        AND tt.is_active
        AND tt.role_code=p_role_code
    ) THEN
      RAISE EXCEPTION USING errcode='22023', message='task_template_role_mismatch';
    END IF;
    SELECT count(*) INTO v_legacy_fields
    FROM public.task_template_report_fields f
    WHERE f.template_id=p_template_id;
  END IF;
  IF p_report_template_id IS NULL AND p_report_version_id IS NOT NULL THEN
    RAISE EXCEPTION USING errcode='22023', message='report_form_version_without_template';
  END IF;
  IF p_report_template_id IS NOT NULL THEN
    IF p_report_version_id IS NULL THEN
      RAISE EXCEPTION USING errcode='22023', message='report_form_version_required';
    END IF;
    SELECT t.role_code INTO v_version_role
    FROM public.report_form_templates t
    JOIN public.report_form_versions v ON v.template_id=t.id
    WHERE t.id=p_report_template_id
      AND t.organization_id=p_organization_id
      AND t.is_active
      AND v.id=p_report_version_id
      AND v.status='published'
      AND v.approved_by IS NOT NULL
      AND v.approved_at IS NOT NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING errcode='22023', message='report_form_version_requires_approval';
    END IF;
    IF v_version_role<>p_role_code THEN
      RAISE EXCEPTION USING errcode='22023', message='report_template_role_mismatch';
    END IF;
    v_has_report := true;
  ELSIF v_legacy_fields > 0 THEN
    v_has_report := true;
  END IF;
  IF coalesce(p_report_required,false) AND NOT v_has_report THEN
    RAISE EXCEPTION USING errcode='22023', message='task_report_required_without_fields';
  END IF;
  INSERT INTO public.tasks(
    organization_id, branch_id, title, description, assigned_to, created_by,
    due_at, priority, template_id, position_code, report_flow, report_required
  ) VALUES (
    p_organization_id, p_branch_id, trim(p_title),
    nullif(trim(coalesce(p_description,'')), ''), p_assigned_to, v_user,
    p_due_at, v_priority, p_template_id, p_role_code,
    CASE WHEN p_report_template_id IS NOT NULL THEN 'multi_form' ELSE 'legacy' END,
    coalesce(p_report_required,false) AND v_has_report
  ) RETURNING id INTO v_task_id;
  IF v_legacy_fields > 0 THEN
    INSERT INTO public.task_report_fields(
      task_id, label, field_key, field_type, is_required, options, sort_order
    )
    SELECT v_task_id, f.label, f.field_key, f.field_type, f.is_required, f.options, f.sort_order
    FROM public.task_template_report_fields f
    WHERE f.template_id=p_template_id
    ORDER BY f.sort_order;
  END IF;
  IF p_report_template_id IS NOT NULL THEN
    PERFORM public.publish_task_report_form(
      v_task_id, p_report_template_id, p_report_version_id,
      coalesce(p_report_required,false)
    );
  END IF;
  RETURN jsonb_build_object(
    'id', v_task_id,
    'assigned_to', p_assigned_to,
    'position_code', p_role_code,
    'report_required', coalesce(p_report_required,false) AND v_has_report
  );
END $$;

REVOKE ALL ON FUNCTION public.create_task_with_report_form(
  uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean
) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_task_with_report_form(
  uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean
) TO authenticated;

COMMIT;
