begin;

-- Production already has public.task_attachments and public.task_activity_log.
-- This migration only adds the missing storage bucket, RLS policies, and a
-- production-compatible timeline RPC; it does not recreate either table.

insert into storage.buckets (id, name, public, file_size_limit)
values ('task-attachments', 'task-attachments', false, 20971520)
on conflict (id) do update set public = false, file_size_limit = 20971520;

alter table public.task_attachments enable row level security;
drop policy if exists task_attachments_read_assigned_or_manager on public.task_attachments;
create policy task_attachments_read_assigned_or_manager
on public.task_attachments for select to authenticated
using (
  exists (
    select 1 from public.tasks t
    where t.id = task_attachments.task_id
      and (
        t.assigned_to = auth.uid()
        or t.created_by = auth.uid()
        or exists (
          select 1
          from public.organization_memberships m
          join public.role_assignments ra
            on ra.organization_id = m.organization_id
           and ra.membership_id = m.id
          where m.user_id = auth.uid()
            and m.is_active
            and ra.role_code in ('owner', 'admin_followup')
        )
      )
  )
);

drop policy if exists task_attachments_insert_uploader_on_visible_task on public.task_attachments;
create policy task_attachments_insert_uploader_on_visible_task
on public.task_attachments for insert to authenticated
with check (
  uploaded_by = auth.uid()
  and exists (
    select 1 from public.tasks t
    where t.id = task_attachments.task_id
      and (t.assigned_to = auth.uid() or t.created_by = auth.uid())
  )
);

drop policy if exists task_reports_storage_read_visible_task on storage.objects;
create policy task_reports_storage_read_visible_task
on storage.objects for select to authenticated
using (
  bucket_id = 'task-attachments'
  and exists (
    select 1 from public.task_attachments a
    join public.tasks t on t.id = a.task_id
    where a.storage_path = name
      and (t.assigned_to = auth.uid() or t.created_by = auth.uid()
        or exists (
          select 1 from public.organization_memberships m
          join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
          where m.user_id = auth.uid() and m.is_active and ra.role_code in ('owner', 'admin_followup')
        ))
  )
);

drop policy if exists task_reports_storage_insert_uploader on storage.objects;
create policy task_reports_storage_insert_uploader
on storage.objects for insert to authenticated
with check (
  bucket_id = 'task-attachments'
  and exists (
    select 1 from public.tasks t
    where split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and split_part(name, '/', 1)::uuid = t.id
      and t.assigned_to = auth.uid()
  )
);

create or replace function public.mobile_task_timeline(p_task_id uuid)
returns table (
  event_id uuid,
  task_id uuid,
  action_type text,
  actor_id uuid,
  actor_name text,
  previous_status text,
  new_status text,
  notes text,
  created_at timestamptz
)
language plpgsql stable security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'not_authenticated';
  end if;
  return query
  select l.id,
         l.task_id,
         l.action,
         l.actor_id,
         coalesce(u.raw_user_meta_data->>'full_name', u.email, 'النظام'),
         nullif(l.details->>'previous_status', ''),
         coalesce(nullif(l.details->>'new_status', ''), nullif(l.details->>'status', '')),
         coalesce(nullif(l.details->>'notes', ''), nullif(l.details->>'note', ''), l.action),
         l.created_at
  from public.task_activity_log l
  left join auth.users u on u.id = l.actor_id
  where l.task_id = p_task_id
    and exists (
      select 1 from public.tasks t
      where t.id = l.task_id
        and (t.assigned_to = auth.uid() or t.created_by = auth.uid()
          or exists (
            select 1 from public.organization_memberships m
            join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
            where m.user_id = auth.uid() and m.is_active and ra.role_code in ('owner', 'admin_followup')
          ))
    )
  order by l.created_at asc;
end;
$$;

revoke all on function public.mobile_task_timeline(uuid) from public, anon, authenticated;
grant execute on function public.mobile_task_timeline(uuid) to authenticated;

commit;
