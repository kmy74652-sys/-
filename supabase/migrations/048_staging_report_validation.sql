begin;

-- Validated report-builder RPCs and validation rules, adapted to has_org_permission.
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
returns boolean language sql stable security definer set search_path=public,auth as $$
 select public.has_org_permission(p_organization_id,'report_forms.manage',null::uuid)
     or public.has_org_permission(p_organization_id,'task_library.manage',null::uuid)
$$;

create or replace function public.report_can_review_in_org(p_organization_id uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select public.has_org_permission(p_organization_id,'tasks.review',null::uuid)
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

commit;
