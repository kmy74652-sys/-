-- Permanently retire the legacy task-template/task-designer subsystem.
-- Keep tasks, task reports, report form templates/versions, snapshots, and the
-- current create_task_with_report_form flow.

BEGIN;

-- Remove RPCs whose only purpose is the legacy task designer/template library.
DROP FUNCTION IF EXISTS public.assign_task_from_template(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,text,jsonb);
DROP FUNCTION IF EXISTS public.assign_task_from_template(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,text,jsonb,text);
DROP FUNCTION IF EXISTS public.save_task_designer_template(uuid,uuid,jsonb);
DROP FUNCTION IF EXISTS public.delete_task_designer_template(uuid,uuid);
DROP FUNCTION IF EXISTS public.dispatch_default_task_template_assignments(date);
DROP FUNCTION IF EXISTS public.submit_task_publication_request(uuid,uuid,uuid,timestamptz,text);

-- Keep report-template deletion working without referring to task templates.
DROP FUNCTION IF EXISTS public.admin_delete_report_template(uuid,uuid);
CREATE FUNCTION public.admin_delete_report_template(
  p_organization_id uuid,
  p_template_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.management_role_allowed(p_organization_id) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'management_role_required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.report_form_templates
    WHERE id = p_template_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'report_template_not_found';
  END IF;
  UPDATE public.task_report_form_snapshots SET template_id = NULL WHERE template_id = p_template_id;
  UPDATE public.report_form_versions SET template_id = NULL WHERE template_id = p_template_id;
  DELETE FROM public.report_form_templates
  WHERE id = p_template_id AND organization_id = p_organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'report_template_not_found';
  END IF;
  RETURN p_template_id;
END;
$$;

-- Keep the current report-template publishing path, but use the task's stored
-- role directly; there is no longer a task-template fallback.
DROP FUNCTION IF EXISTS public.publish_task_report_form(uuid,uuid,uuid,boolean);
CREATE FUNCTION public.publish_task_report_form(
  p_task_id uuid,
  p_template_id uuid,
  p_version_id uuid,
  p_report_required boolean
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_template public.report_form_templates%rowtype;
  v_version public.report_form_versions%rowtype;
  v_snapshot uuid;
  v_schema jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION USING errcode='28000', message='not_authenticated'; END IF;
  SELECT * INTO v_task FROM public.tasks WHERE id=p_task_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002', message='task_not_found'; END IF;
  IF NOT public.report_designer_allowed_for_org(v_task.organization_id) THEN RAISE EXCEPTION USING errcode='42501', message='permission_denied'; END IF;
  IF v_task.report_form_snapshot_id IS NOT NULL OR EXISTS(SELECT 1 FROM public.task_report_form_snapshots s WHERE s.task_id=v_task.id) THEN
    RAISE EXCEPTION USING errcode='22023', message='report_form_snapshot_immutable';
  END IF;
  SELECT * INTO v_template FROM public.report_form_templates
  WHERE id=p_template_id AND organization_id=v_task.organization_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002', message='report_form_template_not_found'; END IF;
  SELECT * INTO v_version FROM public.report_form_versions
  WHERE id=p_version_id AND template_id=p_template_id FOR SHARE;
  IF NOT FOUND OR v_version.status <> 'published' OR v_version.approved_by IS NULL OR v_version.approved_at IS NULL THEN
    RAISE EXCEPTION USING errcode='22023', message='report_form_version_requires_approval';
  END IF;
  IF v_task.position_code IS NULL THEN RAISE EXCEPTION USING errcode='22023', message='task_role_missing'; END IF;
  IF v_task.position_code <> v_template.role_code THEN RAISE EXCEPTION USING errcode='22023', message='report_template_role_mismatch'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'key',f.field_key,'label',f.label,'description',f.description,'type',f.field_type,
    'required',f.is_required,'repeatable',f.repeatable,'options',f.options,
    'validation',f.validation,'config',f.config
  ) ORDER BY f.sort_order),'[]'::jsonb)
  INTO v_schema FROM public.report_form_version_fields f WHERE f.version_id=p_version_id;
  IF jsonb_array_length(v_schema)=0 THEN RAISE EXCEPTION USING errcode='22023', message='report_form_fields_required'; END IF;
  INSERT INTO public.task_report_form_snapshots(task_id,template_id,version_id,report_required,schema,published_by)
  VALUES(v_task.id,v_template.id,v_version.id,coalesce(p_report_required,v_version.report_required),v_schema,v_user)
  RETURNING id INTO v_snapshot;
  UPDATE public.tasks SET report_required=coalesce(p_report_required,v_version.report_required),report_form_snapshot_id=v_snapshot,updated_at=now() WHERE id=v_task.id;
  INSERT INTO public.task_activity_log(task_id,actor_id,action,details)
  VALUES(v_task.id,v_user,'report_form_published',jsonb_build_object('snapshot_id',v_snapshot,'version_id',v_version.id));
  RETURN v_snapshot;
END;
$$;

-- Preserve the public RPC signature used by the current app, while ignoring
-- the retired p_template_id parameter and creating only direct tasks.
DROP FUNCTION IF EXISTS public.create_task_with_report_form(uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean);
CREATE FUNCTION public.create_task_with_report_form(
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
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_task_id uuid;
  v_version_role text;
  v_has_report boolean := false;
  v_priority public.task_priority;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION USING errcode='28000', message='not_authenticated'; END IF;
  IF NOT alshaari_private.has_permission(p_organization_id,'tasks.manage',NULL::uuid) THEN RAISE EXCEPTION USING errcode='42501', message='permission_denied'; END IF;
  IF p_title IS NULL OR length(trim(p_title)) < 2 OR length(trim(p_title)) > 200 OR p_due_at IS NULL THEN RAISE EXCEPTION USING errcode='22023', message='task_title_or_due_date_invalid'; END IF;
  IF p_role_code NOT IN ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker') THEN RAISE EXCEPTION USING errcode='22023', message='invalid_task_role'; END IF;
  IF p_priority IS NULL OR p_priority NOT IN ('normal','important','urgent','critical') THEN RAISE EXCEPTION USING errcode='22023', message='invalid_task_priority'; END IF;
  v_priority := p_priority::public.task_priority;
  IF NOT EXISTS (
    SELECT 1 FROM public.organization_memberships m
    JOIN public.role_assignments ra ON ra.organization_id=m.organization_id AND ra.membership_id=m.id
    WHERE m.organization_id=p_organization_id AND m.user_id=p_assigned_to AND m.is_active
      AND ra.role_code=p_role_code AND (p_branch_id IS NULL OR ra.branch_id=p_branch_id)
  ) THEN RAISE EXCEPTION USING errcode='22023', message='no_employee_for_role'; END IF;
  IF p_branch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.branches b WHERE b.id=p_branch_id AND b.organization_id=p_organization_id AND b.is_active) THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid_task_branch';
  END IF;
  IF p_report_template_id IS NULL AND p_report_version_id IS NOT NULL THEN RAISE EXCEPTION USING errcode='22023', message='report_form_version_without_template'; END IF;
  IF p_report_template_id IS NOT NULL THEN
    IF p_report_version_id IS NULL THEN RAISE EXCEPTION USING errcode='22023', message='report_form_version_required'; END IF;
    SELECT t.role_code INTO v_version_role
    FROM public.report_form_templates t
    JOIN public.report_form_versions v ON v.template_id=t.id
    WHERE t.id=p_report_template_id AND t.organization_id=p_organization_id AND t.is_active
      AND v.id=p_report_version_id AND v.status='published' AND v.approved_by IS NOT NULL AND v.approved_at IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION USING errcode='22023', message='report_form_version_requires_approval'; END IF;
    IF v_version_role <> p_role_code THEN RAISE EXCEPTION USING errcode='22023', message='report_template_role_mismatch'; END IF;
    v_has_report := true;
  END IF;
  IF coalesce(p_report_required,false) AND NOT v_has_report THEN RAISE EXCEPTION USING errcode='22023', message='task_report_required_without_fields'; END IF;
  INSERT INTO public.tasks(organization_id,branch_id,title,description,assigned_to,created_by,due_at,priority,position_code,report_flow,report_required)
  VALUES(p_organization_id,p_branch_id,trim(p_title),nullif(trim(coalesce(p_description,'')),''),p_assigned_to,v_user,p_due_at,v_priority,p_role_code,
    CASE WHEN p_report_template_id IS NOT NULL THEN 'multi_form' ELSE 'legacy' END,
    coalesce(p_report_required,false) AND v_has_report)
  RETURNING id INTO v_task_id;
  IF p_report_template_id IS NOT NULL THEN
    PERFORM public.publish_task_report_form(v_task_id,p_report_template_id,p_report_version_id,coalesce(p_report_required,false));
  END IF;
  RETURN jsonb_build_object('id',v_task_id,'assigned_to',p_assigned_to,'position_code',p_role_code,'report_required',coalesce(p_report_required,false) AND v_has_report);
END;
$$;

-- Remove all remaining schema links to the retired template subsystem while
-- preserving task execution, reports, and report snapshots.
ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_template_id_fkey;
ALTER TABLE public.tasks DROP COLUMN IF EXISTS template_id;
ALTER TABLE public.task_execution_steps DROP COLUMN IF EXISTS source_template_step_id;
ALTER TABLE public.task_report_form_snapshots DROP CONSTRAINT IF EXISTS task_report_form_snapshots_task_report_form_id_fkey;
ALTER TABLE public.task_report_form_snapshots DROP COLUMN IF EXISTS task_report_form_id;

DROP TABLE IF EXISTS public.task_publication_requests CASCADE;
DROP TABLE IF EXISTS public.task_import_rows CASCADE;
DROP TABLE IF EXISTS public.task_import_batches CASCADE;
DROP TABLE IF EXISTS public.task_template_assignments CASCADE;
DROP TABLE IF EXISTS public.task_template_report_fields CASCADE;
DROP TABLE IF EXISTS public.task_template_report_forms CASCADE;
DROP TABLE IF EXISTS public.task_template_steps CASCADE;
DROP TABLE IF EXISTS public.task_templates CASCADE;

COMMIT;
