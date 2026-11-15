begin;

alter table public.report_form_versions add column if not exists approved_by uuid references auth.users(id);
alter table public.report_form_versions add column if not exists approved_at timestamptz;

create or replace function public.approve_report_form_version(p_version_id uuid)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare v_user uuid := auth.uid(); v_version uuid;
begin
  if v_user is null or not exists (
    select 1 from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id=m.organization_id and ra.membership_id=m.id
    where m.user_id=v_user and m.is_active and ra.role_code='owner'
  ) then raise exception using errcode='42501', message='owner_approval_required'; end if;
  update public.report_form_versions set status='published', approved_by=v_user, approved_at=now(), published_at=coalesce(published_at, now()) where id=p_version_id returning id into v_version;
  if v_version is null then raise exception using errcode='P0002', message='report_form_version_not_found'; end if;
  return v_version;
end $$;
revoke all on function public.approve_report_form_version(uuid) from public, anon, authenticated;
grant execute on function public.approve_report_form_version(uuid) to authenticated;

commit;
