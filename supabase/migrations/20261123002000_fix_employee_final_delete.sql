begin;

-- تم إنشاء جداول الموارد البشرية بعلاقات RESTRICT لحماية السجل أثناء العمل.
-- عند طلب الحذف النهائي الصريح من مالك المؤسسة، نحذف السجلات التابعة أولاً
-- ثم نزيل العضوية ورمز الدخول. يبقى سجل auth بلا عضوية، ولذلك لا يستطيع
-- الدخول إلى التطبيق أو الوصول إلى بيانات المؤسسة.
create or replace function public.admin_delete_employee_record(
  p_organization_id uuid,
  p_membership_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid;
begin
  if not public.management_role_allowed(p_organization_id) then
    raise exception using errcode = '42501', message = 'management_role_required';
  end if;

  select user_id into v_user
  from public.organization_memberships
  where id = p_membership_id
    and organization_id = p_organization_id
    and is_active;
  if not found then
    raise exception using errcode = 'P0002', message = 'employee_not_found';
  end if;

  if exists (
    select 1 from public.role_assignments
    where organization_id = p_organization_id
      and membership_id = p_membership_id
      and role_code = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'owner_account_protected';
  end if;

  delete from public.employee_agreement_approvals
   where organization_id = p_organization_id and membership_id = p_membership_id;
  delete from public.employee_agreement_responses
   where organization_id = p_organization_id and membership_id = p_membership_id;
  delete from public.employee_agreement_audit_log
   where organization_id = p_organization_id and membership_id = p_membership_id;
  update public.employee_agreements
     set current_version_id = null
   where organization_id = p_organization_id and membership_id = p_membership_id;
  delete from public.employee_agreements
   where organization_id = p_organization_id and membership_id = p_membership_id;

  delete from public.employee_payroll_entries
   where organization_id = p_organization_id and membership_id = p_membership_id;
  delete from public.employee_attendance_records
   where organization_id = p_organization_id and membership_id = p_membership_id;
  delete from public.employee_work_schedules
   where organization_id = p_organization_id and membership_id = p_membership_id;
  delete from public.employee_contracts
   where organization_id = p_organization_id and membership_id = p_membership_id;

  delete from public.employee_access_credentials where membership_id = p_membership_id;
  delete from public.role_assignments
   where organization_id = p_organization_id and membership_id = p_membership_id;
  delete from public.organization_memberships
   where id = p_membership_id and organization_id = p_organization_id;

  return v_user;
end;
$$;

revoke all on function public.admin_delete_employee_record(uuid, uuid) from public, anon;
grant execute on function public.admin_delete_employee_record(uuid, uuid) to authenticated;

commit;
