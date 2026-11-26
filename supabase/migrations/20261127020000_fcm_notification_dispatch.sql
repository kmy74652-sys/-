begin;

-- The FCM Edge Function is protected by FCM_WEBHOOK_SECRET. The secret is
-- read from Supabase Vault and never stored in this migration or sent to the
-- client application.
create extension if not exists pg_net;

create or replace function public.dispatch_notification_fcm()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, net
as $$
declare
  v_secret text;
  v_request_id bigint;
begin
  select decrypted_secret
    into v_secret
    from vault.decrypted_secrets
   where name = 'fcm_webhook_secret'
     and decrypted_secret is not null
   limit 1;

  if v_secret is null or length(trim(v_secret)) = 0 then
    raise notice 'FCM dispatch skipped: fcm_webhook_secret is not configured';
    return new;
  end if;

  select net.http_post(
    url := 'https://fjmryqhdwxsocdzswnkq.supabase.co/functions/v1/send-fcm-notification',
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_secret
    )
  ) into v_request_id;

  return new;
exception when others then
  -- The in-app notification is already the source of truth. A temporary FCM
  -- outage must not roll back the business transaction that created it.
  raise notice 'FCM dispatch skipped: %', sqlerrm;
  return new;
end;
$$;

revoke all on function public.dispatch_notification_fcm() from public, anon, authenticated;

drop trigger if exists notifications_dispatch_fcm on public.notifications;
create trigger notifications_dispatch_fcm
after insert on public.notifications
for each row execute function public.dispatch_notification_fcm();

commit;
