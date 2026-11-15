begin;

create or replace function public.mobile_submit_task_report(p_task_id uuid, p_values jsonb)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_user_id uuid := auth.uid(); v_task public.tasks%rowtype; v_report public.task_reports%rowtype; v_field record; v_snapshot public.task_report_form_snapshots%rowtype;
begin
  if v_user_id is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception using errcode='22023', message='invalid_task_report_payload'; end if;
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found or v_task.assigned_to <> v_user_id then raise exception using errcode='P0002', message='task_not_found'; end if;
  if v_task.status not in ('in_progress','needs_revision') then raise exception using errcode='22023', message='task_report_not_allowed'; end if;
  if v_task.report_form_snapshot_id is not null then
    select * into v_snapshot from public.task_report_form_snapshots where id=v_task.report_form_snapshot_id;
    for v_field in select value as field from jsonb_array_elements(v_snapshot.schema) where coalesce((value->>'required')::boolean, false) loop
      if coalesce(p_values ->> (v_field.field->>'key'), '') = '' then raise exception using errcode='22023', message='required_report_field_missing'; end if;
    end loop;
  else
    for v_field in select field_key from public.task_report_fields where task_id=v_task.id and is_required loop
      if coalesce(p_values ->> v_field.field_key, '') = '' then raise exception using errcode='22023', message='required_report_field_missing'; end if;
    end loop;
  end if;
  insert into public.task_reports(task_id,submitted_by,status,values,submitted_at) values(v_task.id,v_user_id,'submitted',p_values,now()) returning * into v_report;
  insert into public.task_activity_log(task_id,actor_id,action,details) values(v_task.id,v_user_id,'report_submitted',jsonb_build_object('report_id',v_report.id,'snapshot_id',v_task.report_form_snapshot_id));
  update public.tasks set status='report_submitted',report_submitted_at=now(),updated_at=now() where id=v_task.id;
  return jsonb_build_object('report',jsonb_build_object('id',v_report.id,'task_id',v_report.task_id,'submitted_by',v_report.submitted_by,'values',v_report.values,'created_at',v_report.created_at));
end $$;
revoke all on function public.mobile_submit_task_report(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.mobile_submit_task_report(uuid,jsonb) to authenticated;

commit;
