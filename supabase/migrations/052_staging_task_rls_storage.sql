begin;

-- Task table scope: employees see assigned tasks, creators see their work, and managers get only their tenant.
alter table public.tasks enable row level security;
drop policy if exists tasks_select_scoped on public.tasks;
create policy tasks_select_scoped on public.tasks for select to authenticated using (
 public.is_organization_member(organization_id) and
 (assigned_to=auth.uid() or created_by=auth.uid() or public.has_org_permission(organization_id,'tasks.read_all',null::uuid))
);
drop policy if exists tasks_manage_scoped on public.tasks;
create policy tasks_manage_scoped on public.tasks for all to authenticated using (
 public.has_org_permission(organization_id,'tasks.manage',null::uuid)
) with check (public.has_org_permission(organization_id,'tasks.manage',null::uuid));

alter table public.task_templates enable row level security;
drop policy if exists task_templates_read_scoped on public.task_templates;
create policy task_templates_read_scoped on public.task_templates for select to authenticated using (
 public.task_library_allowed_for_org(organization_id,'task_library.read') or public.task_library_allowed_for_org(organization_id,'task_library.manage')
);
drop policy if exists task_templates_manage_scoped on public.task_templates;
create policy task_templates_manage_scoped on public.task_templates for all to authenticated using (
 public.task_library_allowed_for_org(organization_id,'task_library.manage')
) with check (public.task_library_allowed_for_org(organization_id,'task_library.manage'));

alter table public.task_reports enable row level security;
drop policy if exists task_reports_select_scoped on public.task_reports;
create policy task_reports_select_scoped on public.task_reports for select to authenticated using (
 exists(select 1 from public.tasks t where t.id=task_id and (
  t.assigned_to=auth.uid() or t.created_by=auth.uid() or public.report_designer_allowed_for_org(t.organization_id)
  or public.report_can_review_in_org(t.organization_id) or public.has_org_permission(t.organization_id,'task_reports.read',null::uuid)
 ))
);
alter table public.task_report_fields enable row level security;
drop policy if exists task_report_fields_select_scoped on public.task_report_fields;
create policy task_report_fields_select_scoped on public.task_report_fields for select to authenticated using (
 exists(select 1 from public.tasks t where t.id=task_id and (t.assigned_to=auth.uid() or t.created_by=auth.uid() or public.has_org_permission(t.organization_id,'tasks.read_all',null::uuid)))
);
alter table public.task_activity_log enable row level security;
drop policy if exists task_activity_log_read_scoped on public.task_activity_log;
create policy task_activity_log_read_scoped on public.task_activity_log for select to authenticated using (
 exists(select 1 from public.tasks t where t.id=task_id and (t.assigned_to=auth.uid() or t.created_by=auth.uid() or public.has_org_permission(t.organization_id,'tasks.read_all',null::uuid)))
);
create or replace function public.prevent_task_activity_mutation()
returns trigger language plpgsql set search_path=public as $$
begin raise exception using errcode='42501',message='task_activity_log_append_only'; end $$;
drop trigger if exists task_activity_log_no_update on public.task_activity_log;
create trigger task_activity_log_no_update before update or delete on public.task_activity_log for each row execute function public.prevent_task_activity_mutation();

alter table public.task_attachments enable row level security;
drop policy if exists task_attachments_read_scoped on public.task_attachments;
create policy task_attachments_read_scoped on public.task_attachments for select to authenticated using (
 exists(select 1 from public.tasks t where t.id=task_id and (t.assigned_to=auth.uid() or t.created_by=auth.uid() or public.has_org_permission(t.organization_id,'task_reports.read',null::uuid) or public.has_org_permission(t.organization_id,'tasks.read_all',null::uuid)))
);
drop policy if exists task_attachments_insert_assignee on public.task_attachments;
create policy task_attachments_insert_assignee on public.task_attachments for insert to authenticated with check (
 uploaded_by=auth.uid() and exists(select 1 from public.tasks t where t.id=task_id and (t.assigned_to=auth.uid() or t.created_by=auth.uid()))
);

-- RPC-only writes protect report provenance, signatures, and task snapshots from client tampering.
revoke all on public.tasks,public.task_reports,public.task_report_fields,public.task_activity_log,public.task_attachments,
 public.task_report_form_snapshots,public.task_report_signature_attachments,public.task_execution_steps,
 public.task_report_drafts,public.task_template_steps,public.task_template_report_forms,public.task_template_report_fields,
 public.task_categories,public.task_templates,public.report_form_templates,public.report_form_versions,public.report_form_version_fields
 from public,anon;
grant select on public.tasks,public.task_reports,public.task_report_fields,public.task_activity_log,public.task_attachments,
 public.task_report_form_snapshots,public.task_report_signature_attachments,public.task_execution_steps,
 public.task_report_drafts,public.task_template_steps,public.task_template_report_forms,public.task_template_report_fields,
 public.task_categories,public.task_templates,public.report_form_templates,public.report_form_versions,public.report_form_version_fields
 to authenticated;
grant insert on public.task_attachments to authenticated;
grant insert,update on public.task_categories to authenticated;
grant update on public.task_templates to authenticated;
revoke insert,update,delete on public.tasks,public.task_reports,public.task_report_fields,public.task_activity_log,
 public.task_report_form_snapshots,public.task_report_signature_attachments,public.task_execution_steps,public.task_report_drafts,
 public.task_template_steps,public.task_template_report_forms,public.task_template_report_fields,
 public.report_form_templates,public.report_form_versions,public.report_form_version_fields from authenticated;

-- Employee task status changes are authenticated and derived from auth.uid(), not a client-supplied employee ID.
create or replace function public.mobile_record_task_update(p_task_id uuid,p_status text,p_note text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_task public.tasks%rowtype; v_next text; v_action text;
begin
 if auth.uid() is null then raise exception using errcode='28000',message='not_authenticated'; end if;
 select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
 if not found or (v_task.assigned_to<>auth.uid() and v_task.created_by<>auth.uid()) then raise exception using errcode='P0002',message='task_not_found'; end if;
 if not public.has_org_permission(v_task.organization_id,'tasks.read',null::uuid) then raise exception using errcode='42501',message='permission_denied'; end if;
 if p_status='in_progress' and v_task.status in ('new','received','in_progress','needs_revision') then v_next:='in_progress'; v_action:='started';
 elsif p_status in ('pending','received') then v_next:='received'; v_action:='received';
 elsif p_status='submitted' then
   if not exists(select 1 from public.task_reports r where r.task_id=v_task.id and r.submitted_by=auth.uid()) then raise exception using errcode='22023',message='task_report_required'; end if;
   v_next:='report_submitted'; v_action:='report_submitted';
 else raise exception using errcode='22023',message='invalid_progress_status'; end if;
 insert into public.task_activity_log(task_id,actor_id,action,details) values(v_task.id,auth.uid(),v_action,jsonb_build_object('note',nullif(trim(p_note),''),'previous_status',v_task.status,'new_status',v_next));
 update public.tasks set status=v_next,started_at=case when v_next='in_progress' then coalesce(started_at,now()) else started_at end,
 report_submitted_at=case when v_next='report_submitted' then coalesce(report_submitted_at,now()) else report_submitted_at end,updated_at=now() where id=v_task.id;
 return v_task.id;
end $$;
revoke all on function public.mobile_record_task_update(uuid,text,text) from public,anon,authenticated;
grant execute on function public.mobile_record_task_update(uuid,text,text) to authenticated;

create or replace function public.mobile_task_timeline(p_task_id uuid)
returns table(event_id uuid,task_id uuid,action_type text,actor_id uuid,actor_name text,previous_status text,new_status text,notes text,created_at timestamptz)
language plpgsql stable security definer set search_path=public,auth as $$
begin
 if auth.uid() is null then raise exception using errcode='28000',message='not_authenticated'; end if;
 return query select l.id,l.task_id,l.action,l.actor_id,coalesce(u.raw_user_meta_data->>'full_name',u.email,'النظام'),
  nullif(l.details->>'previous_status',''),nullif(l.details->>'new_status',''),coalesce(nullif(l.details->>'note',''),l.action),l.created_at
 from public.task_activity_log l join public.tasks t on t.id=l.task_id left join auth.users u on u.id=l.actor_id
 where l.task_id=p_task_id and (t.assigned_to=auth.uid() or t.created_by=auth.uid() or public.has_org_permission(t.organization_id,'tasks.read_all',null::uuid))
 order by l.created_at asc;
end $$;
revoke all on function public.mobile_task_timeline(uuid) from public,anon,authenticated;
grant execute on function public.mobile_task_timeline(uuid) to authenticated;

-- Private task-attachment bucket: keys are task UUIDs, matching the mobile uploader.
insert into storage.buckets(id,name,public,file_size_limit) values('task-attachments','task-attachments',false,20971520)
on conflict(id) do update set public=false,file_size_limit=20971520;
drop policy if exists task_attachment_storage_read on storage.objects;
create policy task_attachment_storage_read on storage.objects for select to authenticated using(
 bucket_id='task-attachments' and exists(select 1 from public.tasks t where t.id::text=split_part(name,'/',1)
 and (t.assigned_to=auth.uid() or t.created_by=auth.uid() or public.has_org_permission(t.organization_id,'task_reports.read',null::uuid) or public.has_org_permission(t.organization_id,'tasks.read_all',null::uuid)))
);
drop policy if exists task_attachment_storage_insert on storage.objects;
create policy task_attachment_storage_insert on storage.objects for insert to authenticated with check(
 bucket_id='task-attachments' and exists(select 1 from public.tasks t where t.id::text=split_part(name,'/',1) and t.assigned_to=auth.uid())
);

commit;
