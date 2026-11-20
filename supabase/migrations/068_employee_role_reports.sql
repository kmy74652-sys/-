begin;

create table if not exists public.employee_role_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null references public.roles(code),
  branch_id uuid references public.branches(id) on delete set null,
  report_date date not null default current_date,
  report_title text not null check (length(trim(report_title)) between 2 and 200),
  values jsonb not null default '{}'::jsonb check (jsonb_typeof(values) = 'object'),
  status text not null default 'submitted' check (status in ('submitted','approved','returned')),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_user_id, role_code, report_date)
);
create index if not exists employee_role_reports_org_status_idx on public.employee_role_reports(organization_id,status,submitted_at desc);
create index if not exists employee_role_reports_employee_date_idx on public.employee_role_reports(employee_user_id,report_date desc);
alter table public.employee_role_reports enable row level security;

drop policy if exists employee_role_reports_select on public.employee_role_reports;
create policy employee_role_reports_select on public.employee_role_reports for select to authenticated using (
  employee_user_id = auth.uid() or alshaari_private.has_permission(organization_id,'tasks.review',null::uuid) or alshaari_private.has_permission(organization_id,'reports.read_all',null::uuid)
);
revoke all on public.employee_role_reports from anon, authenticated;
grant select on public.employee_role_reports to authenticated;

create or replace function public.mobile_submit_employee_role_report(
  p_role_code text, p_branch_id uuid, p_report_date date, p_report_title text, p_values jsonb
) returns jsonb language plpgsql security definer set search_path=public,auth,alshaari_private as $$
declare v_org uuid; v_report public.employee_role_reports%rowtype; v_existing public.employee_role_reports%rowtype;
begin
  if auth.uid() is null then raise exception using errcode='28000',message='not_authenticated'; end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception using errcode='22023',message='invalid_role_report_payload'; end if;
  select m.organization_id into v_org from public.organization_memberships m where m.user_id=auth.uid() and m.is_active limit 1;
  if v_org is null then raise exception using errcode='42501',message='employee_not_active'; end if;
  if not exists(select 1 from public.organization_memberships m join public.role_assignments ra on ra.membership_id=m.id and ra.organization_id=m.organization_id where m.user_id=auth.uid() and m.organization_id=v_org and m.is_active and ra.role_code=p_role_code and (p_branch_id is null or ra.branch_id=p_branch_id)) then raise exception using errcode='42501',message='role_report_assignment_invalid'; end if;
  select * into v_existing from public.employee_role_reports where employee_user_id=auth.uid() and role_code=p_role_code and report_date=coalesce(p_report_date,current_date) for update;
  if found and v_existing.status in ('submitted','approved') then raise exception using errcode='22023',message='role_report_already_submitted'; end if;
  insert into public.employee_role_reports(organization_id,employee_user_id,role_code,branch_id,report_date,report_title,values,status,submitted_at,reviewed_at,reviewed_by,review_note,updated_at)
  values(v_org,auth.uid(),p_role_code,p_branch_id,coalesce(p_report_date,current_date),trim(p_report_title),p_values,'submitted',now(),null,null,null,now())
  on conflict(employee_user_id,role_code,report_date) do update set branch_id=excluded.branch_id,report_title=excluded.report_title,values=excluded.values,status='submitted',submitted_at=now(),reviewed_at=null,reviewed_by=null,review_note=null,updated_at=now()
  returning * into v_report;
  return jsonb_build_object('id',v_report.id,'status',v_report.status,'submitted_at',v_report.submitted_at);
end;
$$;
revoke all on function public.mobile_submit_employee_role_report(text,uuid,date,text,jsonb) from public,anon;
grant execute on function public.mobile_submit_employee_role_report(text,uuid,date,text,jsonb) to authenticated;

create or replace function public.review_employee_role_report(p_report_id uuid,p_decision text,p_note text default null) returns jsonb language plpgsql security definer set search_path=public,auth,alshaari_private as $$
declare v_report public.employee_role_reports%rowtype; v_status text;
begin
  select * into v_report from public.employee_role_reports where id=p_report_id for update;
  if not found then raise exception using errcode='P0002',message='role_report_not_found'; end if;
  if not alshaari_private.has_permission(v_report.organization_id,'tasks.review',null::uuid) and not alshaari_private.has_permission(v_report.organization_id,'reports.read_all',null::uuid) then raise exception using errcode='42501',message='permission_denied'; end if;
  if p_decision not in ('approved','returned') then raise exception using errcode='22023',message='invalid_report_decision'; end if;
  if p_decision='returned' and length(trim(coalesce(p_note,'')))<2 then raise exception using errcode='22023',message='review_note_required'; end if;
  v_status:=p_decision;
  update public.employee_role_reports set status=v_status,reviewed_at=now(),reviewed_by=auth.uid(),review_note=nullif(trim(p_note),''),updated_at=now() where id=p_report_id;
  insert into public.notifications(organization_id,recipient_user_id,title,body,severity)
  values(v_report.organization_id,v_report.employee_user_id,case when v_status='approved' then 'تم اعتماد التقرير' else 'أُعيد التقرير للتعديل' end,case when v_status='approved' then 'تم اعتماد التقرير الخاص بدورك.' else 'أُعيد التقرير الخاص بدورك للتعديل. راجع ملاحظة الإدارة.' end,case when v_status='approved' then 'info' else 'warning' end);
  return jsonb_build_object('id',p_report_id,'status',v_status);
end;
$$;
revoke all on function public.review_employee_role_report(uuid,text,text) from public,anon;
grant execute on function public.review_employee_role_report(uuid,text,text) to authenticated;

commit;
