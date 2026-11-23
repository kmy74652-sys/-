BEGIN;

-- The staging database already has organization-scoped report approval.
-- Keep the same contract while ensuring the permission remains authenticated-only.
REVOKE ALL ON FUNCTION public.approve_report_form_version(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_report_form_version(uuid) TO authenticated;

-- Attendance must reference an active membership in the same organization.
CREATE OR REPLACE FUNCTION public.record_employee_attendance(
  p_organization_id uuid,
  p_membership_id uuid,
  p_work_date date,
  p_status text,
  p_check_in_at timestamptz,
  p_check_out_at timestamptz,
  p_note text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_id uuid;
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL
     OR NOT public.employee_agreement_can(p_organization_id, 'employee_hr.manage', NULL::uuid) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'hr_manage_denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organization_memberships m
    WHERE m.id = p_membership_id
      AND m.organization_id = p_organization_id
      AND m.is_active
  ) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'employee_not_active';
  END IF;

  IF p_check_out_at IS NOT NULL
     AND p_check_in_at IS NOT NULL
     AND p_check_out_at < p_check_in_at THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'invalid_attendance_times';
  END IF;

  INSERT INTO public.employee_attendance_records(
    organization_id, membership_id, work_date, status,
    check_in_at, check_out_at, note, recorded_by
  )
  VALUES (
    p_organization_id, p_membership_id, p_work_date,
    COALESCE(NULLIF(p_status, ''), 'present'),
    p_check_in_at, p_check_out_at, NULLIF(trim(p_note), ''), v_user
  )
  ON CONFLICT (membership_id, work_date) DO UPDATE
  SET status = excluded.status,
      check_in_at = excluded.check_in_at,
      check_out_at = excluded.check_out_at,
      note = excluded.note,
      recorded_by = excluded.recorded_by,
      updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Payroll entries must reference an active membership in the same organization
-- as both the caller and the payroll period.
CREATE OR REPLACE FUNCTION public.upsert_employee_payroll_entry(
  p_organization_id uuid,
  p_period_id uuid,
  p_membership_id uuid,
  p_base_amount numeric,
  p_additions numeric,
  p_deductions numeric,
  p_currency text,
  p_note text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_id uuid;
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL
     OR NOT public.employee_agreement_can(p_organization_id, 'employee_hr.manage', NULL::uuid) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'hr_manage_denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.employee_payroll_periods p
    WHERE p.id = p_period_id
      AND p.organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'payroll_period_not_found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organization_memberships m
    WHERE m.id = p_membership_id
      AND m.organization_id = p_organization_id
      AND m.is_active
  ) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'employee_not_active';
  END IF;

  INSERT INTO public.employee_payroll_entries(
    organization_id, period_id, membership_id,
    base_amount, additions, deductions, currency, note
  )
  VALUES (
    p_organization_id, p_period_id, p_membership_id,
    greatest(coalesce(p_base_amount, 0), 0),
    greatest(coalesce(p_additions, 0), 0),
    greatest(coalesce(p_deductions, 0), 0),
    coalesce(nullif(trim(p_currency), ''), 'YER'),
    nullif(trim(p_note), '')
  )
  ON CONFLICT (period_id, membership_id) DO UPDATE
  SET base_amount = excluded.base_amount,
      additions = excluded.additions,
      deductions = excluded.deductions,
      currency = excluded.currency,
      note = excluded.note,
      updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_employee_attendance(uuid,uuid,date,text,timestamptz,timestamptz,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_employee_attendance(uuid,uuid,date,text,timestamptz,timestamptz,text) TO authenticated;
REVOKE ALL ON FUNCTION public.upsert_employee_payroll_entry(uuid,uuid,uuid,numeric,numeric,numeric,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_employee_payroll_entry(uuid,uuid,uuid,numeric,numeric,numeric,text,text) TO authenticated;

COMMIT;
