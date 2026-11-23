-- Additive report submission workflow. Existing report tables and rows are untouched.
create table if not exists public.report_submissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  form_id uuid not null references public.report_form_templates(id) on delete restrict,
  employee_id uuid not null references auth.users(id) on delete restrict,
  employee_name text not null,
  branch_id uuid not null references public.branches(id) on delete restrict,
  branch_name text not null,
  report_date date not null default (timezone('Asia/Aden', now()))::date,
  answers jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','submitted','reviewed','approved','returned')),
  review_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_by_name text,
  approved_by uuid references auth.users(id) on delete set null,
  approved_by_name text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint report_submissions_answers_object check (jsonb_typeof(answers) = 'object'),
  constraint report_submissions_form_employee_branch_date_key unique (form_id, employee_id, branch_id, report_date)
);
create index if not exists report_submissions_org_branch_date_idx on public.report_submissions (organization_id, branch_id, report_date desc);
create index if not exists report_submissions_status_date_idx on public.report_submissions (organization_id, status, report_date desc);
create index if not exists report_submissions_employee_date_idx on public.report_submissions (employee_id, report_date desc);

insert into public.permissions (code, name_ar, domain, action) values
 ('report_submissions.review', 'مراجعة تقارير الموظفين', 'reports', 'review'),
 ('report_submissions.approve', 'اعتماد تقارير الموظفين نهائياً', 'reports', 'approve')
on conflict (code) do update set name_ar = excluded.name_ar, domain = excluded.domain, action = excluded.action;
insert into public.role_permissions (institution_id, role_id, permission_code)
select r.institution_id, r.id, p.code
from public.roles r
cross join public.permissions p
where ((r.code = 'admin_followup' and p.code = 'report_submissions.review')
    or (r.code = 'owner' and p.code = 'report_submissions.approve'))
on conflict do nothing;

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
    new.organization_id := v_org_id;
    new.employee_name := v_employee_name;
    new.branch_name := v_branch_name;
    if new.status not in ('draft','submitted') then raise exception 'الحالة الابتدائية غير مسموحة'; end if;
    if new.status = 'submitted' then new.submitted_at := coalesce(new.submitted_at, now()); end if;
  else
    if new.organization_id <> old.organization_id or new.form_id <> old.form_id or new.employee_id <> old.employee_id
       or new.branch_id <> old.branch_id or new.report_date <> old.report_date then
      raise exception 'لا يمكن تغيير هوية التقرير أو ارتباطاته بعد إنشائه';
    end if;
    if new.status is distinct from old.status then
      if old.status in ('draft','returned') and new.status = 'submitted' then
        if old.employee_id <> auth.uid() then raise exception 'إعادة الإرسال متاحة لصاحب التقرير فقط'; end if;
        new.submitted_at := now(); new.reviewed_by := null; new.reviewed_by_name := null; new.reviewed_at := null;
        new.approved_by := null; new.approved_by_name := null; new.approved_at := null;
      elsif old.status = 'submitted' and new.status in ('reviewed','returned') then
        if not public.employee_agreement_can(old.organization_id, 'report_submissions.review', old.branch_id) then
          raise exception 'لا تملك صلاحية مراجعة التقارير';
        end if;
        select m.display_name into v_actor_name from public.organization_memberships m
         where m.organization_id = old.organization_id and m.user_id = auth.uid() and m.is_active;
        new.reviewed_by := auth.uid(); new.reviewed_by_name := coalesce(v_actor_name, 'المراجع'); new.reviewed_at := now();
        if new.status = 'returned' and nullif(btrim(coalesce(new.review_note,'')), '') is null then
          raise exception 'يجب كتابة سبب إعادة التقرير';
        end if;
      elsif old.status = 'reviewed' and new.status in ('approved','returned') then
        if not public.employee_agreement_can(old.organization_id, 'report_submissions.approve', old.branch_id) then
          raise exception 'لا تملك صلاحية الاعتماد النهائي';
        end if;
        select m.display_name into v_actor_name from public.organization_memberships m
         where m.organization_id = old.organization_id and m.user_id = auth.uid() and m.is_active;
        if new.status = 'approved' then
          new.approved_by := auth.uid(); new.approved_by_name := coalesce(v_actor_name, 'المعتمد'); new.approved_at := now();
        elsif nullif(btrim(coalesce(new.review_note,'')), '') is null then
          raise exception 'يجب كتابة سبب إعادة التقرير';
        end if;
      else raise exception 'انتقال حالة التقرير غير مسموح';
      end if;
    else
      if old.status not in ('draft','returned') or old.employee_id <> auth.uid() then
        if new.answers is distinct from old.answers then raise exception 'لا يمكن تعديل إجابات التقرير بعد رفعه'; end if;
      end if;
      if new.review_note is distinct from old.review_note
         and not (public.employee_agreement_can(old.organization_id, 'report_submissions.review', old.branch_id)
               or public.employee_agreement_can(old.organization_id, 'report_submissions.approve', old.branch_id)) then
        raise exception 'لا تملك صلاحية تعديل ملاحظات المراجعة';
      end if;
    end if;
    new.employee_name := old.employee_name; new.branch_name := old.branch_name; new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prepare_report_submission on public.report_submissions;
create trigger trg_prepare_report_submission before insert or update on public.report_submissions
for each row execute function public.prepare_report_submission();

alter table public.report_submissions enable row level security;
drop policy if exists report_submissions_read on public.report_submissions;
create policy report_submissions_read on public.report_submissions for select to authenticated
using (employee_id = auth.uid()
  or public.employee_agreement_can(organization_id, 'report_submissions.review', branch_id)
  or public.employee_agreement_can(organization_id, 'report_submissions.approve', branch_id));
drop policy if exists report_submissions_insert_own on public.report_submissions;
create policy report_submissions_insert_own on public.report_submissions for insert to authenticated
with check (employee_id = auth.uid() and status in ('draft','submitted')
  and exists (select 1 from public.organization_memberships m where m.organization_id = report_submissions.organization_id and m.user_id = auth.uid() and m.is_active));
drop policy if exists report_submissions_update_workflow on public.report_submissions;
create policy report_submissions_update_workflow on public.report_submissions for update to authenticated
using ((employee_id = auth.uid() and status in ('draft','returned'))
  or (status = 'submitted' and public.employee_agreement_can(organization_id, 'report_submissions.review', branch_id))
  or (status = 'reviewed' and public.employee_agreement_can(organization_id, 'report_submissions.approve', branch_id)))
with check ((employee_id = auth.uid() and status in ('draft','returned','submitted'))
  or (status in ('reviewed','returned') and public.employee_agreement_can(organization_id, 'report_submissions.review', branch_id))
  or (status in ('approved','returned') and public.employee_agreement_can(organization_id, 'report_submissions.approve', branch_id)));
grant select, insert, update on public.report_submissions to authenticated;
