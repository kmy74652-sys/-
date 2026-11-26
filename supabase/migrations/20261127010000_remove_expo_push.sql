begin;

-- NEXORA is now Flutter-only. Flutter receives notification inserts through
-- Supabase Realtime and renders native local notifications. This migration
-- removes the Expo Push delivery path without deleting in-app notifications.

drop trigger if exists notifications_dispatch_push on public.notifications;
drop function if exists public.dispatch_notification_push();

-- Keep registered-device records available for the native provider migration,
-- but remove the Expo-specific column name and RPC contract.
alter table public.notification_devices
  rename column expo_push_token to native_push_token;

alter table public.notification_devices
  drop constraint if exists notification_devices_user_id_expo_push_token_key;

alter table public.notification_devices
  add constraint notification_devices_user_id_native_push_token_key
  unique (user_id, native_push_token);

drop function if exists public.register_push_device(text, text, text);

create or replace function public.register_native_device(
  p_native_push_token text,
  p_platform text,
  p_device_name text default null
) returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_org uuid;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode='28000', message='not_authenticated';
  end if;
  if p_platform not in ('android','ios') then
    raise exception using errcode='22023', message='invalid_native_platform';
  end if;
  if p_native_push_token is null
     or length(trim(p_native_push_token)) < 10
     or length(trim(p_native_push_token)) > 2048 then
    raise exception using errcode='22023', message='invalid_native_push_token';
  end if;

  select organization_id into v_org
    from public.organization_memberships
   where user_id = auth.uid() and is_active
   order by created_at
   limit 1;

  if v_org is null then
    raise exception using errcode='42501', message='employee_not_active';
  end if;

  insert into public.notification_devices(
    organization_id, user_id, native_push_token, platform, device_name,
    is_enabled, last_seen_at, updated_at
  )
  values(
    v_org, auth.uid(), trim(p_native_push_token), p_platform,
    nullif(trim(coalesce(p_device_name,'')), ''), true, now(), now()
  )
  on conflict(user_id, native_push_token) do update set
    organization_id = excluded.organization_id,
    platform = excluded.platform,
    device_name = excluded.device_name,
    is_enabled = true,
    last_seen_at = now(),
    updated_at = now()
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'enabled', true);
end;
$$;

revoke all on function public.register_native_device(text, text, text) from public, anon;
grant execute on function public.register_native_device(text, text, text) to authenticated;

-- Flutter disables all native registrations on sign-out. The current Flutter
-- client uses Realtime for delivery and does not register a remote token yet.
create or replace function public.disable_push_device()
returns jsonb language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception using errcode='28000', message='not_authenticated';
  end if;
  update public.notification_devices
     set is_enabled = false, updated_at = now()
   where user_id = auth.uid();
  return jsonb_build_object('disabled', true);
end;
$$;

revoke all on function public.disable_push_device() from public, anon;
grant execute on function public.disable_push_device() to authenticated;

commit;
