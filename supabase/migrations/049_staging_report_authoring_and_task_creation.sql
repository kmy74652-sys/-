begin;

create or replace function public.save_report_form_draft(
  p_organization_id uuid,
  p_template_id uuid,
  p_title text,
  p_description text,
  p_role_code text,
  p_fields jsonb,
  p_report_required boolean
) returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_template public.report_form_templates%rowtype;
  v_template_id uuid;
  v_version_id uuid;
  v_version_no integer;
  v_field jsonb;
  v_column jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_options jsonb;
  v_validation jsonb;
  v_config jsonb;
  v_default jsonb;
  v_min numeric;
  v_max numeric;
  v_formula text;
  v_match text[];
  v_source jsonb;
  v_column_key text;
  v_column_type text;
  v_column_keys text[];
  v_refs text[];
  v_ref text;
  v_sample jsonb;
  v_ord bigint;
begin
  if v_user is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  if not public.report_designer_allowed_for_org(p_organization_id) then raise exception using errcode='42501', message='permission_denied'; end if;
  if p_title is null or length(trim(p_title))<2 or length(trim(p_title))>160 then raise exception using errcode='22023', message='designer_title_invalid'; end if;
  if p_role_code not in ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker') then raise exception using errcode='22023', message='invalid_report_template_role'; end if;
  if not exists (select 1 from public.roles r where r.institution_id=p_organization_id and r.code=p_role_code) then raise exception using errcode='22023', message='invalid_report_template_role'; end if;
  if p_fields is null or jsonb_typeof(p_fields)<>'array' or jsonb_array_length(p_fields)<1 or jsonb_array_length(p_fields)>100 then raise exception using errcode='22023', message='invalid_report_form_fields'; end if;
  if exists (select 1 from jsonb_array_elements(p_fields) x(value) group by x.value->>'field_key' having count(*)>1) then raise exception using errcode='22023', message='duplicate_report_field_key'; end if;

  -- Validate all field metadata before writing a template or version. In particular, never send blank labels to the CHECK constraint.
  for v_field, v_ord in select x.value, x.ordinality from jsonb_array_elements(p_fields) with ordinality x(value,ordinality) loop
    v_field_key := trim(coalesce(v_field->>'field_key','')); v_label := trim(coalesce(v_field->>'label','')); v_type := coalesce(v_field->>'field_type','');
    v_options := coalesce(v_field->'options','[]'::jsonb); v_validation := coalesce(v_field->'validation','{}'::jsonb); v_config := coalesce(v_field->'config','{}'::jsonb);
    if v_field_key !~ '^[a-z][a-z0-9_]{0,63}$' then raise exception using errcode='22023', message='invalid_report_field_key:' || coalesce(v_field->>'field_key',''); end if;
    if length(v_label)<1 or length(v_label)>200 then raise exception using errcode='22023', message='report_field_label_required:' || v_ord; end if;
    if v_type not in ('short_text','long_text','integer','quantity','money','datetime','select','multiselect','boolean','table','image','file','attachment','signature','calculated','decision_notes','text','number','progress','status','notes','textarea','date','checkbox') then raise exception using errcode='22023', message='invalid_report_field_type:' || v_label; end if;
    if jsonb_typeof(v_options)<>'array' or jsonb_typeof(v_validation)<>'object' or jsonb_typeof(v_config)<>'object' then raise exception using errcode='22023', message='invalid_report_field_configuration:' || v_label; end if;
    if jsonb_array_length(v_options)>100 then raise exception using errcode='22023', message='too_many_report_field_options:' || v_label; end if;
    if exists (select 1 from jsonb_array_elements(v_options) o(value) where jsonb_typeof(o.value)<>'string' or length(trim(o.value#>>'{}'))=0 or length(o.value#>>'{}')>200) then raise exception using errcode='22023', message='invalid_report_field_option:' || v_label; end if;
    if exists (select 1 from jsonb_array_elements_text(v_options) o(value) group by trim(o.value) having count(*)>1) then raise exception using errcode='22023', message='duplicate_report_field_option:' || v_label; end if;
    if v_type in ('select','multiselect') and jsonb_array_length(v_options)=0 then raise exception using errcode='22023', message='report_field_options_required:' || v_label; end if;
    if nullif(v_validation->>'min','') is not null then
      if (v_validation->>'min') !~ '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$' then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
      v_min := (v_validation->>'min')::numeric;
    else v_min := null; end if;
    if nullif(v_validation->>'max','') is not null then
      if (v_validation->>'max') !~ '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$' then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
      v_max := (v_validation->>'max')::numeric;
    else v_max := null; end if;
    if v_min is not null and v_max is not null and v_min>v_max then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
    if nullif(v_validation->>'min_length','') is not null and ((v_validation->>'min_length') !~ '^[0-9]+$' or length(v_validation->>'min_length')>5 or (v_validation->>'min_length')::integer>20000) then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
    if nullif(v_validation->>'max_length','') is not null and ((v_validation->>'max_length') !~ '^[0-9]+$' or length(v_validation->>'max_length')>5 or (v_validation->>'max_length')::integer<1 or (v_validation->>'max_length')::integer>20000) then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
    if nullif(v_validation->>'min_length','') is not null and nullif(v_validation->>'max_length','') is not null and (v_validation->>'min_length')::integer>(v_validation->>'max_length')::integer then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
    if nullif(v_validation->>'decimal_places','') is not null and ((v_validation->>'decimal_places') !~ '^[0-9]+$' or (v_validation->>'decimal_places')::integer>8) then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
    if v_validation ? 'allow_negative' and jsonb_typeof(v_validation->'allow_negative')<>'boolean' then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
    if v_validation ? 'allow_zero' and jsonb_typeof(v_validation->'allow_zero')<>'boolean' then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
    if v_type='select' and v_config ? 'default_value' and not (v_options ? (v_config->>'default_value')) then raise exception using errcode='22023', message='invalid_report_default_option:' || v_label; end if;
    if v_type='multiselect' and v_config ? 'default_value' then
      if jsonb_typeof(v_config->'default_value')<>'array' or exists (select 1 from jsonb_array_elements(v_config->'default_value') d(value) where jsonb_typeof(d.value)<>'string' or not (v_options ? (d.value#>>'{}'))) then raise exception using errcode='22023', message='invalid_report_default_option:' || v_label; end if;
      if exists (select 1 from jsonb_array_elements_text(v_config->'default_value') d(value) group by d.value having count(*)>1) then raise exception using errcode='22023', message='invalid_report_default_option:' || v_label; end if;
    end if;
    v_default := v_config->'default_value';
    if v_default is not null and v_default<>'null'::jsonb and not (jsonb_typeof(v_default)='string' and trim(v_default#>>'{}')='') then
      if v_type in ('short_text','long_text','decision_notes','text','textarea','notes','status','integer','quantity','money','number','progress') then
        perform public.report_validate_scalar(v_type,v_default,v_validation,v_label);
      elsif v_type in ('datetime','date') then
        if jsonb_typeof(v_default)<>'string' then raise exception using errcode='22023', message='invalid_report_default_value:' || v_label; end if;
        begin
          if v_type='date' then perform (v_default#>>'{}')::date; else perform (v_default#>>'{}')::timestamptz; end if;
        exception when others then raise exception using errcode='22023', message='invalid_report_default_value:' || v_label; end;
      elsif v_type in ('boolean','checkbox') and jsonb_typeof(v_default)<>'boolean' then
        raise exception using errcode='22023', message='invalid_report_default_value:' || v_label;
      end if;
    end if;
    if v_type='table' then
      if jsonb_typeof(coalesce(v_config->'columns','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(v_config->'columns','[]'::jsonb))<1 or jsonb_array_length(coalesce(v_config->'columns','[]'::jsonb))>20 then raise exception using errcode='22023', message='report_table_columns_required:' || v_label; end if;
      v_column_keys := array[]::text[];
      for v_column in select value from jsonb_array_elements(v_config->'columns') loop
        if jsonb_typeof(v_column)='string' then v_column_key := trim(v_column#>>'{}'); v_column_type := 'short_text';
        elsif jsonb_typeof(v_column)='object' then v_column_key := trim(coalesce(v_column->>'key',v_column->>'label',v_column->>'name','')); v_column_type := coalesce(v_column->>'type',v_column->>'field_type','short_text');
        else raise exception using errcode='22023', message='invalid_report_table_column:' || v_label; end if;
        if length(v_column_key)<1 or length(v_column_key)>128 or position('.' in v_column_key)>0 or position(')' in v_column_key)>0 then raise exception using errcode='22023', message='invalid_report_table_column:' || v_label; end if;
        if v_column_key=any(v_column_keys) then raise exception using errcode='22023', message='duplicate_report_table_column:' || v_label; end if;
        v_column_keys := array_append(v_column_keys,v_column_key);
        if v_column_type not in ('short_text','long_text','integer','quantity','money','select','boolean') then raise exception using errcode='22023', message='invalid_report_table_column_type:' || v_label; end if;
        if jsonb_typeof(v_column)='object' and (length(trim(coalesce(v_column->>'label','')))<1 or length(v_column->>'label')>200) then raise exception using errcode='22023', message='report_table_column_label_required:' || v_label; end if;
        if jsonb_typeof(v_column)='object' and jsonb_typeof(coalesce(v_column->'validation','{}'::jsonb))<>'object' then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
        if v_column_type='select' then
          if jsonb_typeof(coalesce(v_column->'options','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(v_column->'options','[]'::jsonb))=0 then raise exception using errcode='22023', message='report_table_column_options_required:' || v_label; end if;
          if jsonb_array_length(coalesce(v_column->'options','[]'::jsonb))>100 or exists (select 1 from jsonb_array_elements(coalesce(v_column->'options','[]'::jsonb)) o(value) where jsonb_typeof(o.value)<>'string' or length(trim(o.value#>>'{}'))=0 or length(o.value#>>'{}')>200) then raise exception using errcode='22023', message='invalid_report_table_column_options:' || v_label; end if;
          if exists (select 1 from jsonb_array_elements_text(coalesce(v_column->'options','[]'::jsonb)) o(value) group by trim(o.value) having count(*)>1) then raise exception using errcode='22023', message='invalid_report_table_column_options:' || v_label; end if;
        end if;
        if jsonb_typeof(v_column)='object' then
          if nullif(v_column->'validation'->>'min','') is not null and (v_column->'validation'->>'min') !~ '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$' then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
          if nullif(v_column->'validation'->>'max','') is not null and (v_column->'validation'->>'max') !~ '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$' then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
          if nullif(v_column->'validation'->>'min','') is not null and nullif(v_column->'validation'->>'max','') is not null and (v_column->'validation'->>'min')::numeric>(v_column->'validation'->>'max')::numeric then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
          if nullif(v_column->'validation'->>'decimal_places','') is not null and ((v_column->'validation'->>'decimal_places') !~ '^[0-9]+$' or (v_column->'validation'->>'decimal_places')::integer>8) then raise exception using errcode='22023', message='invalid_report_field_validation:' || v_label; end if;
        end if;
      end loop;
      if nullif(v_config->>'min_rows','') is not null and (v_config->>'min_rows') !~ '^[0-9]+$' then raise exception using errcode='22023', message='invalid_report_table_row_limits:' || v_label; end if;
      if nullif(v_config->>'max_rows','') is not null and (v_config->>'max_rows') !~ '^[0-9]+$' then raise exception using errcode='22023', message='invalid_report_table_row_limits:' || v_label; end if;
      if nullif(v_config->>'min_rows','') is not null and (v_config->>'min_rows')::integer>500 then raise exception using errcode='22023', message='invalid_report_table_row_limits:' || v_label; end if;
      if nullif(v_config->>'max_rows','') is not null and ((v_config->>'max_rows')::integer<1 or (v_config->>'max_rows')::integer>500) then raise exception using errcode='22023', message='invalid_report_table_row_limits:' || v_label; end if;
      if nullif(v_config->>'min_rows','') is not null and nullif(v_config->>'max_rows','') is not null and (v_config->>'min_rows')::integer>(v_config->>'max_rows')::integer then raise exception using errcode='22023', message='invalid_report_table_row_limits:' || v_label; end if;
    end if;
    if v_type='signature' and length(coalesce(v_config->>'consent_text',''))>2000 then raise exception using errcode='22023', message='report_signature_consent_too_long:' || v_label; end if;
    if v_type='calculated' then
      v_formula := trim(coalesce(v_config->>'formula',''));
      if length(v_formula)=0 or length(v_formula)>2048 then raise exception using errcode='22023', message='invalid_calculated_report_formula:' || v_label; end if;
      v_match := regexp_match(v_formula,'^sum_rows\(([^.]{1,64})\.([^)]{1,128})\)$');
      if v_match is not null then
        select x.value into v_source from jsonb_array_elements(p_fields) x(value) where x.value->>'field_key'=v_match[1];
        if v_source is null or v_source->>'field_type'<>'table' or not exists (
          select 1 from jsonb_array_elements(v_source->'config'->'columns') c(value)
          where case when jsonb_typeof(c.value)='string' then c.value#>>'{}' else coalesce(c.value->>'key',c.value->>'label',c.value->>'name') end=v_match[2]
            and (jsonb_typeof(c.value)='string' or coalesce(c.value->>'type',c.value->>'field_type','short_text') in ('integer','quantity','money'))
        ) then raise exception using errcode='22023', message='invalid_calculated_report_formula:' || v_label; end if;
      else
        v_sample := '{}'::jsonb;
        v_match := regexp_match(v_formula,'^sum\(([a-z][a-z0-9_]{0,63})\)$');
        if v_match is not null then v_refs := array[v_match[1]];
        else
          v_match := regexp_match(v_formula,'^difference\(([a-z][a-z0-9_]{0,63}),\s*([a-z][a-z0-9_]{0,63})\)$');
          if v_match is not null then v_refs := array[v_match[1],v_match[2]];
          else
            v_refs := array[]::text[];
            for v_ref in select (m)[1] from regexp_matches(v_formula,'\{([a-z][a-z0-9_]{0,63})\}','g') m loop v_refs := array_append(v_refs,v_ref); end loop;
          end if;
        end if;
        if coalesce(array_length(v_refs,1),0)=0 then raise exception using errcode='22023', message='invalid_calculated_report_formula:' || v_label; end if;
        foreach v_ref in array v_refs loop
          if v_ref=v_field_key or not exists (select 1 from jsonb_array_elements(p_fields) x(value) where x.value->>'field_key'=v_ref and x.value->>'field_type' in ('integer','quantity','money')) then raise exception using errcode='22023', message='invalid_calculated_report_reference:' || v_label || ':' || v_ref; end if;
          v_sample := v_sample || jsonb_build_object(v_ref,2);
        end loop;
        begin perform public.report_safe_formula_eval(v_formula,v_sample);
        exception when others then raise exception using errcode='22023', message='invalid_calculated_report_formula:' || v_label; end;
      end if;
    end if;
  end loop;

  if p_template_id is null then
    v_template_id := gen_random_uuid();
    insert into public.report_form_templates(id,organization_id,code,title,description,role_code,is_active,created_by,updated_by)
    values(v_template_id,p_organization_id,'form_' || replace(v_template_id::text,'-',''),trim(p_title),nullif(trim(coalesce(p_description,'')),''),p_role_code,true,v_user,v_user);
  else
    select * into v_template from public.report_form_templates where id=p_template_id and organization_id=p_organization_id and is_active for update;
    if not found then raise exception using errcode='P0002', message='report_form_template_not_found'; end if;
    if v_template.role_code<>p_role_code then raise exception using errcode='22023', message='report_template_role_immutable'; end if;
    v_template_id := v_template.id;
    update public.report_form_templates set title=trim(p_title), description=nullif(trim(coalesce(p_description,'')),''), updated_by=v_user, updated_at=now() where id=v_template_id;
  end if;
  select coalesce(max(version_no),0)+1 into v_version_no from public.report_form_versions where template_id=v_template_id;
  insert into public.report_form_versions(template_id,version_no,status,report_required,created_by)
  values(v_template_id,v_version_no,'draft',coalesce(p_report_required,true),v_user) returning id into v_version_id;
  for v_field, v_ord in select x.value, x.ordinality from jsonb_array_elements(p_fields) with ordinality x(value,ordinality) loop
    insert into public.report_form_version_fields(version_id,field_key,label,description,field_type,is_required,repeatable,sort_order,options,validation,config)
    values(v_version_id,trim(v_field->>'field_key'),trim(v_field->>'label'),nullif(trim(coalesce(v_field->>'description','')),''),v_field->>'field_type',coalesce((v_field->>'is_required')::boolean,false),coalesce((v_field->>'repeatable')::boolean,false),v_ord-1,coalesce(v_field->'options','[]'::jsonb),coalesce(v_field->'validation','{}'::jsonb),coalesce(v_field->'config','{}'::jsonb));
  end loop;
  return jsonb_build_object('template_id',v_template_id,'version_id',v_version_id,'version_no',v_version_no,'status','draft');
end $$;
revoke all on function public.save_report_form_draft(uuid,uuid,text,text,text,jsonb,boolean) from public, anon, authenticated;
grant execute on function public.save_report_form_draft(uuid,uuid,text,text,text,jsonb,boolean) to authenticated;

create or replace function public.approve_report_form_version(p_version_id uuid)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare v_user uuid := auth.uid(); v_org uuid; v_version uuid; v_status text;
begin
  if v_user is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  select t.organization_id,v.status into v_org,v_status
  from public.report_form_versions v join public.report_form_templates t on t.id=v.template_id where v.id=p_version_id for update of v;
  if not found then raise exception using errcode='P0002', message='report_form_version_not_found'; end if;
  if not exists (
    select 1 from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id=m.organization_id and ra.membership_id=m.id
    where m.user_id=v_user and m.organization_id=v_org and m.is_active and ra.role_code='owner'
  ) then raise exception using errcode='42501', message='owner_approval_required'; end if;
  if v_status<>'draft' then raise exception using errcode='22023', message='report_form_version_immutable'; end if;
  if not exists (select 1 from public.report_form_version_fields f where f.version_id=p_version_id) then raise exception using errcode='22023', message='report_form_fields_required'; end if;
  update public.report_form_versions set status='published',approved_by=v_user,approved_at=now(),published_at=now() where id=p_version_id returning id into v_version;
  return v_version;
end $$;
revoke all on function public.approve_report_form_version(uuid) from public, anon, authenticated;
grant execute on function public.approve_report_form_version(uuid) to authenticated;

create or replace function public.publish_task_report_form(
  p_task_id uuid,
  p_template_id uuid,
  p_version_id uuid,
  p_report_required boolean default true
) returns uuid language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_template public.report_form_templates%rowtype;
  v_version public.report_form_versions%rowtype;
  v_role text;
  v_snapshot uuid;
  v_schema jsonb;
begin
  if v_user is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found then raise exception using errcode='P0002', message='task_not_found'; end if;
  if not public.report_designer_allowed_for_org(v_task.organization_id) then raise exception using errcode='42501', message='permission_denied'; end if;
  if v_task.report_form_snapshot_id is not null or exists(select 1 from public.task_report_form_snapshots s where s.task_id=v_task.id) then
    raise exception using errcode='22023', message='report_form_snapshot_immutable';
  end if;
  select * into v_template from public.report_form_templates where id=p_template_id and organization_id=v_task.organization_id and is_active;
  if not found then raise exception using errcode='P0002', message='report_form_template_not_found'; end if;
  select * into v_version from public.report_form_versions where id=p_version_id and template_id=p_template_id for share;
  if not found or v_version.status<>'published' or v_version.approved_by is null or v_version.approved_at is null then
    raise exception using errcode='22023', message='report_form_version_requires_approval';
  end if;
  v_role := v_task.position_code;
  if v_role is null and v_task.template_id is not null then select role_code into v_role from public.task_templates where id=v_task.template_id and organization_id=v_task.organization_id; end if;
  if v_role is null then raise exception using errcode='22023', message='task_role_missing'; end if;
  if v_role<>v_template.role_code then raise exception using errcode='22023', message='report_template_role_mismatch'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('key',f.field_key,'label',f.label,'description',f.description,'type',f.field_type,'required',f.is_required,'repeatable',f.repeatable,'options',f.options,'validation',f.validation,'config',f.config) order by f.sort_order),'[]'::jsonb)
  into v_schema from public.report_form_version_fields f where f.version_id=p_version_id;
  if jsonb_array_length(v_schema)=0 then raise exception using errcode='22023', message='report_form_fields_required'; end if;
  insert into public.task_report_form_snapshots(task_id,template_id,version_id,report_required,schema,published_by)
  values(v_task.id,v_template.id,v_version.id,coalesce(p_report_required,v_version.report_required),v_schema,v_user)
  returning id into v_snapshot;
  update public.tasks set report_required=coalesce(p_report_required,v_version.report_required),report_form_snapshot_id=v_snapshot,updated_at=now() where id=v_task.id;
  insert into public.task_activity_log(task_id,actor_id,action,details)
  values(v_task.id,v_user,'report_form_published',jsonb_build_object('snapshot_id',v_snapshot,'version_id',v_version.id));
  return v_snapshot;
end $$;
revoke all on function public.publish_task_report_form(uuid,uuid,uuid,boolean) from public, anon, authenticated;
grant execute on function public.publish_task_report_form(uuid,uuid,uuid,boolean) to authenticated;

create or replace function public.create_task_with_report_form(
  p_organization_id uuid,
  p_title text,
  p_description text,
  p_due_at timestamptz,
  p_priority text,
  p_branch_id uuid,
  p_role_code text,
  p_template_id uuid,
  p_assigned_to uuid,
  p_report_template_id uuid,
  p_report_version_id uuid,
  p_report_required boolean
) returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_task_id uuid;
  v_legacy_fields integer := 0;
  v_has_report boolean := false;
  v_version_role text;
begin
  if v_user is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  if not public.has_org_permission(p_organization_id,'tasks.manage',null::uuid) then raise exception using errcode='42501', message='permission_denied'; end if;
  if p_title is null or length(trim(p_title))<2 or length(trim(p_title))>200 or p_due_at is null then raise exception using errcode='22023', message='task_title_or_due_date_invalid'; end if;
  if p_role_code not in ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker') then raise exception using errcode='22023', message='invalid_task_role'; end if;
  if not exists (
    select 1 from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id=m.organization_id and ra.membership_id=m.id
    where m.organization_id=p_organization_id and m.user_id=p_assigned_to and m.is_active and ra.role_code=p_role_code
      and (p_branch_id is null or ra.branch_id=p_branch_id)
  ) then raise exception using errcode='22023', message='no_employee_for_role'; end if;
  if p_branch_id is not null and not exists(select 1 from public.branches b where b.id=p_branch_id and b.organization_id=p_organization_id and b.is_active) then
    raise exception using errcode='22023', message='invalid_task_branch';
  end if;
  if p_template_id is not null then
    if not exists(select 1 from public.task_templates tt where tt.id=p_template_id and tt.organization_id=p_organization_id and tt.is_active and tt.role_code=p_role_code) then
      raise exception using errcode='22023', message='task_template_role_mismatch';
    end if;
    select count(*) into v_legacy_fields from public.task_template_report_fields f where f.template_id=p_template_id;
  end if;
  if p_report_template_id is null and p_report_version_id is not null then raise exception using errcode='22023', message='report_form_version_without_template'; end if;
  if p_report_template_id is not null then
    if p_report_version_id is null then raise exception using errcode='22023', message='report_form_version_required'; end if;
    select t.role_code into v_version_role
    from public.report_form_templates t
    join public.report_form_versions v on v.template_id=t.id
    where t.id=p_report_template_id and t.organization_id=p_organization_id and t.is_active
      and v.id=p_report_version_id and v.status='published' and v.approved_by is not null and v.approved_at is not null;
    if not found then raise exception using errcode='22023', message='report_form_version_requires_approval'; end if;
    if v_version_role<>p_role_code then raise exception using errcode='22023', message='report_template_role_mismatch'; end if;
    v_has_report := true;
  elsif v_legacy_fields>0 then
    v_has_report := true;
  end if;
  if coalesce(p_report_required,false) and not v_has_report then raise exception using errcode='22023', message='task_report_required_without_fields'; end if;

  insert into public.tasks(organization_id,branch_id,title,description,assigned_to,created_by,due_at,priority,template_id,position_code,report_required)
  values(p_organization_id,p_branch_id,trim(p_title),nullif(trim(coalesce(p_description,'')),''),p_assigned_to,v_user,p_due_at,p_priority,p_template_id,p_role_code,coalesce(p_report_required,false) and v_has_report)
  returning id into v_task_id;

  if v_legacy_fields>0 then
    insert into public.task_report_fields(task_id,label,field_key,field_type,is_required,options,sort_order)
    select v_task_id,f.label,f.field_key,f.field_type,f.is_required,f.options,f.sort_order
    from public.task_template_report_fields f where f.template_id=p_template_id order by f.sort_order;
  end if;
  if p_report_template_id is not null then
    perform public.publish_task_report_form(v_task_id,p_report_template_id,p_report_version_id,coalesce(p_report_required,false));
  end if;
  return jsonb_build_object('id',v_task_id,'assigned_to',p_assigned_to,'position_code',p_role_code,'report_required',coalesce(p_report_required,false) and v_has_report);
end $$;
revoke all on function public.create_task_with_report_form(uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean) from public, anon, authenticated;
grant execute on function public.create_task_with_report_form(uuid,text,text,timestamptz,text,uuid,text,uuid,uuid,uuid,uuid,boolean) to authenticated;

commit;
