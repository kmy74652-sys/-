begin;

-- Additive integrity hardening for the report designer. Existing report rows and snapshots are preserved.
-- Do not alter task_attachments, task_activity_log, mobile_task_timeline, or the task-attachments storage bucket.

alter table public.tasks add column if not exists position_code text;
update public.tasks t
set position_code = tt.role_code
from public.task_templates tt
where t.template_id = tt.id
  and t.position_code is null
  and tt.role_code in ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker');
do $$ begin
  alter table public.tasks add constraint tasks_position_code_check
    check (position_code is null or position_code in ('owner','admin_followup','accountant','warehouse_keeper','warehouse_worker'));
exception when duplicate_object then null; end $$;

alter table public.task_reports add column if not exists report_form_snapshot_id uuid;
alter table public.task_reports add column if not exists idempotency_key text;
do $$ begin
  alter table public.task_reports add constraint task_reports_report_form_snapshot_fk
    foreign key (report_form_snapshot_id) references public.task_report_form_snapshots(id) on delete restrict;
exception when duplicate_object then null; end $$;
create unique index if not exists task_reports_submit_idempotency_uq
  on public.task_reports (submitted_by, idempotency_key) where idempotency_key is not null;
create index if not exists task_reports_snapshot_idx on public.task_reports (report_form_snapshot_id) where report_form_snapshot_id is not null;

create table if not exists public.task_report_signature_attachments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete restrict,
  report_id uuid not null references public.task_reports(id) on delete restrict,
  report_form_snapshot_id uuid not null references public.task_report_form_snapshots(id) on delete restrict,
  field_key text not null check (field_key ~ '^[a-z][a-z0-9_]{0,63}$'),
  signed_by uuid not null references auth.users(id),
  consent_text text not null default '' check (length(consent_text) <= 2000),
  acknowledged boolean not null default false,
  stroke_paths jsonb not null check (jsonb_typeof(stroke_paths) = 'array'),
  signed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (report_id, field_key),
  check (jsonb_array_length(stroke_paths) between 1 and 200)
);
create index if not exists task_report_signature_task_idx on public.task_report_signature_attachments (task_id, signed_at desc);
alter table public.task_report_signature_attachments enable row level security;
revoke all on public.task_report_signature_attachments from public, anon, authenticated;
grant select on public.task_report_signature_attachments to authenticated;

create or replace function public.report_designer_allowed_for_org(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select auth.uid() is not null and exists (
    select 1
    from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
    join public.role_permissions rp on rp.role_code = ra.role_code and rp.permission_code = 'report_forms.manage'
    where m.user_id = auth.uid() and m.organization_id = p_organization_id and m.is_active
  );
$$;

create or replace function public.report_can_review_in_org(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select auth.uid() is not null and exists (
    select 1
    from public.organization_memberships m
    join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
    join public.role_permissions rp on rp.role_code = ra.role_code and rp.permission_code = 'tasks.review'
    where m.user_id = auth.uid() and m.organization_id = p_organization_id and m.is_active
  );
$$;
revoke all on function public.report_designer_allowed_for_org(uuid) from public, anon;
revoke all on function public.report_can_review_in_org(uuid) from public, anon;
grant execute on function public.report_designer_allowed_for_org(uuid) to authenticated;
grant execute on function public.report_can_review_in_org(uuid) to authenticated;

create or replace function public.report_json_numeric(p_value jsonb, p_label text)
returns numeric language plpgsql immutable set search_path = public as $$
declare v_text text; v_number numeric;
begin
  if p_value is null or jsonb_typeof(p_value) not in ('number','string') then
    raise exception using errcode='22023', message='report_field_invalid_number:' || coalesce(p_label,'');
  end if;
  v_text := p_value #>> '{}';
  if length(v_text) > 64 or v_text !~ '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$' then
    raise exception using errcode='22023', message='report_field_invalid_number:' || coalesce(p_label,'');
  end if;
  begin v_number := v_text::numeric;
  exception when others then raise exception using errcode='22023', message='report_field_invalid_number:' || coalesce(p_label,''); end;
  if abs(v_number) > 100000000000000000000000000000000000000000000000000 then
    raise exception using errcode='22023', message='report_field_number_too_large:' || coalesce(p_label,'');
  end if;
  return v_number;
end $$;

create or replace function public.report_safe_formula_eval(p_expression text, p_values jsonb, p_depth integer default 0)
returns numeric language plpgsql immutable set search_path = public as $$
declare
  v_expr text := regexp_replace(coalesce(p_expression,''), '\s+', '', 'g');
  v_length integer;
  v_depth_now integer := 0;
  v_index integer;
  v_split integer := 0;
  v_char text;
  v_previous text;
  v_wraps boolean;
  v_key text;
  v_match text[];
  v_right numeric;
  v_left numeric;
begin
  if p_depth > 64 or length(v_expr) = 0 or length(v_expr) > 2048 then
    raise exception using errcode='22023', message='invalid_calculated_report_formula';
  end if;
  v_length := length(v_expr);

  v_match := regexp_match(v_expr, '^sum\(([a-z][a-z0-9_]{0,63})\)$');
  if v_match is not null then
    if p_values ? v_match[1] and p_values->v_match[1] <> 'null'::jsonb then
      return public.report_json_numeric(p_values->v_match[1], v_match[1]);
    end if;
    return 0;
  end if;
  v_match := regexp_match(v_expr, '^difference\(([a-z][a-z0-9_]{0,63}),([a-z][a-z0-9_]{0,63})\)$');
  if v_match is not null then
    v_left := case when p_values ? v_match[1] and p_values->v_match[1] <> 'null'::jsonb then public.report_json_numeric(p_values->v_match[1], v_match[1]) else 0 end;
    v_right := case when p_values ? v_match[2] and p_values->v_match[2] <> 'null'::jsonb then public.report_json_numeric(p_values->v_match[2], v_match[2]) else 0 end;
    return v_left - v_right;
  end if;

  if v_expr ~ '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$' then
    return v_expr::numeric;
  end if;
  v_match := regexp_match(v_expr, '^\{([a-z][a-z0-9_]{0,63})\}$');
  if v_match is not null then
    if not (p_values ? v_match[1]) or p_values->v_match[1] = 'null'::jsonb then
      raise exception using errcode='22023', message='report_calculated_input_missing:' || v_match[1];
    end if;
    return public.report_json_numeric(p_values->v_match[1], v_match[1]);
  end if;

  -- Remove only parentheses that enclose the entire expression.
  if left(v_expr,1)='(' and right(v_expr,1)=')' then
    v_wraps := true;
    for v_index in 1..v_length loop
      v_char := substr(v_expr,v_index,1);
      if v_char='(' then v_depth_now := v_depth_now + 1;
      elsif v_char=')' then v_depth_now := v_depth_now - 1; end if;
      if v_depth_now < 0 then raise exception using errcode='22023', message='invalid_calculated_report_formula'; end if;
      if v_depth_now=0 and v_index < v_length then v_wraps := false; exit; end if;
    end loop;
    if v_wraps and v_depth_now=0 then
      return public.report_safe_formula_eval(substr(v_expr,2,v_length-2),p_values,p_depth+1);
    end if;
  end if;
  if left(v_expr,1)='+' then return public.report_safe_formula_eval(substr(v_expr,2),p_values,p_depth+1); end if;
  if left(v_expr,1)='-' then return -public.report_safe_formula_eval(substr(v_expr,2),p_values,p_depth+1); end if;

  -- Split on the rightmost top-level additive operator (left associative).
  v_depth_now := 0; v_split := 0;
  for v_index in reverse v_length..1 loop
    v_char := substr(v_expr,v_index,1);
    if v_char=')' then v_depth_now := v_depth_now + 1;
    elsif v_char='(' then v_depth_now := v_depth_now - 1;
    elsif v_depth_now=0 and v_char in ('+','-') and v_index > 1 then
      v_previous := substr(v_expr,v_index-1,1);
      if v_previous not in ('+','-','*','/','(') then v_split := v_index; exit; end if;
    end if;
  end loop;
  if v_split > 0 then
    v_left := public.report_safe_formula_eval(substr(v_expr,1,v_split-1),p_values,p_depth+1);
    v_right := public.report_safe_formula_eval(substr(v_expr,v_split+1),p_values,p_depth+1);
    if substr(v_expr,v_split,1)='+' then return v_left+v_right; else return v_left-v_right; end if;
  end if;

  -- Split on the rightmost top-level multiplicative operator.
  v_depth_now := 0; v_split := 0;
  for v_index in reverse v_length..1 loop
    v_char := substr(v_expr,v_index,1);
    if v_char=')' then v_depth_now := v_depth_now + 1;
    elsif v_char='(' then v_depth_now := v_depth_now - 1;
    elsif v_depth_now=0 and v_char in ('*','/') then v_split := v_index; exit;
    end if;
  end loop;
  if v_split > 0 then
    v_left := public.report_safe_formula_eval(substr(v_expr,1,v_split-1),p_values,p_depth+1);
    v_right := public.report_safe_formula_eval(substr(v_expr,v_split+1),p_values,p_depth+1);
    if substr(v_expr,v_split,1)='/' and v_right=0 then
      raise exception using errcode='22023', message='report_calculated_division_by_zero';
    end if;
    if substr(v_expr,v_split,1)='*' then return v_left*v_right; else return v_left/v_right; end if;
  end if;
  raise exception using errcode='22023', message='invalid_calculated_report_formula';
end $$;

create or replace function public.report_validate_scalar(p_type text, p_value jsonb, p_rules jsonb, p_label text)
returns void language plpgsql immutable set search_path = public as $$
declare v_number numeric; v_min numeric; v_max numeric; v_decimals integer; v_min_length integer; v_max_length integer; v_text text;
begin
  if p_type in ('integer','quantity','money','number','progress') then
    v_number := public.report_json_numeric(p_value,p_label);
    if p_type='integer' and trunc(v_number) <> v_number then raise exception using errcode='22023', message='report_field_integer_required:' || p_label; end if;
    if nullif(p_rules->>'min','') is not null then v_min := (p_rules->>'min')::numeric; if v_number < v_min then raise exception using errcode='22023', message='report_field_below_min:' || p_label || ':' || v_min; end if; end if;
    if nullif(p_rules->>'max','') is not null then v_max := (p_rules->>'max')::numeric; if v_number > v_max then raise exception using errcode='22023', message='report_field_above_max:' || p_label || ':' || v_max; end if; end if;
    if coalesce((p_rules->>'allow_negative')::boolean,true)=false and v_number < 0 then raise exception using errcode='22023', message='report_field_negative_not_allowed:' || p_label; end if;
    if coalesce((p_rules->>'allow_zero')::boolean,true)=false and v_number=0 then raise exception using errcode='22023', message='report_field_zero_not_allowed:' || p_label; end if;
    if nullif(p_rules->>'decimal_places','') is not null then
      v_decimals := (p_rules->>'decimal_places')::integer;
      if v_decimals < 0 or v_decimals > 8 or round(v_number,v_decimals) <> v_number then raise exception using errcode='22023', message='report_field_decimal_places:' || p_label || ':' || v_decimals; end if;
    end if;
    return;
  end if;
  if p_type in ('short_text','long_text','decision_notes','text','textarea','notes','status') then
    if jsonb_typeof(p_value)<>'string' then raise exception using errcode='22023', message='report_field_invalid_text:' || p_label; end if;
    v_text := p_value #>> '{}';
    if nullif(p_rules->>'min_length','') is not null then v_min_length := (p_rules->>'min_length')::integer; if char_length(trim(v_text)) < v_min_length then raise exception using errcode='22023', message='report_field_min_length:' || p_label || ':' || v_min_length; end if; end if;
    if nullif(p_rules->>'max_length','') is not null then v_max_length := (p_rules->>'max_length')::integer; if char_length(v_text) > v_max_length then raise exception using errcode='22023', message='report_field_max_length:' || p_label || ':' || v_max_length; end if; end if;
    return;
  end if;
  raise exception using errcode='22023', message='invalid_report_field_type:' || p_label;
end $$;

create or replace function public.report_validate_field(p_field jsonb, p_value jsonb, p_values jsonb, p_task_id uuid)
returns void language plpgsql stable set search_path = public as $$
declare
  v_key text := coalesce(p_field->>'key','');
  v_label text := coalesce(p_field->>'label','الحقل');
  v_type text := coalesce(p_field->>'type','');
  v_required boolean := coalesce((p_field->>'required')::boolean,false);
  v_options jsonb := coalesce(p_field->'options','[]'::jsonb);
  v_rules jsonb := coalesce(p_field->'validation','{}'::jsonb);
  v_config jsonb := coalesce(p_field->'config','{}'::jsonb);
  v_value_text text;
  v_item jsonb;
  v_column jsonb;
  v_column_key text;
  v_column_label text;
  v_column_type text;
  v_column_rules jsonb;
  v_cell jsonb;
  v_row jsonb;
  v_row_key text;
  v_seen text[] := array[]::text[];
  v_rows jsonb;
  v_columns jsonb;
  v_index integer := 0;
  v_min_rows integer;
  v_max_rows integer;
  v_min numeric;
  v_max numeric;
  v_expected numeric;
  v_actual numeric;
  v_formula text;
  v_match text[];
  v_strokes jsonb;
  v_path text;
  v_attachment_path text;
  v_total_path_length integer := 0;
  v_consent text;
begin
  if p_value is null or p_value='null'::jsonb
    or (jsonb_typeof(p_value)='string' and trim(p_value#>>'{}')='')
    or (jsonb_typeof(p_value)='array' and jsonb_array_length(p_value)=0) then
    if v_required then raise exception using errcode='22023', message='required_report_field_missing:' || v_label; end if;
    if v_type='signature' and length(trim(coalesce(v_config->>'consent_text','')))>0 then raise exception using errcode='22023', message='report_signature_required:' || v_label; end if;
    if v_type='table' and nullif(v_config->>'min_rows','') is not null and (v_config->>'min_rows')::integer > 0 then
      raise exception using errcode='22023', message='report_table_min_rows:' || v_label || ':' || (v_config->>'min_rows');
    end if;
    return;
  end if;

  if v_type in ('short_text','long_text','decision_notes','text','textarea','notes','status','integer','quantity','money','number','progress') then
    perform public.report_validate_scalar(v_type,p_value,v_rules,v_label);
  elsif v_type in ('datetime','date') then
    if jsonb_typeof(p_value)<>'string' then raise exception using errcode='22023', message='report_field_invalid_datetime:' || v_label; end if;
    begin
      if v_type='date' then perform (p_value#>>'{}')::date; else perform (p_value#>>'{}')::timestamptz; end if;
    exception when others then raise exception using errcode='22023', message='report_field_invalid_datetime:' || v_label; end;
  elsif v_type in ('boolean','checkbox') then
    if jsonb_typeof(p_value)<>'boolean' then raise exception using errcode='22023', message='report_field_invalid_boolean:' || v_label; end if;
  elsif v_type='select' then
    if jsonb_typeof(p_value)<>'string' or jsonb_typeof(v_options)<>'array' or not (v_options ? (p_value#>>'{}')) then raise exception using errcode='22023', message='invalid_report_field_option:' || v_label; end if;
  elsif v_type='multiselect' then
    if jsonb_typeof(p_value)<>'array' then raise exception using errcode='22023', message='invalid_report_field_option:' || v_label; end if;
    for v_item in select value from jsonb_array_elements(p_value) loop
      if jsonb_typeof(v_item)<>'string' then raise exception using errcode='22023', message='invalid_report_field_option:' || v_label; end if;
      v_value_text := v_item#>>'{}';
      if not (v_options ? v_value_text) then raise exception using errcode='22023', message='invalid_report_field_option:' || v_label; end if;
      if v_value_text=any(v_seen) then raise exception using errcode='22023', message='duplicate_report_field_option:' || v_label; end if;
      v_seen := array_append(v_seen,v_value_text);
    end loop;
  elsif v_type='table' then
    if jsonb_typeof(p_value)<>'array' then raise exception using errcode='22023', message='invalid_report_field_type:' || v_label; end if;
    v_rows := p_value; v_columns := coalesce(v_config->'columns','[]'::jsonb);
    if jsonb_typeof(v_columns)<>'array' or jsonb_array_length(v_columns)=0 then raise exception using errcode='22023', message='report_table_columns_missing:' || v_label; end if;
    if jsonb_array_length(v_rows)>500 then raise exception using errcode='22023', message='report_table_max_rows:' || v_label || ':500'; end if;
    if nullif(v_config->>'min_rows','') is not null then v_min_rows := (v_config->>'min_rows')::integer; if jsonb_array_length(v_rows)<v_min_rows then raise exception using errcode='22023', message='report_table_min_rows:' || v_label || ':' || v_min_rows; end if; end if;
    if nullif(v_config->>'max_rows','') is not null then v_max_rows := (v_config->>'max_rows')::integer; if jsonb_array_length(v_rows)>(v_config->>'max_rows')::integer then raise exception using errcode='22023', message='report_table_max_rows:' || v_label || ':' || v_max_rows; end if; end if;
    for v_row in select value from jsonb_array_elements(v_rows) loop
      v_index := v_index+1;
      if jsonb_typeof(v_row)<>'object' then raise exception using errcode='22023', message='invalid_report_table_row:' || v_label; end if;
      for v_row_key in select jsonb_object_keys(v_row) loop
        if not exists (
          select 1 from jsonb_array_elements(v_columns) c(value)
          where case when jsonb_typeof(c.value)='string' then c.value#>>'{}' else coalesce(c.value->>'key',c.value->>'label',c.value->>'name') end = v_row_key
        ) then raise exception using errcode='22023', message='invalid_report_table_column:' || v_label; end if;
      end loop;
      for v_column in select value from jsonb_array_elements(v_columns) loop
        if jsonb_typeof(v_column)='string' then
          v_column_key := v_column#>>'{}'; v_column_label := v_column_key; v_column_type := 'short_text'; v_column_rules := '{}'::jsonb;
        else
          v_column_key := coalesce(v_column->>'key',v_column->>'label',v_column->>'name','');
          v_column_label := coalesce(v_column->>'label',v_column->>'name',v_column_key);
          v_column_type := coalesce(v_column->>'type',v_column->>'field_type','short_text');
          v_column_rules := coalesce(v_column->'validation','{}'::jsonb);
        end if;
        v_cell := v_row->v_column_key;
        if v_cell is null or v_cell='null'::jsonb or (jsonb_typeof(v_cell)='string' and trim(v_cell#>>'{}')='') then
          if coalesce((v_column->>'required')::boolean,coalesce((v_column->>'is_required')::boolean,false)) then raise exception using errcode='22023', message='required_report_table_cell:' || v_label || ':' || v_index || ':' || v_column_label; end if;
          continue;
        end if;
        if v_column_type in ('short_text','long_text','integer','quantity','money','decision_notes') then
          perform public.report_validate_scalar(v_column_type,v_cell,v_column_rules,v_label || '، ' || v_column_label);
        elsif v_column_type='boolean' then
          if jsonb_typeof(v_cell)<>'boolean' and not (jsonb_typeof(v_cell)='string' and v_cell#>>'{}' in ('true','false')) then raise exception using errcode='22023', message='invalid_report_table_boolean:' || v_label || ':' || v_column_label; end if;
        elsif v_column_type='select' then
          if jsonb_typeof(v_cell)<>'string' or jsonb_typeof(coalesce(v_column->'options','[]'::jsonb))<>'array' or not (coalesce(v_column->'options','[]'::jsonb) ? (v_cell#>>'{}')) then raise exception using errcode='22023', message='invalid_report_table_option:' || v_label || ':' || v_column_label; end if;
        else raise exception using errcode='22023', message='invalid_report_table_column_type:' || v_label || ':' || v_column_label;
        end if;
      end loop;
    end loop;
  elsif v_type='calculated' then
    v_actual := public.report_json_numeric(p_value,v_label);
    v_formula := trim(coalesce(v_config->>'formula',''));
    v_match := regexp_match(v_formula,'^sum_rows\(([^.]{1,64})\.([^)]{1,128})\)$');
    if v_match is not null then
      v_expected := 0;
      if jsonb_typeof(p_values->v_match[1])='array' then
        for v_row in select value from jsonb_array_elements(p_values->v_match[1]) loop
          v_cell := v_row->v_match[2];
          if v_cell is not null and v_cell<>'null'::jsonb and not (jsonb_typeof(v_cell)='string' and trim(v_cell#>>'{}')='') then v_expected := v_expected + public.report_json_numeric(v_cell,v_match[2]); end if;
        end loop;
      end if;
    else v_expected := public.report_safe_formula_eval(v_formula,p_values); end if;
    if abs(v_expected-v_actual)>0.000000001 then raise exception using errcode='22023', message='invalid_calculated_report_value:' || v_label; end if;
  elsif v_type='signature' then
    if jsonb_typeof(p_value)<>'object' then raise exception using errcode='22023', message='invalid_report_signature:' || v_label; end if;
    v_strokes := p_value->'strokes'; v_consent := coalesce(v_config->>'consent_text','');
    if jsonb_typeof(v_strokes)<>'array' then raise exception using errcode='22023', message='invalid_report_signature:' || v_label; end if;
    if (v_required or length(trim(v_consent))>0) and jsonb_array_length(v_strokes)=0 then raise exception using errcode='22023', message='report_signature_required:' || v_label; end if;
    if length(trim(v_consent))>0 and coalesce((p_value->>'acknowledged')::boolean,false)=false then raise exception using errcode='22023', message='report_signature_consent_required:' || v_label; end if;
    if jsonb_array_length(v_strokes)>200 then raise exception using errcode='22023', message='report_signature_too_many_strokes:' || v_label; end if;
    for v_item in select value from jsonb_array_elements(v_strokes) loop
      if jsonb_typeof(v_item)<>'string' then raise exception using errcode='22023', message='invalid_report_signature:' || v_label; end if;
      v_path := v_item#>>'{}'; v_total_path_length := v_total_path_length+length(v_path);
      if length(v_path)>15000 or v_path !~ '^[ML0-9 .+\-]+$' or v_total_path_length>200000 then raise exception using errcode='22023', message='invalid_report_signature:' || v_label; end if;
    end loop;
  elsif v_type in ('image','file','attachment') then
    if jsonb_typeof(p_value)<>'array' or jsonb_array_length(p_value)>20 then raise exception using errcode='22023', message='invalid_report_attachment:' || v_label; end if;
    for v_item in select value from jsonb_array_elements(p_value) loop
      if jsonb_typeof(v_item)<>'object' then raise exception using errcode='22023', message='invalid_report_attachment:' || v_label; end if;
      v_attachment_path := nullif(trim(v_item->>'path'),'');
      if v_attachment_path is null or not exists (
        select 1 from public.task_attachments a
        where a.task_id=p_task_id and a.uploaded_by=auth.uid() and a.storage_path=v_attachment_path
      ) then raise exception using errcode='22023', message='invalid_report_attachment:' || v_label; end if;
    end loop;
  else
    raise exception using errcode='22023', message='invalid_report_field_type:' || v_label;
  end if;
end $$;

revoke all on function public.report_json_numeric(jsonb,text) from public, anon, authenticated;
revoke all on function public.report_safe_formula_eval(text,jsonb,integer) from public, anon, authenticated;
revoke all on function public.report_validate_scalar(text,jsonb,jsonb,text) from public, anon, authenticated;
revoke all on function public.report_validate_field(jsonb,jsonb,jsonb,uuid) from public, anon, authenticated;

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
  if not exists (select 1 from public.roles r where r.code=p_role_code) then raise exception using errcode='22023', message='invalid_report_template_role'; end if;
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
  if not alshaari_private.has_permission(p_organization_id,'tasks.manage',null::uuid) then raise exception using errcode='42501', message='permission_denied'; end if;
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

create or replace function public.guard_report_signature_mutation()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task uuid; v_snapshot uuid; v_field text;
begin
  if tg_op='INSERT' then
    select r.task_id,r.report_form_snapshot_id into v_task,v_snapshot from public.task_reports r where r.id=new.report_id;
    if not found or v_task<>new.task_id or v_snapshot is distinct from new.report_form_snapshot_id then raise exception using errcode='22023', message='report_signature_link_invalid'; end if;
    if not exists (
      select 1 from public.task_report_form_snapshots s,jsonb_array_elements(s.schema) f(value)
      where s.id=new.report_form_snapshot_id and f.value->>'key'=new.field_key and f.value->>'type'='signature'
    ) then raise exception using errcode='22023', message='report_signature_field_invalid'; end if;
    if jsonb_typeof(new.stroke_paths)<>'array' or jsonb_array_length(new.stroke_paths)<1 or jsonb_array_length(new.stroke_paths)>200 then raise exception using errcode='22023', message='invalid_report_signature'; end if;
    return new;
  end if;
  raise exception using errcode='42501', message='report_signature_immutable';
end $$;
create trigger task_report_signature_immutable
before insert or update or delete on public.task_report_signature_attachments
for each row execute function public.guard_report_signature_mutation();

create or replace function public.guard_task_report_snapshot_and_signature()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_signature record;
begin
  if tg_op='DELETE' then
    if exists(select 1 from public.task_report_signature_attachments a where a.report_id=old.id) then raise exception using errcode='42501', message='signed_report_immutable'; end if;
    return old;
  end if;
  if old.report_form_snapshot_id is distinct from new.report_form_snapshot_id or old.idempotency_key is distinct from new.idempotency_key then
    raise exception using errcode='42501', message='report_provenance_immutable';
  end if;
  for v_signature in select id,field_key from public.task_report_signature_attachments where report_id=old.id loop
    if new.values->v_signature.field_key->>'signature_attachment_id' is distinct from v_signature.id::text then
      raise exception using errcode='42501', message='report_signature_immutable';
    end if;
  end loop;
  return new;
end $$;
create trigger task_reports_signature_protection
before update or delete on public.task_reports
for each row execute function public.guard_task_report_snapshot_and_signature();

drop function if exists public.mobile_submit_task_report(uuid,jsonb);
create or replace function public.mobile_submit_task_report(p_task_id uuid, p_values jsonb, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_user_id uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_report public.task_reports%rowtype;
  v_snapshot public.task_report_form_snapshots%rowtype;
  v_field jsonb;
  v_raw jsonb;
  v_key text;
  v_type text;
  v_clean_values jsonb := p_values;
  v_signatures jsonb := '[]'::jsonb;
  v_signature_id uuid;
  v_signature jsonb;
  v_idempotency_key text;
  v_now timestamptz := now();
begin
  if v_user_id is null then raise exception using errcode='28000', message='not_authenticated'; end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception using errcode='22023', message='invalid_task_report_payload'; end if;
  if p_idempotency_key is not null and (length(trim(p_idempotency_key))=0 or length(p_idempotency_key)>200) then raise exception using errcode='22023', message='invalid_report_idempotency_key'; end if;
  v_idempotency_key := coalesce(nullif(trim(p_idempotency_key),''),'report:' || p_task_id::text || ':' || gen_random_uuid()::text);
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found or v_task.assigned_to<>v_user_id then raise exception using errcode='P0002', message='task_not_found'; end if;
  if not exists(select 1 from public.organization_memberships m where m.organization_id=v_task.organization_id and m.user_id=v_user_id and m.is_active) then
    raise exception using errcode='42501', message='employee_not_active';
  end if;
  select * into v_report from public.task_reports where submitted_by=v_user_id and idempotency_key=v_idempotency_key;
  if found then
    if v_report.task_id<>v_task.id then raise exception using errcode='22023', message='report_idempotency_key_conflict'; end if;
    return jsonb_build_object('report',jsonb_build_object('id',v_report.id,'task_id',v_report.task_id,'submitted_by',v_report.submitted_by,'values',v_report.values,'created_at',v_report.created_at));
  end if;
  if v_task.status not in ('in_progress','needs_revision') then raise exception using errcode='22023', message='task_must_be_in_progress'; end if;
  if v_task.report_required and v_task.report_form_snapshot_id is null then raise exception using errcode='22023', message='task_report_snapshot_missing'; end if;

  if v_task.report_form_snapshot_id is not null then
    select * into v_snapshot from public.task_report_form_snapshots where id=v_task.report_form_snapshot_id and task_id=v_task.id;
    if not found then raise exception using errcode='22023', message='task_report_snapshot_missing'; end if;
    for v_key in select jsonb_object_keys(p_values) loop
      if not exists(select 1 from jsonb_array_elements(v_snapshot.schema) f(value) where f.value->>'key'=v_key) then raise exception using errcode='22023', message='unknown_report_field:' || v_key; end if;
    end loop;
    for v_field in select value from jsonb_array_elements(v_snapshot.schema) loop
      v_key := coalesce(v_field->>'key',''); v_type := coalesce(v_field->>'type',''); v_raw := p_values->v_key;
      perform public.report_validate_field(v_field,v_raw,p_values,v_task.id);
      if v_type='signature' and jsonb_typeof(v_raw)='object' and jsonb_typeof(v_raw->'strokes')='array' and jsonb_array_length(v_raw->'strokes')>0 then
        v_signature_id := gen_random_uuid();
        v_clean_values := jsonb_set(v_clean_values,array[v_key],jsonb_build_object('signature_attachment_id',v_signature_id,'acknowledged',coalesce(v_raw->'acknowledged','false'::jsonb),'signed_at',v_now),true);
        v_signatures := v_signatures || jsonb_build_array(jsonb_build_object('id',v_signature_id,'field_key',v_key,'strokes',v_raw->'strokes','consent_text',coalesce(v_field->'config'->>'consent_text',''),'acknowledged',coalesce((v_raw->>'acknowledged')::boolean,false)));
      elsif v_type='signature' then
        v_clean_values := v_clean_values - v_key;
      end if;
    end loop;
  else
    if exists(select 1 from public.task_report_fields f where f.task_id=v_task.id and f.field_type='signature') then raise exception using errcode='22023', message='report_signature_requires_snapshot'; end if;
    for v_key in select jsonb_object_keys(p_values) loop
      if not exists(select 1 from public.task_report_fields f where f.task_id=v_task.id and f.field_key=v_key) then raise exception using errcode='22023', message='unknown_report_field:' || v_key; end if;
    end loop;
    for v_field in select jsonb_build_object('field_key',f.field_key,'label',f.label,'required',f.is_required) as value from public.task_report_fields f where f.task_id=v_task.id loop
      v_key := v_field.value->>'field_key';
      if coalesce((v_field.value->>'required')::boolean,false) and (p_values->v_key is null or p_values->v_key='null'::jsonb or (jsonb_typeof(p_values->v_key)='string' and trim(p_values->>v_key)='')) then raise exception using errcode='22023', message='required_report_field_missing:' || coalesce(v_field.value->>'label',v_key); end if;
    end loop;
  end if;

  insert into public.task_reports(task_id,submitted_by,status,values,submitted_at,report_form_snapshot_id,idempotency_key)
  values(v_task.id,v_user_id,'submitted',v_clean_values,v_now,v_task.report_form_snapshot_id,v_idempotency_key)
  returning * into v_report;
  for v_signature in select value from jsonb_array_elements(v_signatures) loop
    insert into public.task_report_signature_attachments(id,task_id,report_id,report_form_snapshot_id,field_key,signed_by,consent_text,acknowledged,stroke_paths,signed_at)
    values((v_signature->>'id')::uuid,v_task.id,v_report.id,v_task.report_form_snapshot_id,v_signature->>'field_key',v_user_id,coalesce(v_signature->>'consent_text',''),coalesce((v_signature->>'acknowledged')::boolean,false),v_signature->'strokes',v_now);
  end loop;
  insert into public.task_activity_log(task_id,actor_id,action,details)
  values(v_task.id,v_user_id,'report_submitted',jsonb_build_object('report_id',v_report.id,'snapshot_id',v_task.report_form_snapshot_id));
  update public.tasks set status='report_submitted',report_submitted_at=v_now,updated_at=v_now where id=v_task.id;
  return jsonb_build_object('report',jsonb_build_object('id',v_report.id,'task_id',v_report.task_id,'submitted_by',v_report.submitted_by,'values',v_report.values,'created_at',v_report.created_at));
end $$;
revoke all on function public.mobile_submit_task_report(uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.mobile_submit_task_report(uuid,jsonb,text) to authenticated;

-- Replace the older global policies: every read/write decision now includes the matching organization.
alter table public.report_form_templates enable row level security;
alter table public.report_form_versions enable row level security;
alter table public.report_form_version_fields enable row level security;
alter table public.task_report_form_snapshots enable row level security;
alter table public.task_reports enable row level security;

drop policy if exists report_form_templates_read on public.report_form_templates;
drop policy if exists report_form_templates_manage on public.report_form_templates;
create policy report_form_templates_select_org on public.report_form_templates for select to authenticated
  using (public.report_designer_allowed_for_org(organization_id));

drop policy if exists report_form_versions_read on public.report_form_versions;
drop policy if exists report_form_versions_manage on public.report_form_versions;
create policy report_form_versions_select_org on public.report_form_versions for select to authenticated
  using (exists(select 1 from public.report_form_templates t where t.id=template_id and public.report_designer_allowed_for_org(t.organization_id)));

drop policy if exists report_form_fields_read on public.report_form_version_fields;
drop policy if exists report_form_fields_manage on public.report_form_version_fields;
create policy report_form_fields_select_org on public.report_form_version_fields for select to authenticated
  using (exists(select 1 from public.report_form_versions v join public.report_form_templates t on t.id=v.template_id where v.id=version_id and public.report_designer_allowed_for_org(t.organization_id)));

drop policy if exists task_report_snapshots_read on public.task_report_form_snapshots;
drop policy if exists task_report_snapshots_insert on public.task_report_form_snapshots;
drop policy if exists task_report_snapshots_select_scoped on public.task_report_form_snapshots;
create policy task_report_snapshots_select_scoped on public.task_report_form_snapshots for select to authenticated
  using (exists(
    select 1 from public.tasks t where t.id=task_id and (
      public.report_designer_allowed_for_org(t.organization_id)
      or public.report_can_review_in_org(t.organization_id)
      or alshaari_private.has_permission(t.organization_id,'task_reports.read',null::uuid)
      or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id and m.user_id=auth.uid() and m.is_active and (t.assigned_to=auth.uid() or t.created_by=auth.uid()))
    )
  ));

drop policy if exists task_report_signatures_select_scoped on public.task_report_signature_attachments;
create policy task_report_signatures_select_scoped on public.task_report_signature_attachments for select to authenticated
  using (exists(
    select 1 from public.task_reports r join public.tasks t on t.id=r.task_id
    where r.id=report_id and (
      public.report_designer_allowed_for_org(t.organization_id)
      or public.report_can_review_in_org(t.organization_id)
      or alshaari_private.has_permission(t.organization_id,'task_reports.read',null::uuid)
      or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id and m.user_id=auth.uid() and m.is_active and (r.submitted_by=auth.uid() or t.assigned_to=auth.uid()))
    )
  ));

-- Reports are submitted and reviewed through security-definer RPCs. Clients may read scoped reports, but may not rewrite submitted values or signature references directly.
drop policy if exists task_reports_insert_assignee on public.task_reports;
drop policy if exists task_reports_select_owner_or_reviewer on public.task_reports;
drop policy if exists task_reports_update_reviewer_or_submitter on public.task_reports;
drop policy if exists task_reports_select_scoped on public.task_reports;
create policy task_reports_select_scoped on public.task_reports for select to authenticated
  using (exists(
    select 1 from public.tasks t where t.id=task_id and (
      public.report_designer_allowed_for_org(t.organization_id)
      or public.report_can_review_in_org(t.organization_id)
      or alshaari_private.has_permission(t.organization_id,'task_reports.read',null::uuid)
      or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id and m.user_id=auth.uid() and m.is_active and (submitted_by=auth.uid() or t.assigned_to=auth.uid() or t.created_by=auth.uid()))
    )
  ));

revoke all on public.report_form_templates, public.report_form_versions, public.report_form_version_fields, public.task_report_form_snapshots from public, anon, authenticated;
grant select on public.report_form_templates, public.report_form_versions, public.report_form_version_fields, public.task_report_form_snapshots to authenticated;
revoke insert, update, delete on public.task_reports from public, anon, authenticated;
grant select on public.task_reports to authenticated;

commit;
