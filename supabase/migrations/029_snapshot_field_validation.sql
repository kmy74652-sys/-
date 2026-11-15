begin;

create or replace function public.mobile_submit_task_report(p_task_id uuid, p_values jsonb)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_user_id uuid := auth.uid(); v_task public.tasks%rowtype; v_report public.task_reports%rowtype; v_field record; v_snapshot public.task_report_form_snapshots%rowtype; v_key text; v_raw jsonb; v_type text; v_options jsonb; v_min numeric; v_max numeric;
begin
  if v_user_id is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception using errcode='22023', message='invalid_task_report_payload'; end if;
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found or v_task.assigned_to <> v_user_id then raise exception using errcode='P0002', message='task_not_found'; end if;
  if v_task.status not in ('in_progress','needs_revision') then raise exception using errcode='22023', message='task_report_not_allowed'; end if;
  if v_task.report_form_snapshot_id is not null then
    select * into v_snapshot from public.task_report_form_snapshots where id=v_task.report_form_snapshot_id;
    for v_field in select value as field from jsonb_array_elements(v_snapshot.schema) loop
      v_key := v_field.field->>'key'; v_type := v_field.field->>'type'; v_raw := p_values->v_key; v_options := coalesce(v_field.field->'options','[]'::jsonb);
      if coalesce((v_field.field->>'required')::boolean,false) and (v_raw is null or trim(coalesce(v_raw#>>'{}',''))='') then raise exception using errcode='22023', message='required_report_field_missing'; end if;
      if v_raw is null then continue; end if;
      if v_type in ('integer','quantity','money') then
        begin perform (v_raw#>>'{}')::numeric; exception when others then raise exception using errcode='22023', message='invalid_report_field_type'; end;
        v_min := nullif(v_field.field->'validation'->>'min','')::numeric; v_max := nullif(v_field.field->'validation'->>'max','')::numeric;
        if v_min is not null and (v_raw#>>'{}')::numeric < v_min then raise exception using errcode='22023', message='report_field_below_min'; end if;
        if v_max is not null and (v_raw#>>'{}')::numeric > v_max then raise exception using errcode='22023', message='report_field_above_max'; end if;
      elsif v_type in ('select','multiselect') then
        if v_type='select' and not (v_options ? (v_raw#>>'{}')) then raise exception using errcode='22023', message='invalid_report_field_option'; end if;
        if v_type='multiselect' then
          if jsonb_typeof(v_raw) <> 'array' or exists (select 1 from jsonb_array_elements_text(v_raw) x where not (v_options ? x.value)) then raise exception using errcode='22023', message='invalid_report_field_option'; end if;
        end if;
      elsif v_type='table' and jsonb_typeof(v_raw) <> 'array' then raise exception using errcode='22023', message='invalid_report_field_type'; end if;
    end loop;
  else
    for v_field in select field_key from public.task_report_fields where task_id=v_task.id and is_required loop
      if coalesce(p_values->>v_field.field_key,'')='' then raise exception using errcode='22023', message='required_report_field_missing'; end if;
    end loop;
  end if;
  insert into public.task_reports(task_id,submitted_by,status,values,submitted_at) values(v_task.id,v_user_id,'submitted',p_values,now()) returning * into v_report;
  insert into public.task_activity_log(task_id,actor_id,action,details) values(v_task.id,v_user_id,'report_submitted',jsonb_build_object('report_id',v_report.id,'snapshot_id',v_task.report_form_snapshot_id));
  update public.tasks set status='report_submitted',report_submitted_at=now(),updated_at=now() where id=v_task.id;
  return jsonb_build_object('report',jsonb_build_object('id',v_report.id,'task_id',v_report.task_id,'submitted_by',v_report.submitted_by,'values',v_report.values,'created_at',v_report.created_at));
end $$;
revoke all on function public.mobile_submit_task_report(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.mobile_submit_task_report(uuid,jsonb) to authenticated;

commit;
