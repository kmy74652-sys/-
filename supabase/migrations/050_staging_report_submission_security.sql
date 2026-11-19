begin;

create or replace function public.guard_report_signature_mutation()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task uuid; v_snapshot uuid; v_field text;
begin
  if tg_op='INSERT' then
    select r.task_id,r.report_form_snapshot_id into v_task,v_snapshot from public.task_reports r where r.id=new.report_id;
    if not found or v_task<>new.task_id or v_snapshot is distinct from new.report_form_snapshot_id then raise exception using errcode='22023', message='report_signature_link_invalid'; end if;
    if not exists (
      select 1 from public.task_report_form_snapshots s,jsonb_array_elements(s.schema) f(value)
      where s.id=new.report_form_snapshot_id and f.value->>'key'=new.field_key and f.value->>'type'='signature'
    ) then raise exception using errcode='22023', message='report_signature_field_invalid'; end if;
    if jsonb_typeof(new.stroke_paths)<>'array' or jsonb_array_length(new.stroke_paths)<1 or jsonb_array_length(new.stroke_paths)>200 then raise exception using errcode='22023', message='invalid_report_signature'; end if;
    return new;
  end if;
  raise exception using errcode='42501', message='report_signature_immutable';
end $$;
create trigger task_report_signature_immutable
before insert or update or delete on public.task_report_signature_attachments
for each row execute function public.guard_report_signature_mutation();

create or replace function public.guard_task_report_snapshot_and_signature()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_signature record;
begin
  if tg_op='DELETE' then
    if exists(select 1 from public.task_report_signature_attachments a where a.report_id=old.id) then raise exception using errcode='42501', message='signed_report_immutable'; end if;
    return old;
  end if;
  if old.report_form_snapshot_id is distinct from new.report_form_snapshot_id or old.idempotency_key is distinct from new.idempotency_key then
    raise exception using errcode='42501', message='report_provenance_immutable';
  end if;
  for v_signature in select id,field_key from public.task_report_signature_attachments where report_id=old.id loop
    if new.values->v_signature.field_key->>'signature_attachment_id' is distinct from v_signature.id::text then
      raise exception using errcode='42501', message='report_signature_immutable';
    end if;
  end loop;
  return new;
end $$;
create trigger task_reports_signature_protection
before update or delete on public.task_reports
for each row execute function public.guard_task_report_snapshot_and_signature();

drop function if exists public.mobile_submit_task_report(uuid,jsonb);
create or replace function public.mobile_submit_task_report(p_task_id uuid, p_values jsonb, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_user_id uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_report public.task_reports%rowtype;
  v_snapshot public.task_report_form_snapshots%rowtype;
  v_field jsonb;
  v_raw jsonb;
  v_key text;
  v_type text;
  v_clean_values jsonb := p_values;
  v_signatures jsonb := '[]'::jsonb;
  v_signature_id uuid;
  v_signature jsonb;
  v_idempotency_key text;
  v_now timestamptz := now();
begin
  if v_user_id is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception using errcode='22023', message='invalid_task_report_payload'; end if;
  if p_idempotency_key is not null and (length(trim(p_idempotency_key))=0 or length(p_idempotency_key)>200) then raise exception using errcode='22023', message='invalid_report_idempotency_key'; end if;
  v_idempotency_key := coalesce(nullif(trim(p_idempotency_key),''),'report:' || p_task_id::text || ':' || gen_random_uuid()::text);
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found or v_task.assigned_to<>v_user_id then raise exception using errcode='P0002', message='task_not_found'; end if;
  if not exists(select 1 from public.organization_memberships m where m.organization_id=v_task.organization_id and m.user_id=v_user_id and m.is_active) then
    raise exception using errcode='42501', message='employee_not_active';
  end if;
  select * into v_report from public.task_reports where submitted_by=v_user_id and idempotency_key=v_idempotency_key;
  if found then
    if v_report.task_id<>v_task.id then raise exception using errcode='22023', message='report_idempotency_key_conflict'; end if;
    return jsonb_build_object('report',jsonb_build_object('id',v_report.id,'task_id',v_report.task_id,'submitted_by',v_report.submitted_by,'values',v_report.values,'created_at',v_report.created_at));
  end if;
  if v_task.status not in ('in_progress','needs_revision') then raise exception using errcode='22023', message='task_must_be_in_progress'; end if;
  if v_task.report_required and v_task.report_form_snapshot_id is null then raise exception using errcode='22023', message='task_report_snapshot_missing'; end if;

  if v_task.report_form_snapshot_id is not null then
    select * into v_snapshot from public.task_report_form_snapshots where id=v_task.report_form_snapshot_id and task_id=v_task.id;
    if not found then raise exception using errcode='22023', message='task_report_snapshot_missing'; end if;
    for v_key in select jsonb_object_keys(p_values) loop
      if not exists(select 1 from jsonb_array_elements(v_snapshot.schema) f(value) where f.value->>'key'=v_key) then raise exception using errcode='22023', message='unknown_report_field:' || v_key; end if;
    end loop;
    for v_field in select value from jsonb_array_elements(v_snapshot.schema) loop
      v_key := coalesce(v_field->>'key',''); v_type := coalesce(v_field->>'type',''); v_raw := p_values->v_key;
      perform public.report_validate_field(v_field,v_raw,p_values,v_task.id);
      if v_type='signature' and jsonb_typeof(v_raw)='object' and jsonb_typeof(v_raw->'strokes')='array' and jsonb_array_length(v_raw->'strokes')>0 then
        v_signature_id := gen_random_uuid();
        v_clean_values := jsonb_set(v_clean_values,array[v_key],jsonb_build_object('signature_attachment_id',v_signature_id,'acknowledged',coalesce(v_raw->'acknowledged','false'::jsonb),'signed_at',v_now),true);
        v_signatures := v_signatures || jsonb_build_array(jsonb_build_object('id',v_signature_id,'field_key',v_key,'strokes',v_raw->'strokes','consent_text',coalesce(v_field->'config'->>'consent_text',''),'acknowledged',coalesce((v_raw->>'acknowledged')::boolean,false)));
      elsif v_type='signature' then
        v_clean_values := v_clean_values - v_key;
      end if;
    end loop;
  else
    if exists(select 1 from public.task_report_fields f where f.task_id=v_task.id and f.field_type='signature') then raise exception using errcode='22023', message='report_signature_requires_snapshot'; end if;
    for v_key in select jsonb_object_keys(p_values) loop
      if not exists(select 1 from public.task_report_fields f where f.task_id=v_task.id and f.field_key=v_key) then raise exception using errcode='22023', message='unknown_report_field:' || v_key; end if;
    end loop;
    for v_field in select jsonb_build_object('field_key',f.field_key,'label',f.label,'required',f.is_required) as value from public.task_report_fields f where f.task_id=v_task.id loop
      v_key := v_field.value->>'field_key';
      if coalesce((v_field.value->>'required')::boolean,false) and (p_values->v_key is null or p_values->v_key='null'::jsonb or (jsonb_typeof(p_values->v_key)='string' and trim(p_values->>v_key)='')) then raise exception using errcode='22023', message='required_report_field_missing:' || coalesce(v_field.value->>'label',v_key); end if;
    end loop;
  end if;

  insert into public.task_reports(task_id,submitted_by,status,values,submitted_at,report_form_snapshot_id,idempotency_key)
  values(v_task.id,v_user_id,'submitted',v_clean_values,v_now,v_task.report_form_snapshot_id,v_idempotency_key)
  returning * into v_report;
  for v_signature in select value from jsonb_array_elements(v_signatures) loop
    insert into public.task_report_signature_attachments(id,task_id,report_id,report_form_snapshot_id,field_key,signed_by,consent_text,acknowledged,stroke_paths,signed_at)
    values((v_signature->>'id')::uuid,v_task.id,v_report.id,v_task.report_form_snapshot_id,v_signature->>'field_key',v_user_id,coalesce(v_signature->>'consent_text',''),coalesce((v_signature->>'acknowledged')::boolean,false),v_signature->'strokes',v_now);
  end loop;
  insert into public.task_activity_log(task_id,actor_id,action,details)
  values(v_task.id,v_user_id,'report_submitted',jsonb_build_object('report_id',v_report.id,'snapshot_id',v_task.report_form_snapshot_id));
  update public.tasks set status='report_submitted',report_submitted_at=v_now,updated_at=v_now where id=v_task.id;
  return jsonb_build_object('report',jsonb_build_object('id',v_report.id,'task_id',v_report.task_id,'submitted_by',v_report.submitted_by,'values',v_report.values,'created_at',v_report.created_at));
end $$;
revoke all on function public.mobile_submit_task_report(uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.mobile_submit_task_report(uuid,jsonb,text) to authenticated;

-- Replace the older global policies: every read/write decision now includes the matching organization.
alter table public.report_form_templates enable row level security;
alter table public.report_form_versions enable row level security;
alter table public.report_form_version_fields enable row level security;
alter table public.task_report_form_snapshots enable row level security;
alter table public.task_reports enable row level security;

drop policy if exists report_form_templates_read on public.report_form_templates;
drop policy if exists report_form_templates_manage on public.report_form_templates;
create policy report_form_templates_select_org on public.report_form_templates for select to authenticated
  using (public.report_designer_allowed_for_org(organization_id));

drop policy if exists report_form_versions_read on public.report_form_versions;
drop policy if exists report_form_versions_manage on public.report_form_versions;
create policy report_form_versions_select_org on public.report_form_versions for select to authenticated
  using (exists(select 1 from public.report_form_templates t where t.id=template_id and public.report_designer_allowed_for_org(t.organization_id)));

drop policy if exists report_form_fields_read on public.report_form_version_fields;
drop policy if exists report_form_fields_manage on public.report_form_version_fields;
create policy report_form_fields_select_org on public.report_form_version_fields for select to authenticated
  using (exists(select 1 from public.report_form_versions v join public.report_form_templates t on t.id=v.template_id where v.id=version_id and public.report_designer_allowed_for_org(t.organization_id)));

drop policy if exists task_report_snapshots_read on public.task_report_form_snapshots;
drop policy if exists task_report_snapshots_insert on public.task_report_form_snapshots;
drop policy if exists task_report_snapshots_select_scoped on public.task_report_form_snapshots;
create policy task_report_snapshots_select_scoped on public.task_report_form_snapshots for select to authenticated
  using (exists(
    select 1 from public.tasks t where t.id=task_id and (
      public.report_designer_allowed_for_org(t.organization_id)
      or public.report_can_review_in_org(t.organization_id)
      or public.has_org_permission(t.organization_id,'task_reports.read',null::uuid)
      or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id and m.user_id=auth.uid() and m.is_active and (t.assigned_to=auth.uid() or t.created_by=auth.uid()))
    )
  ));

drop policy if exists task_report_signatures_select_scoped on public.task_report_signature_attachments;
create policy task_report_signatures_select_scoped on public.task_report_signature_attachments for select to authenticated
  using (exists(
    select 1 from public.task_reports r join public.tasks t on t.id=r.task_id
    where r.id=report_id and (
      public.report_designer_allowed_for_org(t.organization_id)
      or public.report_can_review_in_org(t.organization_id)
      or public.has_org_permission(t.organization_id,'task_reports.read',null::uuid)
      or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id and m.user_id=auth.uid() and m.is_active and (r.submitted_by=auth.uid() or t.assigned_to=auth.uid()))
    )
  ));

-- Reports are submitted and reviewed through security-definer RPCs. Clients may read scoped reports, but may not rewrite submitted values or signature references directly.
drop policy if exists task_reports_insert_assignee on public.task_reports;
drop policy if exists task_reports_select_owner_or_reviewer on public.task_reports;
drop policy if exists task_reports_update_reviewer_or_submitter on public.task_reports;
drop policy if exists task_reports_select_scoped on public.task_reports;
create policy task_reports_select_scoped on public.task_reports for select to authenticated
  using (exists(
    select 1 from public.tasks t where t.id=task_id and (
      public.report_designer_allowed_for_org(t.organization_id)
      or public.report_can_review_in_org(t.organization_id)
      or public.has_org_permission(t.organization_id,'task_reports.read',null::uuid)
      or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id and m.user_id=auth.uid() and m.is_active and (submitted_by=auth.uid() or t.assigned_to=auth.uid() or t.created_by=auth.uid()))
    )
  ));

revoke all on public.report_form_templates, public.report_form_versions, public.report_form_version_fields, public.task_report_form_snapshots from public, anon, authenticated;
grant select on public.report_form_templates, public.report_form_versions, public.report_form_version_fields, public.task_report_form_snapshots to authenticated;
revoke insert, update, delete on public.task_reports from public, anon, authenticated;
grant select on public.task_reports to authenticated;

commit;
