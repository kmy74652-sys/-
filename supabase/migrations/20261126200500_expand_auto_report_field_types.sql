BEGIN;

-- Expand automatic report field types for calculated and financial values.
-- Creates one immutable, task-scoped report snapshot for each unified-table row.
-- The existing 13-argument RPC remains unchanged for backward compatibility.
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
  p_idempotency_key text,
  p_report_schema jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_existing uuid;
  v_result jsonb;
  v_task_id uuid;
  v_snapshot_id uuid;
  v_field jsonb;
  v_key text;
  v_type text;
BEGIN
  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) = 0 OR length(trim(p_idempotency_key)) > 200 THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_idempotency_key';
  END IF;
  IF jsonb_typeof(p_report_schema) <> 'array' OR jsonb_array_length(p_report_schema) = 0 OR jsonb_array_length(p_report_schema) > 30 THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_auto_report_schema';
  END IF;
  FOR v_field IN SELECT value FROM jsonb_array_elements(p_report_schema)
  LOOP
    v_key := coalesce(v_field->>'key','');
    v_type := coalesce(v_field->>'type','');
    IF jsonb_typeof(v_field) <> 'object'
       OR length(trim(v_key)) < 2
       OR length(v_key) > 80
       OR length(trim(coalesce(v_field->>'label',''))) < 2
       OR v_type NOT IN ('text','textarea','number','date','time','select','checkbox','rating','percentage','money','calculated','attachment')
    THEN
      RAISE EXCEPTION USING errcode='22023', message='invalid_auto_report_field';
    END IF;
  END LOOP;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || trim(p_idempotency_key), 0));
  SELECT id INTO v_existing
  FROM public.tasks
  WHERE organization_id=p_organization_id
    AND idempotency_key=trim(p_idempotency_key)
    AND deleted_at IS NULL
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('id', v_existing, 'idempotent_replay', true);
  END IF;

  -- The existing function performs all permission, employee, branch and priority checks.
  -- It creates the task first; this function then attaches the generated immutable snapshot.
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
    NULL::uuid,
    NULL::uuid,
    false
  );
  v_task_id := nullif(v_result->>'id','')::uuid;
  IF v_task_id IS NULL THEN
    RAISE EXCEPTION USING errcode='22023', message='task_creation_missing_id';
  END IF;

  INSERT INTO public.task_report_form_snapshots(
    task_id, template_id, version_id, report_required, schema, published_by,
    title, sort_order, is_required, organization_id, task_report_form_id
  ) VALUES (
    v_task_id, NULL, NULL, true, p_report_schema, auth.uid(),
    trim(p_title) || ' — تقرير المهمة', 0, true, p_organization_id, NULL
  ) RETURNING id INTO v_snapshot_id;

  UPDATE public.tasks
  SET report_flow='multi_form',
      report_required=true,
      report_form_snapshot_id=v_snapshot_id,
      idempotency_key=trim(p_idempotency_key),
      updated_at=now()
  WHERE id=v_task_id AND organization_id=p_organization_id;

  INSERT INTO public.task_activity_log(task_id,actor_id,action,details)
  VALUES(v_task_id,auth.uid(),'report_form_auto_generated',jsonb_build_object(
    'snapshot_id',v_snapshot_id,
    'field_count',jsonb_array_length(p_report_schema),
    'generator','rules-v1'
  ));

  RETURN v_result || jsonb_build_object(
    'id',v_task_id,
    'report_required',true,
    'report_form_snapshot_id',v_snapshot_id,
    'idempotent_replay',false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_task_with_report_form(
  uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean,text,jsonb
) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_task_with_report_form(
  uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean,text,jsonb
) TO authenticated;

COMMIT;
