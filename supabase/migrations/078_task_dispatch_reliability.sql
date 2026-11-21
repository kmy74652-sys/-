-- Reliable task dispatch: idempotent assignment plus visible delivery milestones.
BEGIN;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS received_at timestamptz,
  ADD COLUMN IF NOT EXISTS opened_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS tasks_dispatch_idempotency_uq
  ON public.tasks (organization_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.assign_task_from_template(
  p_organization_id uuid,
  p_template_id uuid,
  p_assigned_to uuid,
  p_branch_id uuid,
  p_starts_at timestamptz,
  p_due_at timestamptz,
  p_priority text DEFAULT NULL,
  p_instructions text DEFAULT NULL,
  p_report_overrides jsonb DEFAULT '[]'::jsonb,
  p_idempotency_key text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_t public.task_templates%rowtype;
  v_existing uuid;
  v_task uuid;
  v_form record;
  v_snap uuid;
  v_schema jsonb;
  v_required boolean;
  v_override jsonb;
BEGIN
  IF v_user IS NULL OR NOT public.has_org_permission(p_organization_id,'tasks.manage',NULL::uuid) THEN
    RAISE EXCEPTION USING errcode='42501', message='permission_denied';
  END IF;
  IF p_idempotency_key IS NOT NULL AND (length(trim(p_idempotency_key)) = 0 OR length(p_idempotency_key) > 200) THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_idempotency_key';
  END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id INTO v_existing FROM public.tasks
    WHERE organization_id=p_organization_id AND idempotency_key=trim(p_idempotency_key) AND deleted_at IS NULL
    LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  END IF;
  SELECT * INTO v_t FROM public.task_templates
  WHERE id=p_template_id AND organization_id=p_organization_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='22023', message='task_template_not_found'; END IF;
  IF p_starts_at IS NULL OR p_due_at IS NULL OR p_due_at < p_starts_at THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_schedule';
  END IF;
  IF p_priority IS NOT NULL AND p_priority NOT IN ('normal','important','urgent','critical') THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_priority';
  END IF;
  IF p_report_overrides IS NULL OR jsonb_typeof(p_report_overrides) <> 'array' THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_report_overrides';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.organization_memberships m
    JOIN public.role_assignments r ON r.organization_id=m.organization_id AND r.membership_id=m.id
    WHERE m.organization_id=p_organization_id AND m.user_id=p_assigned_to AND m.is_active
      AND r.role_code=v_t.role_code AND (p_branch_id IS NULL OR r.branch_id=p_branch_id)
  ) THEN RAISE EXCEPTION USING errcode='22023', message='no_employee_for_role_branch'; END IF;
  IF p_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.branches WHERE id=p_branch_id AND organization_id=p_organization_id AND is_active
  ) THEN RAISE EXCEPTION USING errcode='22023', message='invalid_task_branch'; END IF;

  INSERT INTO public.tasks(
    organization_id,branch_id,title,description,expected_result,assigned_to,created_by,due_at,starts_at,
    priority,template_id,position_code,report_flow,task_instructions,category_id,subcategory_id,
    proof_required,proof_instructions,template_version,report_required,idempotency_key
  ) VALUES (
    p_organization_id,p_branch_id,v_t.title,v_t.description,v_t.expected_result,p_assigned_to,v_user,p_due_at,p_starts_at,
    coalesce(nullif(p_priority,''),v_t.default_priority)::task_priority,p_template_id,v_t.role_code,'multi_form',
    coalesce(nullif(trim(p_instructions),''),v_t.instructions),v_t.category_id,v_t.subcategory_id,false,null,v_t.version,
    exists(select 1 from public.task_template_report_forms where template_id=v_t.id and is_required),
    nullif(trim(p_idempotency_key),'')
  ) RETURNING id INTO v_task;

  INSERT INTO public.task_execution_steps(task_id,source_template_step_id,title,instructions,sort_order,is_required,evidence_required,evidence_instructions)
  SELECT v_task,s.id,s.title,s.instructions,s.sort_order,s.is_required,s.evidence_required,s.evidence_instructions
  FROM public.task_template_steps s WHERE s.template_id=v_t.id ORDER BY s.sort_order;
  FOR v_form IN
    SELECT l.*,r.title FROM public.task_template_report_forms l
    JOIN public.report_form_versions v ON v.id=l.version_id
    JOIN public.report_form_templates r ON r.id=v.template_id
    WHERE l.template_id=v_t.id ORDER BY l.sort_order
  LOOP
    v_required:=v_form.is_required;
    SELECT value INTO v_override FROM jsonb_array_elements(p_report_overrides) value
    WHERE value->>'approvedVersionId'=v_form.version_id::text LIMIT 1;
    IF v_override IS NOT NULL THEN v_required:=coalesce((v_override->>'required')::boolean,v_required); END IF;
    IF v_form.is_required AND NOT v_required THEN
      RAISE EXCEPTION USING errcode='22023',message='required_report_cannot_be_optional';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('key',f.field_key,'label',f.label,'type',f.field_type,'required',f.is_required,'repeatable',f.repeatable,'validation',f.validation,'options',f.options,'config',f.config) order by f.sort_order),'[]'::jsonb)
    INTO v_schema FROM public.report_form_version_fields f WHERE f.version_id=v_form.version_id;
    INSERT INTO public.task_report_form_snapshots(task_id,template_id,version_id,report_required,schema,published_by,title,sort_order,is_required,organization_id,task_report_form_id)
    VALUES(v_task,(select template_id from public.report_form_versions where id=v_form.version_id),v_form.version_id,v_required,v_schema,v_user,v_form.title,v_form.sort_order,v_required,p_organization_id,v_form.id)
    RETURNING id INTO v_snap;
  END LOOP;
  INSERT INTO public.task_activity_log(task_id,actor_id,action,details)
  VALUES(v_task,v_user,'task_assigned',jsonb_build_object('template_id',v_t.id,'template_version',v_t.version,'report_flow','multi_form','delivery','sent'));
  RETURN v_task;
EXCEPTION WHEN unique_violation THEN
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id INTO v_existing FROM public.tasks WHERE organization_id=p_organization_id AND idempotency_key=trim(p_idempotency_key) LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  END IF;
  RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_task_from_template(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,text,jsonb,text) FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.assign_task_from_template(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,text,jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.mobile_mark_task_opened(p_task_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_task public.tasks%rowtype;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION USING errcode='28000',message='not_authenticated'; END IF;
  SELECT * INTO v_task FROM public.tasks WHERE id=p_task_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_task.assigned_to<>auth.uid() THEN RAISE EXCEPTION USING errcode='P0002',message='task_not_found'; END IF;
  IF NOT public.has_org_permission(v_task.organization_id,'tasks.read',NULL::uuid) THEN RAISE EXCEPTION USING errcode='42501',message='permission_denied'; END IF;
  UPDATE public.tasks SET status=CASE WHEN status='new' THEN 'received' ELSE status END,
    received_at=coalesce(received_at,now()), opened_at=coalesce(opened_at,now()), updated_at=now()
  WHERE id=v_task.id;
  INSERT INTO public.task_activity_log(task_id,actor_id,action,details)
  VALUES(v_task.id,auth.uid(),'task_opened',jsonb_build_object('previous_status',v_task.status,'new_status',CASE WHEN v_task.status='new' THEN 'received' ELSE v_task.status END));
  RETURN v_task.id;
END;
$$;
REVOKE ALL ON FUNCTION public.mobile_mark_task_opened(uuid) FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mobile_mark_task_opened(uuid) TO authenticated;

COMMIT;
