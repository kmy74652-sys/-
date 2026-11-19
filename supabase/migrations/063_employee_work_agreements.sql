-- Employee work agreements are versioned, tenant-scoped, and immutable after publication.
create table if not exists public.employee_agreements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid not null references public.organization_memberships(id) on delete restrict,
  agreement_no text not null,
  agreement_type text not null default 'employment',
  title text not null,
  status text not null default 'draft' check (status in ('draft','pending_approval','published','accepted','rejected','superseded','expired','revoked')),
  effective_from date not null default current_date,
  effective_to date,
  current_version_no integer not null default 1 check (current_version_no > 0),
  current_version_id uuid,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  published_by uuid references auth.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, agreement_no),
  check (length(trim(agreement_no)) between 2 and 80),
  check (length(trim(title)) between 2 and 180),
  check (effective_to is null or effective_to >= effective_from)
);

create table if not exists public.employee_agreement_versions (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.employee_agreements(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  version_no integer not null check (version_no > 0),
  title text not null,
  terms jsonb not null default '{}'::jsonb check (jsonb_typeof(terms) = 'object'),
  content_hash text not null,
  status text not null default 'draft' check (status in ('draft','published','superseded')),
  created_by uuid not null references auth.users(id),
  published_by uuid references auth.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique (agreement_id, version_no),
  unique (agreement_id, content_hash),
  check (length(trim(title)) between 2 and 180)
);

alter table public.employee_agreements
  drop constraint if exists employee_agreements_current_version_fk;
alter table public.employee_agreements
  add constraint employee_agreements_current_version_fk
  foreign key (current_version_id) references public.employee_agreement_versions(id) on delete restrict;

create table if not exists public.employee_agreement_responses (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.employee_agreements(id) on delete cascade,
  version_id uuid not null references public.employee_agreement_versions(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid not null references public.organization_memberships(id) on delete restrict,
  response text not null check (response in ('accepted','rejected')),
  note text,
  responded_by uuid not null references auth.users(id),
  responded_at timestamptz not null default now(),
  unique (version_id, membership_id),
  check (note is null or length(note) <= 2000)
);

create table if not exists public.employee_agreement_audit_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agreement_id uuid not null references public.employee_agreements(id) on delete cascade,
  version_id uuid references public.employee_agreement_versions(id) on delete set null,
  membership_id uuid not null references public.organization_memberships(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id),
  action text not null check (action in ('created','submitted_for_approval','published','accepted','rejected','superseded','revoked')),
  from_status text,
  to_status text,
  content_hash text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists employee_agreements_member_idx on public.employee_agreements (organization_id, membership_id, status);
create index if not exists employee_agreement_versions_agreement_idx on public.employee_agreement_versions (agreement_id, version_no desc);
create index if not exists employee_agreement_audit_org_idx on public.employee_agreement_audit_log (organization_id, created_at desc);

do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='domain') then
    execute $q$insert into public.permissions(code,name_ar,domain,action,description) values
      ('employee_agreements.manage','إدارة اتفاقيات العمل','employee_agreements','manage','إنشاء وإرسال مسودات اتفاقيات العمل'),
      ('employee_agreements.publish','نشر اتفاقيات العمل','employee_agreements','publish','اعتماد ونشر الاتفاقيات'),
      ('employee_agreements.read_all','قراءة اتفاقيات المؤسسة','employee_agreements','read_all','قراءة اتفاقيات المؤسسة') on conflict(code) do nothing$q$;
  else
    execute $q$insert into public.permissions(code,name_ar) values
      ('employee_agreements.manage','إدارة اتفاقيات العمل'),
      ('employee_agreements.publish','نشر اتفاقيات العمل'),
      ('employee_agreements.read_all','قراءة اتفاقيات المؤسسة') on conflict(code) do nothing$q$;
  end if;
end $$;
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='role_permissions' and column_name='role_code') then
    insert into public.role_permissions(role_code, permission_code)
    select r.code, p.code from public.roles r cross join public.permissions p where r.code='owner' and p.code in ('employee_agreements.manage','employee_agreements.publish','employee_agreements.read_all') on conflict do nothing;
    insert into public.role_permissions(role_code, permission_code)
    select r.code, p.code from public.roles r cross join public.permissions p where r.code='admin_followup' and p.code in ('employee_agreements.manage','employee_agreements.read_all') on conflict do nothing;
  else
    insert into public.role_permissions(institution_id, role_id, permission_code)
    select r.institution_id, r.id, p.code from public.roles r cross join public.permissions p where r.code='owner' and p.code in ('employee_agreements.manage','employee_agreements.publish','employee_agreements.read_all') on conflict do nothing;
    insert into public.role_permissions(institution_id, role_id, permission_code)
    select r.institution_id, r.id, p.code from public.roles r cross join public.permissions p where r.code='admin_followup' and p.code in ('employee_agreements.manage','employee_agreements.read_all') on conflict do nothing;
  end if;
end $$;

create or replace function public.employee_agreement_can(p_org uuid, p_permission text, p_branch_id uuid default null)
returns boolean language plpgsql stable security definer set search_path=public,auth,alshaari_private
as $$
declare v_allowed boolean;
begin
  if to_regprocedure('alshaari_private.has_permission(uuid,text,uuid)') is not null then
    execute 'select alshaari_private.has_permission($1,$2,$3)' into v_allowed using p_org,p_permission,p_branch_id;
  else
    execute 'select public.has_org_permission($1,$2,$3)' into v_allowed using p_org,p_permission,p_branch_id;
  end if;
  return coalesce(v_allowed,false);
end;
$$;

alter table public.employee_agreements enable row level security;
alter table public.employee_agreement_versions enable row level security;
alter table public.employee_agreement_responses enable row level security;
alter table public.employee_agreement_audit_log enable row level security;

revoke all on public.employee_agreements, public.employee_agreement_versions, public.employee_agreement_responses, public.employee_agreement_audit_log from public, anon;
grant select on public.employee_agreements, public.employee_agreement_versions, public.employee_agreement_responses to authenticated;
revoke insert, update, delete on public.employee_agreements, public.employee_agreement_versions, public.employee_agreement_responses, public.employee_agreement_audit_log from authenticated;
revoke all on public.employee_agreement_audit_log from authenticated;

drop policy if exists employee_agreements_select_scoped on public.employee_agreements;
create policy employee_agreements_select_scoped on public.employee_agreements for select to authenticated using (
  public.employee_agreement_can(organization_id, 'employee_agreements.read_all', null::uuid)
  or (exists (select 1 from public.organization_memberships m where m.id = membership_id and m.organization_id = employee_agreements.organization_id and m.user_id = auth.uid() and m.is_active)
      and status <> 'draft' and status <> 'pending_approval')
);
drop policy if exists employee_agreement_versions_select_scoped on public.employee_agreement_versions;
create policy employee_agreement_versions_select_scoped on public.employee_agreement_versions for select to authenticated using (
  exists (select 1 from public.employee_agreements a where a.id = agreement_id and (
    public.employee_agreement_can(a.organization_id, 'employee_agreements.read_all', null::uuid)
    or (exists (select 1 from public.organization_memberships m where m.id = a.membership_id and m.organization_id = a.organization_id and m.user_id = auth.uid() and m.is_active)
        and employee_agreement_versions.status = 'published')
  ))
);
drop policy if exists employee_agreement_responses_select_scoped on public.employee_agreement_responses;
create policy employee_agreement_responses_select_scoped on public.employee_agreement_responses for select to authenticated using (
  public.employee_agreement_can(organization_id, 'employee_agreements.read_all', null::uuid)
  or (membership_id in (select m.id from public.organization_memberships m where m.organization_id = employee_agreement_responses.organization_id and m.user_id = auth.uid() and m.is_active))
);

create or replace function public.employee_agreement_audit_guard()
returns trigger language plpgsql as $$
begin raise exception using errcode='42501', message='employee_agreement_audit_append_only'; end;
$$;
drop trigger if exists employee_agreement_audit_no_mutation on public.employee_agreement_audit_log;
create trigger employee_agreement_audit_no_mutation before update or delete on public.employee_agreement_audit_log for each row execute function public.employee_agreement_audit_guard();

create or replace function public.create_employee_agreement(
  p_organization_id uuid, p_membership_id uuid, p_agreement_no text, p_title text,
  p_terms jsonb, p_effective_from date default current_date, p_effective_to date default null
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid := auth.uid(); v_agreement uuid; v_version uuid; v_hash text; v_name text;
begin
  if v_user is null or not public.employee_agreement_can(p_organization_id,'employee_agreements.manage',null::uuid) then raise exception using errcode='42501', message='agreement_manage_denied'; end if;
  if p_terms is null or jsonb_typeof(p_terms) <> 'object' then raise exception using errcode='22023', message='agreement_terms_must_be_object'; end if;
  select m.display_name into v_name from public.organization_memberships m where m.id=p_membership_id and m.organization_id=p_organization_id and m.is_active;
  if not found then raise exception using errcode='22023', message='agreement_employee_not_active'; end if;
  v_hash := md5(coalesce(trim(p_title),'') || '|' || p_terms::text || '|' || coalesce(p_effective_from::text,'') || '|' || coalesce(p_effective_to::text,''));
  insert into public.employee_agreements(organization_id,membership_id,agreement_no,title,effective_from,effective_to,created_by,updated_by)
  values(p_organization_id,p_membership_id,trim(p_agreement_no),trim(p_title),coalesce(p_effective_from,current_date),p_effective_to,v_user,v_user) returning id into v_agreement;
  insert into public.employee_agreement_versions(agreement_id,organization_id,version_no,title,terms,content_hash,created_by)
  values(v_agreement,p_organization_id,1,trim(p_title),p_terms,v_hash,v_user) returning id into v_version;
  update public.employee_agreements set current_version_id=v_version where id=v_agreement;
  insert into public.employee_agreement_audit_log(organization_id,agreement_id,version_id,membership_id,actor_user_id,action,from_status,to_status,content_hash,metadata)
  values(p_organization_id,v_agreement,v_version,p_membership_id,v_user,'created',null,'draft',v_hash,jsonb_build_object('employee_name',v_name));
  return jsonb_build_object('agreement_id',v_agreement,'version_id',v_version,'status','draft');
end; $$;

create or replace function public.submit_employee_agreement_for_approval(p_agreement_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid:=auth.uid(); v_a public.employee_agreements%rowtype; begin
  select * into v_a from public.employee_agreements where id=p_agreement_id for update;
  if not found or not public.employee_agreement_can(v_a.organization_id,'employee_agreements.manage',null::uuid) then raise exception using errcode='42501',message='agreement_manage_denied'; end if;
  if v_a.status <> 'draft' then raise exception using errcode='22023',message='agreement_must_be_draft'; end if;
  update public.employee_agreements set status='pending_approval',updated_by=v_user,updated_at=now() where id=p_agreement_id;
  insert into public.employee_agreement_audit_log(organization_id,agreement_id,version_id,membership_id,actor_user_id,action,from_status,to_status,content_hash) select v_a.organization_id,v_a.id,v_a.current_version_id,v_a.membership_id,v_user,'submitted_for_approval',v_a.status,'pending_approval',v.content_hash from public.employee_agreement_versions v where v.id=v_a.current_version_id;
  return jsonb_build_object('agreement_id',p_agreement_id,'status','pending_approval');
end; $$;

create or replace function public.publish_employee_agreement(p_agreement_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid:=auth.uid(); v_a public.employee_agreements%rowtype; v_v public.employee_agreement_versions%rowtype;
begin
  select * into v_a from public.employee_agreements where id=p_agreement_id for update;
  if not found or not public.employee_agreement_can(v_a.organization_id,'employee_agreements.publish',null::uuid) then raise exception using errcode='42501',message='agreement_publish_denied'; end if;
  if v_a.status <> 'pending_approval' then raise exception using errcode='22023',message='agreement_must_be_pending_approval'; end if;
  select * into v_v from public.employee_agreement_versions where id=v_a.current_version_id and agreement_id=v_a.id for update;
  if not found then raise exception using errcode='22023',message='agreement_version_missing'; end if;
  update public.employee_agreement_versions set status='superseded' where agreement_id=v_a.id and status='published';
  update public.employee_agreement_versions set status='published',published_by=v_user,published_at=now() where id=v_v.id;
  update public.employee_agreements set status='published',published_by=v_user,published_at=now(),updated_by=v_user,updated_at=now() where id=v_a.id;
  insert into public.employee_agreement_audit_log(organization_id,agreement_id,version_id,membership_id,actor_user_id,action,from_status,to_status,content_hash) values(v_a.organization_id,v_a.id,v_v.id,v_a.membership_id,v_user,'published',v_a.status,'published',v_v.content_hash);
  return jsonb_build_object('agreement_id',v_a.id,'version_id',v_v.id,'status','published');
end; $$;

create or replace function public.respond_employee_agreement(p_version_id uuid, p_response text, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid:=auth.uid(); v_v public.employee_agreement_versions%rowtype; v_a public.employee_agreements%rowtype; v_m public.organization_memberships%rowtype; v_response text;
begin
  if v_user is null or p_response not in ('accepted','rejected') then raise exception using errcode='22023',message='invalid_agreement_response'; end if;
  select * into v_v from public.employee_agreement_versions where id=p_version_id and status='published';
  select * into v_a from public.employee_agreements where id=v_v.agreement_id;
  select * into v_m from public.organization_memberships where id=v_a.membership_id and user_id=v_user and is_active;
  if not found then raise exception using errcode='42501',message='agreement_response_denied'; end if;
  insert into public.employee_agreement_responses(agreement_id,version_id,organization_id,membership_id,response,note,responded_by)
  values(v_a.id,v_v.id,v_a.organization_id,v_m.id,p_response,nullif(trim(p_note),''),v_user)
  on conflict (version_id,membership_id) do update set response=excluded.response,note=excluded.note,responded_by=excluded.responded_by,responded_at=now();
  v_response := case when p_response='accepted' then 'accepted' else 'rejected' end;
  update public.employee_agreements set status=v_response,updated_by=v_user,updated_at=now() where id=v_a.id and status='published';
  insert into public.employee_agreement_audit_log(organization_id,agreement_id,version_id,membership_id,actor_user_id,action,from_status,to_status,content_hash,metadata)
  values(v_a.organization_id,v_a.id,v_v.id,v_m.id,v_user,case when p_response='accepted' then 'accepted' else 'rejected' end,v_a.status,v_response,v_v.content_hash,jsonb_build_object('note',p_note));
  return jsonb_build_object('agreement_id',v_a.id,'version_id',v_v.id,'status',v_response);
end; $$;

revoke all on function public.create_employee_agreement(uuid,uuid,text,text,jsonb,date,date) from public,anon,authenticated;
revoke all on function public.submit_employee_agreement_for_approval(uuid) from public,anon,authenticated;
revoke all on function public.publish_employee_agreement(uuid) from public,anon,authenticated;
revoke all on function public.respond_employee_agreement(uuid,text,text) from public,anon,authenticated;
grant execute on function public.create_employee_agreement(uuid,uuid,text,text,jsonb,date,date) to authenticated;
grant execute on function public.submit_employee_agreement_for_approval(uuid) to authenticated;
grant execute on function public.publish_employee_agreement(uuid) to authenticated;
grant execute on function public.respond_employee_agreement(uuid,text,text) to authenticated;
