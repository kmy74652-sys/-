begin;

-- A suspended employee may still hold an unexpired Supabase JWT.
-- Every direct task ownership path must therefore verify an active membership,
-- not merely compare the task's assignee/creator with auth.uid().

drop policy if exists tasks_select_assigned_or_manager on public.tasks;
create policy tasks_select_assigned_or_manager
on public.tasks
for select
to authenticated
using (
  (
    assigned_to = (select auth.uid())
    and exists (
      select 1
      from public.organization_memberships m
      where m.organization_id = tasks.organization_id
        and m.user_id = (select auth.uid())
        and m.is_active
    )
  )
  or alshaari_private.has_permission(organization_id, 'tasks.manage', null::uuid)
  or alshaari_private.has_permission(organization_id, 'tasks.review', null::uuid)
  or alshaari_private.has_permission(organization_id, 'task_reports.read', null::uuid)
);

drop policy if exists task_activity_log_read on public.task_activity_log;
create policy task_activity_log_read
on public.task_activity_log
for select
to authenticated
using (
  exists (
    select 1
    from public.tasks t
    join public.organization_memberships m
      on m.organization_id = t.organization_id
     and m.user_id = (select auth.uid())
     and m.is_active
    where t.id = task_activity_log.task_id
      and (
        t.assigned_to = (select auth.uid())
        or t.created_by = (select auth.uid())
        or exists (
          select 1
          from public.role_assignments ra
          where ra.organization_id = m.organization_id
            and ra.membership_id = m.id
            and ra.role_code in ('owner', 'admin_followup')
        )
      )
  )
);

drop policy if exists task_attachments_insert_uploader_on_visible_task on public.task_attachments;
create policy task_attachments_insert_uploader_on_visible_task
on public.task_attachments
for insert
to authenticated
with check (
  uploaded_by = (select auth.uid())
  and exists (
    select 1
    from public.tasks t
    join public.organization_memberships m
      on m.organization_id = t.organization_id
     and m.user_id = (select auth.uid())
     and m.is_active
    where t.id = task_attachments.task_id
      and (t.assigned_to = (select auth.uid()) or t.created_by = (select auth.uid()))
  )
);

drop policy if exists task_attachments_read_assigned_or_manager on public.task_attachments;
create policy task_attachments_read_assigned_or_manager
on public.task_attachments
for select
to authenticated
using (
  exists (
    select 1
    from public.tasks t
    join public.organization_memberships m
      on m.organization_id = t.organization_id
     and m.user_id = (select auth.uid())
     and m.is_active
    where t.id = task_attachments.task_id
      and (
        t.assigned_to = (select auth.uid())
        or t.created_by = (select auth.uid())
        or exists (
          select 1
          from public.role_assignments ra
          where ra.organization_id = m.organization_id
            and ra.membership_id = m.id
            and ra.role_code in ('owner', 'admin_followup')
        )
      )
  )
);

drop policy if exists task_execution_steps_read on public.task_execution_steps;
create policy task_execution_steps_read
on public.task_execution_steps
for select
to authenticated
using (
  exists (
    select 1
    from public.tasks t
    where t.id = task_execution_steps.task_id
      and (
        (
          (t.assigned_to = (select auth.uid()) or t.created_by = (select auth.uid()))
          and exists (
            select 1
            from public.organization_memberships m
            where m.organization_id = t.organization_id
              and m.user_id = (select auth.uid())
              and m.is_active
          )
        )
        or alshaari_private.has_permission(t.organization_id, 'tasks.manage', null::uuid)
        or alshaari_private.has_permission(t.organization_id, 'tasks.review', null::uuid)
      )
  )
);

drop policy if exists task_report_drafts_insert on public.task_report_drafts;
create policy task_report_drafts_insert
on public.task_report_drafts
for insert
to authenticated
with check (
  employee_id = (select auth.uid())
  and exists (
    select 1
    from public.tasks t
    join public.organization_memberships m
      on m.organization_id = t.organization_id
     and m.user_id = (select auth.uid())
     and m.is_active
    where t.id = task_report_drafts.task_id
      and t.assigned_to = (select auth.uid())
      and t.report_flow = 'multi_form'
  )
);

drop policy if exists task_report_drafts_select on public.task_report_drafts;
create policy task_report_drafts_select
on public.task_report_drafts
for select
to authenticated
using (
  (
    employee_id = (select auth.uid())
    and exists (
      select 1
      from public.tasks t
      join public.organization_memberships m
        on m.organization_id = t.organization_id
       and m.user_id = (select auth.uid())
       and m.is_active
      where t.id = task_report_drafts.task_id
    )
  )
  or exists (
    select 1
    from public.tasks t
    where t.id = task_report_drafts.task_id
      and alshaari_private.has_permission(t.organization_id, 'tasks.review', null::uuid)
  )
);

drop policy if exists task_report_drafts_update on public.task_report_drafts;
create policy task_report_drafts_update
on public.task_report_drafts
for update
to authenticated
using (
  employee_id = (select auth.uid())
  and exists (
    select 1
    from public.tasks t
    join public.organization_memberships m
      on m.organization_id = t.organization_id
     and m.user_id = (select auth.uid())
     and m.is_active
    where t.id = task_report_drafts.task_id
  )
)
with check (
  employee_id = (select auth.uid())
  and exists (
    select 1
    from public.tasks t
    join public.organization_memberships m
      on m.organization_id = t.organization_id
     and m.user_id = (select auth.uid())
     and m.is_active
    where t.id = task_report_drafts.task_id
  )
);

commit;
