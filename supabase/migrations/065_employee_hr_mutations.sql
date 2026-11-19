-- Protected HR mutations. Client writes go through these RPCs only.
create or replace function public.create_employee_contract(p_organization_id uuid,p_membership_id uuid,p_contract_no text,p_contract_type text,p_start_date date,p_end_date date,p_base_salary numeric,p_currency text,p_pay_frequency text,p_duties jsonb)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_user uuid:=auth.uid();
begin
  if v_user is null or not public.employee_agreement_can(p_organization_id,'employee_hr.manage',null::uuid) then raise exception using errcode='42501',message='hr_manage_denied'; end if;
  if not exists(select 1 from public.organization_memberships where id=p_membership_id and organization_id=p_organization_id and is_active) then raise exception using errcode='22023',message='employee_not_active'; end if;
  if p_end_date is not null and p_end_date<p_start_date then raise exception using errcode='22023',message='invalid_contract_dates'; end if;
  insert into public.employee_contracts(organization_id,membership_id,contract_no,contract_type,start_date,end_date,base_salary,salary_currency,pay_frequency,duties,created_by,updated_by)
  values(p_organization_id,p_membership_id,trim(p_contract_no),coalesce(nullif(trim(p_contract_type),''),'employment'),p_start_date,p_end_date,p_base_salary,coalesce(nullif(trim(p_currency),''),'SAR'),coalesce(nullif(trim(p_pay_frequency),''),'monthly'),coalesce(p_duties,'[]'::jsonb),v_user,v_user) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.create_employee_work_schedule(p_organization_id uuid,p_membership_id uuid,p_name text,p_timezone text,p_work_days jsonb,p_start_time time,p_end_time time,p_break_minutes integer,p_effective_from date,p_effective_to date)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_user uuid:=auth.uid();
begin
  if v_user is null or not public.employee_agreement_can(p_organization_id,'employee_hr.manage',null::uuid) then raise exception using errcode='42501',message='hr_manage_denied'; end if;
  if not exists(select 1 from public.organization_memberships where id=p_membership_id and organization_id=p_organization_id and is_active) then raise exception using errcode='22023',message='employee_not_active'; end if;
  if p_effective_to is not null and p_effective_to<p_effective_from then raise exception using errcode='22023',message='invalid_schedule_dates'; end if;
  insert into public.employee_work_schedules(organization_id,membership_id,name,timezone,work_days,start_time,end_time,break_minutes,effective_from,effective_to,created_by)
  values(p_organization_id,p_membership_id,trim(p_name),coalesce(nullif(trim(p_timezone),''),'Asia/Riyadh'),coalesce(p_work_days,'[0,1,2,3,4]'::jsonb),p_start_time,p_end_time,greatest(coalesce(p_break_minutes,0),0),coalesce(p_effective_from,current_date),p_effective_to,v_user) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.record_employee_attendance(p_organization_id uuid,p_membership_id uuid,p_work_date date,p_status text,p_check_in_at timestamptz,p_check_out_at timestamptz,p_note text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_user uuid:=auth.uid();
begin
  if v_user is null or not public.employee_agreement_can(p_organization_id,'employee_hr.manage',null::uuid) then raise exception using errcode='42501',message='hr_manage_denied'; end if;
  insert into public.employee_attendance_records(organization_id,membership_id,work_date,status,check_in_at,check_out_at,note,recorded_by)
  values(p_organization_id,p_membership_id,p_work_date,coalesce(nullif(p_status,''),'present'),p_check_in_at,p_check_out_at,nullif(trim(p_note),''),v_user)
  on conflict(membership_id,work_date) do update set status=excluded.status,check_in_at=excluded.check_in_at,check_out_at=excluded.check_out_at,note=excluded.note,recorded_by=excluded.recorded_by,updated_at=now()
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.create_employee_payroll_period(p_organization_id uuid,p_period_start date,p_period_end date)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_user uuid:=auth.uid();
begin
  if v_user is null or not public.employee_agreement_can(p_organization_id,'employee_hr.manage',null::uuid) then raise exception using errcode='42501',message='hr_manage_denied'; end if;
  insert into public.employee_payroll_periods(organization_id,period_start,period_end,created_by) values(p_organization_id,p_period_start,p_period_end,v_user) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.upsert_employee_payroll_entry(p_organization_id uuid,p_period_id uuid,p_membership_id uuid,p_base_amount numeric,p_additions numeric,p_deductions numeric,p_currency text,p_note text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_user uuid:=auth.uid();
begin
  if v_user is null or not public.employee_agreement_can(p_organization_id,'employee_hr.manage',null::uuid) then raise exception using errcode='42501',message='hr_manage_denied'; end if;
  if not exists(select 1 from public.employee_payroll_periods where id=p_period_id and organization_id=p_organization_id) then raise exception using errcode='22023',message='payroll_period_not_found'; end if;
  insert into public.employee_payroll_entries(organization_id,period_id,membership_id,base_amount,additions,deductions,currency,note)
  values(p_organization_id,p_period_id,p_membership_id,greatest(coalesce(p_base_amount,0),0),greatest(coalesce(p_additions,0),0),greatest(coalesce(p_deductions,0),0),coalesce(nullif(trim(p_currency),''),'SAR'),nullif(trim(p_note),''))
  on conflict(period_id,membership_id) do update set base_amount=excluded.base_amount,additions=excluded.additions,deductions=excluded.deductions,currency=excluded.currency,note=excluded.note,updated_at=now()
  returning id into v_id;
  return v_id;
end; $$;

do $$ declare f text; begin foreach f in array array['create_employee_contract(uuid,uuid,text,text,date,date,numeric,text,text,jsonb)','create_employee_work_schedule(uuid,uuid,text,text,jsonb,time,time,integer,date,date)','record_employee_attendance(uuid,uuid,date,text,timestamptz,timestamptz,text)','create_employee_payroll_period(uuid,date,date)','upsert_employee_payroll_entry(uuid,uuid,uuid,numeric,numeric,numeric,text,text)'] loop execute format('revoke all on function public.%s from public,anon,authenticated',f); execute format('grant execute on function public.%s to authenticated',f); end loop; end $$;
