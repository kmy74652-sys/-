begin;

-- The production schema uses organization_memberships/auth.users and the modern
-- task status enum. Keep a stable field key for mobile report forms.
alter table public.task_report_fields
  add column if not exists field_key text;

update public.task_report_fields
set field_key = coalesce(nullif(field_key, ''), 'field_' || left(id::text, 8))
where field_key is null or field_key = '';

create or replace function public.mobile_record_task_update(
  p_task_id uuid,
  p_status text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_membership boolean;
  v_next public.task_status;
  v_action text;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  select exists (
    select 1 from public.organization_memberships m
    where m.user_id = v_user_id and m.is_active
  ) into v_membership;
  if not v_membership then
    raise exception using errcode = '42501', message = 'employee_not_active';
  end if;

  select * into v_task
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found or (v_task.assigned_to <> v_user_id and v_task.created_by <> v_user_id) then
    raise exception using errcode = 'P0002', message = 'task_not_found';
  end if;

  if p_status = 'in_progress' then
    if v_task.status not in ('new', 'received', 'in_progress', 'needs_revision') then
      raise exception using errcode = '22023', message = 'invalid_progress_transition';
    end if;
    v_next := 'in_progress';
    v_action := 'started';
  elsif p_status in ('pending', 'received') then
    v_next := 'received';
    v_action := 'received';
  else
    raise exception using errcode = '22023', message = 'invalid_progress_status';
  end if;

  insert into public.task_activity_log (task_id, actor_id, action, details)
  values (v_task.id, v_user_id, v_action, jsonb_build_object('note', nullif(trim(p_note), '')));

  update public.tasks
  set status = v_next,
      started_at = case when v_next = 'in_progress' then coalesce(started_at, now()) else started_at end,
      updated_at = now()
  where id = v_task.id;
  return v_task.id;
end;
$$;

create or replace function public.mobile_submit_task_report(
  p_task_id uuid,
  p_values jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_report public.task_reports%rowtype;
  v_field record;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_task_report_payload';
  end if;

  select * into v_task
  from public.tasks
  where id = p_task_id and deleted_at is null
  for update;
  if not found or v_task.assigned_to <> v_user_id then
    raise exception using errcode = 'P0002', message = 'task_not_found';
  end if;
  if v_task.status not in ('in_progress', 'needs_revision') then
    raise exception using errcode = '22023', message = 'task_report_not_allowed';
  end if;

  for v_field in
    select field_key, label
    from public.task_report_fields
    where task_id = v_task.id and is_required
  loop
    if v_field.field_key is not null and coalesce(p_values ->> v_field.field_key, '') = '' then
      raise exception using errcode = '22023', message = 'required_report_field_missing';
    end if;
  end loop;

  insert into public.task_reports (task_id, submitted_by, status, values, submitted_at)
  values (v_task.id, v_user_id, 'submitted', p_values, now())
  returning * into v_report;

  insert into public.task_activity_log (task_id, actor_id, action, details)
  values (v_task.id, v_user_id, 'report_submitted', jsonb_build_object('report_id', v_report.id));

  update public.tasks
  set status = 'report_submitted', report_submitted_at = now(), updated_at = now()
  where id = v_task.id;

  return jsonb_build_object('report', jsonb_build_object(
    'id', v_report.id,
    'task_id', v_report.task_id,
    'submitted_by', v_report.submitted_by,
    'values', v_report.values,
    'created_at', v_report.created_at
  ));
end;
$$;

create or replace function public.mobile_review_task(
  p_task_id uuid,
  p_decision text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_report public.task_reports%rowtype;
  v_role text;
  v_next public.task_status;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  select ra.role_code into v_role
  from public.role_assignments ra
  join public.organization_memberships m on m.id = ra.membership_id and m.organization_id = ra.organization_id
  where m.user_id = v_user_id and m.is_active
    and ra.role_code in ('owner', 'admin_followup')
  order by case when ra.role_code = 'owner' then 0 else 1 end
  limit 1;
  if v_role is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  select * into v_task from public.tasks where id = p_task_id and deleted_at is null for update;
  if not found or v_task.status <> 'report_submitted' or v_task.assigned_to = v_user_id then
    raise exception using errcode = 'P0002', message = 'task_not_found';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'invalid_review_decision';
  end if;

  select * into v_report from public.task_reports
  where task_id = v_task.id and status = 'submitted'
  order by submitted_at desc limit 1
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'task_report_not_found';
  end if;

  v_next := case when p_decision = 'approved' then 'completed_approved' else 'needs_revision' end;
  update public.task_reports
  set status = case when p_decision = 'approved' then 'approved' else 'returned' end,
      reviewed_by = v_user_id, reviewed_at = now(),
      review_action = case when p_decision = 'approved' then 'approved' else 'returned_for_revision' end,
      review_note = nullif(trim(p_note), ''), updated_at = now()
  where id = v_report.id;

  insert into public.task_activity_log (task_id, actor_id, action, details)
  values (v_task.id, v_user_id, p_decision, jsonb_build_object('note', nullif(trim(p_note), '')));

  update public.tasks
  set status = v_next,
      approved_at = case when v_next = 'completed_approved' then now() else null end,
      updated_at = now()
  where id = v_task.id;
  return v_task.id;
end;
$$;

revoke all on function public.mobile_record_task_update(uuid, text, text) from public, anon, authenticated;
revoke all on function public.mobile_submit_task_report(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.mobile_review_task(uuid, text, text) from public, anon, authenticated;
grant execute on function public.mobile_record_task_update(uuid, text, text) to authenticated;
grant execute on function public.mobile_submit_task_report(uuid, jsonb) to authenticated;
grant execute on function public.mobile_review_task(uuid, text, text) to authenticated;

commit;
