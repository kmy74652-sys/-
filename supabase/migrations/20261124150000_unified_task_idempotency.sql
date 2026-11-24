BEGIN;

-- Idempotent wrapper for the existing task/report creation flow.
-- The original 12-argument RPC remains unchanged for backward compatibility.
-- Unified-table dispatch uses this overload so a retry cannot create a duplicate row.
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
  p_report_required boolean,
  p_idempotency_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_existing uuid;
  v_result jsonb;
  v_task_id uuid;
BEGIN
  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) = 0 OR length(trim(p_idempotency_key)) > 200 THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_idempotency_key';
  END IF;

  -- Serialize retries for the same organization/key inside one transaction.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || trim(p_idempotency_key), 0));

  SELECT id INTO v_existing
  FROM public.tasks
  WHERE organization_id = p_organization_id
    AND idempotency_key = trim(p_idempotency_key)
    AND deleted_at IS NULL
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('id', v_existing, 'idempotent_replay', true);
  END IF;

  v_result := public.create_task_with_report_form(
    p_organization_id,
    p_title,
    p_description,
    p_due_at,
    p_priority,
    p_branch_id,
    p_role_code,
    p_template_id,
    p_assigned_to,
    p_report_template_id,
    p_report_version_id,
    p_report_required
  );

  v_task_id := nullif(v_result->>'id', '')::uuid;
  IF v_task_id IS NULL THEN
    RAISE EXCEPTION USING errcode='22023', message='task_creation_missing_id';
  END IF;

  UPDATE public.tasks
  SET idempotency_key = trim(p_idempotency_key), updated_at = now()
  WHERE id = v_task_id AND organization_id = p_organization_id;

  RETURN v_result || jsonb_build_object('idempotent_replay', false);
END;
$$;

REVOKE ALL ON FUNCTION public.create_task_with_report_form(
  uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean,text
) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_task_with_report_form(
  uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean,text
) TO authenticated;

COMMIT;
