BEGIN;

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

  -- هذه العلاقة RESTRICT، لذلك يجب حذف دورات الإصدار قبل حذف الحساب أو مهامه.
  DELETE FROM public.approved_task_cycles
  WHERE organization_id = p_organization_id
    AND employee_user_id = v_user;

  ALTER TABLE public.task_activity_log DISABLE TRIGGER task_activity_log_no_update;
  DELETE FROM public.tasks WHERE assigned_to = v_user;
  ALTER TABLE public.task_activity_log ENABLE TRIGGER task_activity_log_no_update;

  DELETE FROM public.organization_memberships
  WHERE id = p_membership_id AND organization_id = p_organization_id;
  DELETE FROM auth.users WHERE id = v_user;
  RETURN v_user;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_employee_record(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_employee_record(uuid, uuid) TO authenticated;

COMMIT;
