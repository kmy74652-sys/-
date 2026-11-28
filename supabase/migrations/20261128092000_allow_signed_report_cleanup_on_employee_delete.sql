BEGIN;

-- التقارير الموقعة تبقى غير قابلة للتعديل والحذف في التشغيل العادي.
-- هذا الاستثناء لا يعمل إلا داخل معاملة حذف حساب موظف نهائية ومصرح بها.
CREATE OR REPLACE FUNCTION public.guard_report_signature_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_task uuid;
  v_snapshot uuid;
  v_field text;
BEGIN
  IF tg_op = 'DELETE'
     AND current_setting('app.allow_employee_delete', true) = 'on' THEN
    RETURN old;
  END IF;
  IF tg_op = 'INSERT' THEN
    SELECT r.task_id, r.report_form_snapshot_id
      INTO v_task, v_snapshot
    FROM public.task_reports r
    WHERE r.id = new.report_id;
    IF NOT FOUND OR v_task <> new.task_id OR v_snapshot IS DISTINCT FROM new.report_form_snapshot_id THEN
      RAISE EXCEPTION USING errcode='22023', message='report_signature_link_invalid';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.task_report_form_snapshots s,
           jsonb_array_elements(s.schema) f(value)
      WHERE s.id = new.report_form_snapshot_id
        AND f.value->>'key' = new.field_key
        AND f.value->>'type' = 'signature'
    ) THEN
      RAISE EXCEPTION USING errcode='22023', message='report_signature_field_invalid';
    END IF;
    IF jsonb_typeof(new.stroke_paths) <> 'array'
       OR jsonb_array_length(new.stroke_paths) < 1
       OR jsonb_array_length(new.stroke_paths) > 200 THEN
      RAISE EXCEPTION USING errcode='22023', message='invalid_report_signature';
    END IF;
    RETURN new;
  END IF;
  RAISE EXCEPTION USING errcode='42501', message='report_signature_immutable';
END;
$function$;

CREATE OR REPLACE FUNCTION public.guard_task_report_snapshot_and_signature()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_signature record;
BEGIN
  IF tg_op = 'DELETE' THEN
    IF current_setting('app.allow_employee_delete', true) = 'on' THEN
      RETURN old;
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.task_report_signature_attachments a
      WHERE a.report_id = old.id
    ) THEN
      RAISE EXCEPTION USING errcode='42501', message='signed_report_immutable';
    END IF;
    RETURN old;
  END IF;
  IF old.report_form_snapshot_id IS DISTINCT FROM new.report_form_snapshot_id
     OR old.idempotency_key IS DISTINCT FROM new.idempotency_key THEN
    RAISE EXCEPTION USING errcode='42501', message='report_provenance_immutable';
  END IF;
  FOR v_signature IN
    SELECT id, field_key
    FROM public.task_report_signature_attachments
    WHERE report_id = old.id
  LOOP
    IF new.values->v_signature.field_key->>'signature_attachment_id'
       IS DISTINCT FROM v_signature.id::text THEN
      RAISE EXCEPTION USING errcode='42501', message='report_signature_immutable';
    END IF;
  END LOOP;
  RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_employee_record(
  p_organization_id uuid,
  p_membership_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $function$
DECLARE
  v_user uuid;
BEGIN
  IF NOT public.management_role_allowed(p_organization_id) THEN
    RAISE EXCEPTION USING errcode='42501', message='management_role_required';
  END IF;
  SELECT user_id INTO v_user
  FROM public.organization_memberships
  WHERE id = p_membership_id
    AND organization_id = p_organization_id
    AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='P0002', message='employee_not_found';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.role_assignments
    WHERE organization_id = p_organization_id
      AND membership_id = p_membership_id
      AND role_code = 'owner'
  ) THEN
    RAISE EXCEPTION USING errcode='42501', message='owner_account_protected';
  END IF;

  DELETE FROM public.employee_agreement_approvals WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  DELETE FROM public.employee_agreement_responses WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  DELETE FROM public.employee_agreement_audit_log WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  UPDATE public.employee_agreements SET current_version_id = NULL WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  DELETE FROM public.employee_agreements WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  DELETE FROM public.employee_payroll_entries WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  DELETE FROM public.employee_attendance_records WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  DELETE FROM public.employee_work_schedules WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  DELETE FROM public.employee_contracts WHERE organization_id = p_organization_id AND membership_id = p_membership_id;
  DELETE FROM public.employee_access_credentials WHERE membership_id = p_membership_id;
  DELETE FROM public.role_assignments WHERE organization_id = p_organization_id AND membership_id = p_membership_id;

  PERFORM set_config('app.allow_employee_delete', 'on', true);
  PERFORM set_config('app.allow_task_delete', 'on', true);
  DELETE FROM public.tasks WHERE assigned_to = v_user OR created_by = v_user;

  DELETE FROM public.organization_memberships
  WHERE id = p_membership_id AND organization_id = p_organization_id;
  DELETE FROM auth.users WHERE id = v_user;
  RETURN v_user;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_employee_record(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_employee_record(uuid, uuid) TO authenticated;

COMMIT;
