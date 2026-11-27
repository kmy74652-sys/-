begin;

create or replace function public.save_organization_branding(
  p_organization_id uuid,
  p_name text,
  p_tagline text,
  p_logo_url text default null,
  p_english_name text default null,
  p_phone text default null,
  p_address text default null
) returns boolean
language plpgsql
security definer
set search_path = public, auth, alshaari_private
as $$
declare
  v_settings jsonb;
  v_name text := trim(coalesce(p_name, ''));
  v_tagline text := trim(coalesce(p_tagline, ''));
  v_english_name text := trim(coalesce(p_english_name, ''));
  v_phone text := trim(coalesce(p_phone, ''));
  v_address text := trim(coalesce(p_address, ''));
begin
  if auth.uid() is null
     or not alshaari_private.has_permission(p_organization_id, 'organizations.update', null::uuid) then
    raise exception using errcode = '42501', message = 'organization_branding_permission_denied';
  end if;
  if length(v_name) < 2 or length(v_name) > 90 then
    raise exception using errcode = '22023', message = 'organization_name_invalid';
  end if;
  if length(v_tagline) > 100 or length(v_english_name) > 160
     or length(v_phone) > 60 or length(v_address) > 240 then
    raise exception using errcode = '22023', message = 'organization_branding_field_invalid';
  end if;
  select coalesce(settings, '{}'::jsonb) into v_settings
  from public.organizations
  where id = p_organization_id and is_active
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'organization_not_found';
  end if;
  update public.organizations
  set name = v_name,
      settings = jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set(
                jsonb_set(v_settings, '{branding,tagline}', to_jsonb(v_tagline), true),
                '{branding,logo_url}',
                case when p_logo_url is null then 'null'::jsonb else to_jsonb(p_logo_url) end,
                true
              ),
              '{branding,english_name}', to_jsonb(v_english_name), true
            ),
            '{branding,phone}', to_jsonb(v_phone), true
          ),
          '{branding,address}', to_jsonb(v_address), true
        ),
        '{branding,version}', to_jsonb(2), true
      )
  where id = p_organization_id;
  return true;
end;
$$;

revoke all on function public.save_organization_branding(uuid, text, text, text, text, text, text) from public, anon;
grant execute on function public.save_organization_branding(uuid, text, text, text, text, text, text) to authenticated;

commit;
