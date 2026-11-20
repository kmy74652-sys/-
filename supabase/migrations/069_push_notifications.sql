begin;

-- pg_net is used asynchronously so a temporary Expo outage never blocks the
-- business transaction that creates the in-app notification.
create extension if not exists pg_net;

create table if not exists public.notification_devices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expo_push_token text not null check (length(trim(expo_push_token)) between 10 and 512),
  platform text not null check (platform in ('android', 'ios', 'web')),
  device_name text,
  is_enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, expo_push_token)
);
create index if not exists notification_devices_recipient_idx
  on public.notification_devices (organization_id, user_id, is_enabled);
alter table public.notification_devices enable row level security;
revoke all on public.notification_devices from anon, authenticated;

drop policy if exists notification_devices_select_own on public.notification_devices;
create policy notification_devices_select_own on public.notification_devices
  for select to authenticated using (user_id = auth.uid());

create or replace function public.register_push_device(
  p_expo_push_token text,
  p_platform text,
  p_device_name text default null
) returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_org uuid;
  v_id uuid;
begin
  if auth.uid() is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  if p_platform not in ('android','ios','web') then raise exception using errcode='22023', message='invalid_push_platform'; end if;
  if p_expo_push_token is null or length(trim(p_expo_push_token)) < 10 or length(trim(p_expo_push_token)) > 512 then
    raise exception using errcode='22023', message='invalid_push_token';
  end if;
  select organization_id into v_org
    from public.organization_memberships
   where user_id = auth.uid() and is_active
   order by created_at
   limit 1;
  if v_org is null then raise exception using errcode='42501', message='employee_not_active'; end if;
  insert into public.notification_devices(organization_id,user_id,expo_push_token,platform,device_name,is_enabled,last_seen_at,updated_at)
  values(v_org,auth.uid(),trim(p_expo_push_token),p_platform,nullif(trim(coalesce(p_device_name,'')),''),true,now(),now())
  on conflict(user_id,expo_push_token) do update set
    organization_id=excluded.organization_id, platform=excluded.platform, device_name=excluded.device_name,
    is_enabled=true, last_seen_at=now(), updated_at=now()
  returning id into v_id;
  return jsonb_build_object('id',v_id,'enabled',true);
end;
$$;
revoke all on function public.register_push_device(text,text,text) from public, anon;
grant execute on function public.register_push_device(text,text,text) to authenticated;

create or replace function public.disable_push_device()
returns jsonb language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  update public.notification_devices set is_enabled=false, updated_at=now() where user_id=auth.uid();
  return jsonb_build_object('disabled',true);
end;
$$;
revoke all on function public.disable_push_device() from public, anon;
grant execute on function public.disable_push_device() to authenticated;

create or replace function public.dispatch_notification_push()
returns trigger language plpgsql security definer set search_path = public, extensions, net as $$
declare
  v_device record;
  v_payload jsonb;
begin
  for v_device in
    select expo_push_token from public.notification_devices
     where organization_id = new.organization_id
       and user_id = new.recipient_user_id
       and is_enabled = true
  loop
    v_payload := jsonb_build_object(
      'to', v_device.expo_push_token,
      'title', new.title,
      'body', new.body,
      'sound', 'default',
      'priority', 'high',
      'data', jsonb_build_object('notificationId', new.id, 'taskId', new.task_id, 'route', '/tasks')
    );
    begin
      perform net.http_post(
        url := 'https://exp.host/--/api/v2/push/send',
        body := v_payload,
        headers := jsonb_build_object('Content-Type','application/json')
      );
    exception when others then
      -- The in-app notification has already been created; push delivery is best effort.
      raise notice 'push dispatch skipped: %', sqlerrm;
    end;
  end loop;
  return new;
end;
$$;
drop trigger if exists notifications_dispatch_push on public.notifications;
create trigger notifications_dispatch_push
after insert on public.notifications
for each row execute function public.dispatch_notification_push();

commit;
