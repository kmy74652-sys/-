begin;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  updated_count integer;
begin
  update public.notifications
     set read_at = coalesce(read_at, now())
   where id = p_notification_id
     and recipient_user_id = auth.uid();

  get diagnostics updated_count = row_count;
  return updated_count = 1;
end;
$$;

revoke all on function public.mark_notification_read(uuid) from public;
grant execute on function public.mark_notification_read(uuid) to authenticated;

commit;
