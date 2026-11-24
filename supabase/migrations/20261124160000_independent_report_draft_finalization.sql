begin;

-- Independent dynamic reports need a real draft state before employee submission.
alter table public.employee_dynamic_reports
  drop constraint if exists employee_dynamic_reports_status_check;
alter table public.employee_dynamic_reports
  add constraint employee_dynamic_reports_status_check
  check (status in ('draft','submitted','approved','returned'));

create or replace function public.save_my_dynamic_report_draft(
  p_template_id uuid,
  p_version_id uuid,
  p_report_date date,
  p_values jsonb,
  p_branch_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_report_id uuid;
  v_status text;
begin
  if v_user is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_dynamic_report_payload';
  end if;
  select t.organization_id, t.role_code into v_org, v_role
  from public.report_form_templates t
  join public.report_form_versions v on v.template_id = t.id
  where t.id = p_template_id and v.id = p_version_id and t.is_active
    and v.status = 'published' and v.approved_by is not null and v.approved_at is not null;
  if not found then
    raise exception using errcode = '22023', message = 'dynamic_report_form_not_available';
  end if;
  if not exists (
    select 1 from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
    where m.organization_id = v_org and m.user_id = v_user and m.is_active
      and ra.role_code = v_role and (p_branch_id is null or ra.branch_id = p_branch_id)
  ) then
    raise exception using errcode = '42501', message = 'dynamic_report_assignment_invalid';
  end if;
  select id, status into v_report_id, v_status
  from public.employee_dynamic_reports
  where template_id = p_template_id and version_id = p_version_id
    and employee_user_id = v_user and report_date = p_report_date
  for update;
  if v_status = 'approved' then
    raise exception using errcode = '22023', message = 'dynamic_report_already_approved';
  end if;
  if v_report_id is null then
    insert into public.employee_dynamic_reports
      (organization_id, template_id, version_id, employee_user_id, role_code, branch_id, report_date, status, values, submitted_at)
    values (v_org, p_template_id, p_version_id, v_user, v_role, p_branch_id, p_report_date, 'draft', p_values, null)
    returning id into v_report_id;
  else
    update public.employee_dynamic_reports
    set values = p_values, status = 'draft', review_note = null,
        reviewed_at = null, updated_at = now(), branch_id = p_branch_id
    where id = v_report_id;
  end if;
  return v_report_id;
end;
$$;

create or replace function public.finalize_employee_dynamic_report(
  p_report_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, alshaari_private
as $$
declare
  v_report public.employee_dynamic_reports%rowtype;
begin
  select * into v_report from public.employee_dynamic_reports where id = p_report_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'dynamic_report_not_found'; end if;
  if not alshaari_private.has_permission(v_report.organization_id, 'tasks.review', null::uuid)
     and not alshaari_private.has_permission(v_report.organization_id, 'reports.read_all', null::uuid) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if v_report.status <> 'draft' then
    raise exception using errcode = '22023', message = 'dynamic_report_not_draft';
  end if;
  if now() < coalesce(v_report.created_at, v_report.updated_at) + interval '24 hours' then
    raise exception using errcode = '22023', message = 'dynamic_report_24h_not_elapsed';
  end if;
  update public.employee_dynamic_reports
  set status = 'submitted', submitted_at = now(), reviewed_at = null, updated_at = now()
  where id = p_report_id
  returning * into v_report;
  return jsonb_build_object('id', v_report.id, 'status', v_report.status, 'submitted_at', v_report.submitted_at);
end;
$$;

create or replace function public.finalize_report_submission(
  p_report_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_report public.report_submissions%rowtype;
  v_actor text;
begin
  select * into v_report from public.report_submissions where id = p_report_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'report_submission_not_found'; end if;
  if not public.employee_agreement_can(v_report.organization_id, 'report_submissions.review', v_report.branch_id)
     and not public.employee_agreement_can(v_report.organization_id, 'report_submissions.approve', v_report.branch_id) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if v_report.status <> 'draft' then
    raise exception using errcode = '22023', message = 'report_submission_not_draft';
  end if;
  if now() < v_report.created_at + interval '24 hours' then
    raise exception using errcode = '22023', message = 'report_submission_24h_not_elapsed';
  end if;
  select m.display_name into v_actor
  from public.organization_memberships m
  where m.organization_id = v_report.organization_id and m.user_id = auth.uid() and m.is_active;
  update public.report_submissions
  set status = 'submitted', submitted_at = now(), reviewed_by = null, reviewed_by_name = null,
      reviewed_at = null, approved_by = null, approved_by_name = null, approved_at = null,
      updated_at = now()
  where id = p_report_id
  returning * into v_report;
  return jsonb_build_object('id', v_report.id, 'status', v_report.status, 'submitted_at', v_report.submitted_at, 'finalized_by', coalesce(v_actor, 'الإدارة'));
end;
$$;

create or replace function public.prepare_report_submission()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_org_id uuid;
  v_form_active boolean;
  v_branch_name text;
  v_employee_name text;
  v_actor_name text;
begin
  select f.organization_id, f.is_active into v_org_id, v_form_active
  from public.report_form_templates f where f.id = new.form_id;
  if v_org_id is null or not v_form_active then raise exception 'نموذج التقرير غير موجود أو غير نشط'; end if;
  if not exists (select 1 from public.branches b where b.id = new.branch_id and b.organization_id = v_org_id and b.is_active) then
    raise exception 'الفرع غير تابع للمؤسسة أو غير نشط';
  end if;
  select b.name into v_branch_name from public.branches b where b.id = new.branch_id;
  select m.display_name into v_employee_name from public.organization_memberships m
  where m.organization_id = v_org_id and m.user_id = new.employee_id and m.is_active;
  if tg_op = 'INSERT' then
    if new.employee_id <> auth.uid() then raise exception 'لا يمكن إنشاء تقرير لموظف آخر'; end if;
    if v_employee_name is null then raise exception 'المستخدم ليس عضواً نشطاً في المؤسسة'; end if;
    new.organization_id := v_org_id; new.employee_name := v_employee_name; new.branch_name := v_branch_name;
    if new.status not in ('draft','submitted') then raise exception 'الحالة الابتدائية غير مسموحة'; end if;
    if new.status = 'submitted' then new.submitted_at := coalesce(new.submitted_at, now()); end if;
  else
    if new.organization_id <> old.organization_id or new.form_id <> old.form_id or new.employee_id <> old.employee_id
       or new.branch_id <> old.branch_id or new.report_date <> old.report_date then
      raise exception 'لا يمكن تغيير هوية التقرير أو ارتباطاته بعد إنشائه';
    end if;
    if new.status is distinct from old.status then
      if old.status in ('draft','returned') and new.status = 'submitted' then
        if old.employee_id <> auth.uid() and
           (not public.employee_agreement_can(old.organization_id, 'report_submissions.review', old.branch_id)
            or now() < old.created_at + interval '24 hours') then
          raise exception 'إعادة الإرسال متاحة لصاحب التقرير فقط قبل مرور 24 ساعة، وبعدها يلزم ترحيل الإدارة';
        end if;
        new.submitted_at := now(); new.reviewed_by := null; new.reviewed_by_name := null; new.reviewed_at := null;
        new.approved_by := null; new.approved_by_name := null; new.approved_at := null;
      elsif old.status = 'submitted' and new.status in ('reviewed','returned') then
        if not public.employee_agreement_can(old.organization_id, 'report_submissions.review', old.branch_id) then raise exception 'لا تملك صلاحية مراجعة التقارير'; end if;
        select m.display_name into v_actor_name from public.organization_memberships m where m.organization_id = old.organization_id and m.user_id = auth.uid() and m.is_active;
        new.reviewed_by := auth.uid(); new.reviewed_by_name := coalesce(v_actor_name, 'المراجع'); new.reviewed_at := now();
        if new.status = 'returned' and nullif(btrim(coalesce(new.review_note,'')), '') is null then raise exception 'يجب كتابة سبب إعادة التقرير'; end if;
      elsif old.status = 'reviewed' and new.status in ('approved','returned') then
        if not public.employee_agreement_can(old.organization_id, 'report_submissions.approve', old.branch_id) then raise exception 'لا تملك صلاحية الاعتماد النهائي'; end if;
        select m.display_name into v_actor_name from public.organization_memberships m where m.organization_id = old.organization_id and m.user_id = auth.uid() and m.is_active;
        if new.status = 'approved' then new.approved_by := auth.uid(); new.approved_by_name := coalesce(v_actor_name, 'المعتمد'); new.approved_at := now();
        elsif nullif(btrim(coalesce(new.review_note,'')), '') is null then raise exception 'يجب كتابة سبب إعادة التقرير'; end if;
      else raise exception 'انتقال حالة التقرير غير مسموح';
      end if;
    else
      if old.status not in ('draft','returned') or old.employee_id <> auth.uid() then
        if new.answers is distinct from old.answers then raise exception 'لا يمكن تعديل إجابات التقرير بعد رفعه'; end if;
      end if;
      if new.review_note is distinct from old.review_note and not (public.employee_agreement_can(old.organization_id, 'report_submissions.review', old.branch_id) or public.employee_agreement_can(old.organization_id, 'report_submissions.approve', old.branch_id)) then
        raise exception 'لا تملك صلاحية تعديل ملاحظات المراجعة';
      end if;
    end if;
    new.employee_name := old.employee_name; new.branch_name := old.branch_name; new.updated_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.list_my_dynamic_report_forms()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  return coalesce((
    select jsonb_agg(row_data order by title)
    from (
      select distinct on (t.id)
        jsonb_build_object(
          'template_id', t.id, 'version_id', v.id, 'title', t.title,
          'description', t.description, 'role_code', t.role_code,
          'report_date', (now() at time zone 'Asia/Aden')::date,
          'status', current_report.status, 'review_note', current_report.review_note,
          'values', coalesce(current_report.values, '{}'::jsonb),
          'created_at', current_report.created_at,
          'submitted_at', current_report.submitted_at,
          'fields', coalesce((select jsonb_agg(jsonb_build_object(
            'key', f.field_key, 'label', f.label, 'description', f.description,
            'type', f.field_type, 'required', f.is_required, 'repeatable', f.repeatable,
            'options', f.options, 'validation', f.validation, 'config', f.config
          ) order by f.sort_order) from public.report_form_version_fields f where f.version_id = v.id), '[]'::jsonb)
        ) as row_data,
        t.title
      from public.report_form_templates t
      join public.report_form_versions v on v.template_id = t.id
        and v.status = 'published' and v.approved_by is not null and v.approved_at is not null
        and v.version_no = (select max(v2.version_no) from public.report_form_versions v2
          where v2.template_id = t.id and v2.status = 'published'
            and v2.approved_by is not null and v2.approved_at is not null)
      join public.organization_memberships m on m.organization_id = t.organization_id
        and m.user_id = v_user and m.is_active
      join public.role_assignments ra on ra.organization_id = m.organization_id
        and ra.membership_id = m.id and ra.role_code = t.role_code
      left join lateral (
        select r.status, r.review_note, r.values, r.created_at, r.submitted_at
        from public.employee_dynamic_reports r
        where r.template_id = t.id and r.version_id = v.id
          and r.employee_user_id = v_user
          and r.report_date = (now() at time zone 'Asia/Aden')::date
        limit 1
      ) current_report on true
      where t.is_active
      order by t.id, ra.branch_id nulls last
    ) forms
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.save_my_dynamic_report_draft(uuid,uuid,date,jsonb,uuid) from public, anon, authenticated;
revoke all on function public.finalize_employee_dynamic_report(uuid) from public, anon, authenticated;
revoke all on function public.finalize_report_submission(uuid) from public, anon, authenticated;
grant execute on function public.save_my_dynamic_report_draft(uuid,uuid,date,jsonb,uuid) to authenticated;
grant execute on function public.finalize_employee_dynamic_report(uuid) to authenticated;
grant execute on function public.finalize_report_submission(uuid) to authenticated;

commit;
