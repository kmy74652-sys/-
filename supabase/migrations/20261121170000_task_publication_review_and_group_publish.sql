-- Two-stage task publication: save the exact designer snapshot, review it, then publish to every active employee matching role + branch.
BEGIN;

CREATE TABLE IF NOT EXISTS public.task_publication_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES public.task_templates(id) ON DELETE RESTRICT,
  template_version integer NOT NULL,
  role_code text NOT NULL,
  branch_id uuid NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  due_at timestamptz NOT NULL,
  template_snapshot jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending_approval'
    CHECK (status IN ('pending_approval','rejected','published')),
  requested_by uuid NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid NULL,
  reviewed_at timestamptz NULL,
  review_note text NULL,
  published_count integer NULL,
  published_at timestamptz NULL,
  CONSTRAINT task_publication_requests_snapshot_object CHECK (jsonb_typeof(template_snapshot) = 'object')
);

CREATE INDEX IF NOT EXISTS task_publication_requests_review_idx
  ON public.task_publication_requests (organization_id, status, requested_at DESC);

ALTER TABLE public.task_publication_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS task_publication_requests_read ON public.task_publication_requests;
CREATE POLICY task_publication_requests_read
  ON public.task_publication_requests FOR SELECT TO authenticated
  USING (public.has_org_permission(organization_id, 'tasks.manage', NULL::uuid));

REVOKE ALL ON public.task_publication_requests FROM public, anon, authenticated;
GRANT SELECT ON public.task_publication_requests TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_task_publication_request(
  p_organization_id uuid,
  p_template_id uuid,
  p_branch_id uuid,
  p_due_at timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, alshaari_private
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_template public.task_templates%rowtype;
  v_snapshot jsonb;
  v_request_id uuid;
BEGIN
  IF v_user IS NULL OR NOT public.has_org_permission(p_organization_id, 'tasks.manage', NULL::uuid) THEN
    RAISE EXCEPTION USING errcode='42501', message='permission_denied';
  END IF;
  IF p_due_at IS NULL OR p_due_at <= now() THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_schedule';
  END IF;

  SELECT * INTO v_template
  FROM public.task_templates
  WHERE id=p_template_id AND organization_id=p_organization_id AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='22023', message='task_template_not_found';
  END IF;

  IF p_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.branches b
    WHERE b.id=p_branch_id AND b.organization_id=p_organization_id AND b.is_active
  ) THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_branch';
  END IF;

  SELECT jsonb_build_object(
    'title', v_template.title,
    'description', v_template.description,
    'expected_result', v_template.expected_result,
    'instructions', v_template.instructions,
    'role_code', v_template.role_code,
    'priority', v_template.default_priority,
    'version', v_template.version,
    'category_id', v_template.category_id,
    'subcategory_id', v_template.subcategory_id,
    'steps', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'title', s.title, 'instructions', s.instructions, 'sort_order', s.sort_order,
        'required', s.is_required, 'evidence_required', s.evidence_required,
        'evidence_instructions', s.evidence_instructions
      ) ORDER BY s.sort_order)
      FROM public.task_template_steps s WHERE s.template_id=v_template.id
    ), '[]'::jsonb),
    'report_fields', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'key', f.field_key, 'label', f.label, 'description', f.description,
        'type', f.field_type, 'required', f.is_required, 'repeatable', f.repeatable,
        'validation', f.validation, 'options', f.options, 'config', f.config
      ) ORDER BY f.sort_order)
      FROM public.task_template_report_fields f WHERE f.template_id=v_template.id
    ), '[]'::jsonb)
  ) INTO v_snapshot;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organization_memberships m
    JOIN public.role_assignments ra
      ON ra.organization_id=m.organization_id AND ra.membership_id=m.id
    WHERE m.organization_id=p_organization_id
      AND m.is_active AND m.user_id IS NOT NULL
      AND ra.role_code=v_template.role_code
      AND (p_branch_id IS NULL OR ra.branch_id=p_branch_id)
  ) THEN
    RAISE EXCEPTION USING errcode='22023', message='no_employee_for_role_branch';
  END IF;

  INSERT INTO public.task_publication_requests(
    organization_id, template_id, template_version, role_code, branch_id,
    due_at, template_snapshot, requested_by
  ) VALUES (
    p_organization_id, p_template_id, v_template.version, v_template.role_code,
    p_branch_id, p_due_at, v_snapshot, v_user
  ) RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_and_publish_task_request(
  p_organization_id uuid,
  p_request_id uuid,
  p_approve boolean,
  p_review_note text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, alshaari_private
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_request public.task_publication_requests%rowtype;
  v_recipient record;
  v_task uuid;
  v_count integer := 0;
  v_schema jsonb;
  v_step jsonb;
  v_field_count integer;
  v_key text;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.organization_memberships m
    JOIN public.role_assignments ra
      ON ra.organization_id=m.organization_id AND ra.membership_id=m.id
    WHERE m.organization_id=p_organization_id AND m.user_id=v_user
      AND m.is_active AND ra.role_code='owner'
  ) THEN
    RAISE EXCEPTION USING errcode='42501', message='owner_approval_required';
  END IF;

  SELECT * INTO v_request
  FROM public.task_publication_requests
  WHERE id=p_request_id AND organization_id=p_organization_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='22023', message='task_publication_request_not_found';
  END IF;
  IF v_request.status <> 'pending_approval' THEN
    RAISE EXCEPTION USING errcode='22023', message='task_publication_request_already_reviewed';
  END IF;

  IF NOT p_approve THEN
    UPDATE public.task_publication_requests
    SET status='rejected', reviewed_by=v_user, reviewed_at=now(),
        review_note=nullif(trim(coalesce(p_review_note,'')),'')
    WHERE id=p_request_id;
    RETURN 0;
  END IF;

  v_schema := coalesce(v_request.template_snapshot->'report_fields','[]'::jsonb);
  v_field_count := jsonb_array_length(v_schema);

  FOR v_recipient IN
    SELECT DISTINCT m.id AS membership_id, m.user_id, ra.branch_id
    FROM public.organization_memberships m
    JOIN public.role_assignments ra
      ON ra.organization_id=m.organization_id AND ra.membership_id=m.id
    JOIN public.branches b
      ON b.id=ra.branch_id AND b.organization_id=m.organization_id AND b.is_active
    WHERE m.organization_id=p_organization_id
      AND m.is_active AND m.user_id IS NOT NULL
      AND ra.role_code=v_request.role_code
      AND (v_request.branch_id IS NULL OR ra.branch_id=v_request.branch_id)
    ORDER BY m.id, ra.branch_id
  LOOP
    v_key := 'approved-template:' || p_request_id::text || ':' ||
      v_recipient.membership_id::text || ':' || v_recipient.branch_id::text;

    SELECT id INTO v_task FROM public.tasks
    WHERE organization_id=p_organization_id AND idempotency_key=v_key AND deleted_at IS NULL
    LIMIT 1;

    IF v_task IS NULL THEN
      INSERT INTO public.tasks(
        organization_id, branch_id, title, description, expected_result,
        assigned_to, created_by, due_at, starts_at, priority, template_id,
        position_code, report_flow, task_instructions, category_id, subcategory_id,
        proof_required, template_version, report_required, idempotency_key
      ) VALUES (
        p_organization_id, v_recipient.branch_id,
        v_request.template_snapshot->>'title',
        coalesce(v_request.template_snapshot->>'description',''),
        v_request.template_snapshot->>'expected_result',
        v_recipient.user_id, v_request.requested_by, v_request.due_at, now(),
        coalesce(v_request.template_snapshot->>'priority','normal')::task_priority,
        v_request.template_id, v_request.role_code, 'multi_form',
        v_request.template_snapshot->>'instructions',
        nullif(v_request.template_snapshot->>'category_id','')::uuid,
        nullif(v_request.template_snapshot->>'subcategory_id','')::uuid,
        false, v_request.template_version, v_field_count > 0, v_key
      ) RETURNING id INTO v_task;

      FOR v_step IN
        SELECT value FROM jsonb_array_elements(coalesce(v_request.template_snapshot->'steps','[]'::jsonb))
      LOOP
        INSERT INTO public.task_execution_steps(
          task_id, source_template_step_id, title, instructions, sort_order,
          is_required, evidence_required, evidence_instructions
        ) VALUES (
          v_task, NULL, v_step->>'title', v_step->>'instructions',
          coalesce((v_step->>'sort_order')::integer,0),
          coalesce((v_step->>'required')::boolean,true),
          coalesce((v_step->>'evidence_required')::boolean,false),
          v_step->>'evidence_instructions'
        );
      END LOOP;

      IF v_field_count > 0 THEN
        INSERT INTO public.task_report_form_snapshots(
          task_id, template_id, version_id, report_required, schema, published_by,
          title, sort_order, is_required, organization_id, task_report_form_id
        ) VALUES (
          v_task, NULL, NULL, true, v_schema, v_user,
          (v_request.template_snapshot->>'title') || ' — تقرير المهمة',
          0, true, p_organization_id, NULL
        );
      END IF;

      INSERT INTO public.task_activity_log(task_id, actor_id, action, details)
      VALUES (v_task, v_user, 'task_assigned', jsonb_build_object(
        'publication_request_id', p_request_id,
        'template_id', v_request.template_id,
        'template_version', v_request.template_version,
        'delivery', 'sent',
        'approved_by_owner', true
      ));
      v_count := v_count + 1;
    END IF;
  END LOOP;

  IF v_count = 0 THEN
    RAISE EXCEPTION USING errcode='22023', message='no_employee_for_role_branch';
  END IF;

  UPDATE public.task_publication_requests
  SET status='published', reviewed_by=v_user, reviewed_at=now(),
      review_note=nullif(trim(coalesce(p_review_note,'')),''),
      published_count=v_count, published_at=now()
  WHERE id=p_request_id;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_task_publication_request(uuid,uuid,uuid,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_task_publication_request(uuid,uuid,uuid,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.review_and_publish_task_request(uuid,uuid,boolean,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_and_publish_task_request(uuid,uuid,boolean,text) TO authenticated;

COMMIT;
