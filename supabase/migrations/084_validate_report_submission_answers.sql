-- Enforce required published-form fields in the database before a report is submitted.
-- Additive guard only; no existing report data is modified.
create or replace function public.validate_report_submission_answers()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version_id uuid;
  v_field record;
  v_answer jsonb;
  v_should_validate boolean := false;
begin
  if tg_op = 'INSERT' then
    v_should_validate := new.status = 'submitted';
  else
    v_should_validate := new.status = 'submitted'
      and old.status in ('draft','returned')
      and new.status is distinct from old.status;
    if old.status = 'returned' and new.status = 'submitted' then
      new.review_note := null;
    end if;
  end if;

  if not v_should_validate then
    return new;
  end if;

  select v.id into v_version_id
  from public.report_form_versions v
  where v.template_id = new.form_id
    and v.status = 'published'
    and v.approved_by is not null
    and v.approved_at is not null
  order by v.version_no desc
  limit 1;

  if v_version_id is null then
    raise exception 'لا توجد نسخة معتمدة ونشطة لهذا النموذج';
  end if;

  for v_field in
    select f.field_key, f.label
    from public.report_form_version_fields f
    where f.version_id = v_version_id and f.is_required
  loop
    v_answer := new.answers -> v_field.field_key;
    if v_answer is null
       or jsonb_typeof(v_answer) = 'null'
       or (jsonb_typeof(v_answer) = 'string' and btrim(v_answer #>> '{}') = '')
       or (jsonb_typeof(v_answer) = 'array' and jsonb_array_length(v_answer) = 0)
       or (jsonb_typeof(v_answer) = 'object' and v_answer = '{}'::jsonb) then
      raise exception 'الحقل المطلوب غير مكتمل: %', v_field.label;
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_validate_report_submission_answers on public.report_submissions;
create trigger trg_validate_report_submission_answers
before insert or update on public.report_submissions
for each row execute function public.validate_report_submission_answers();

revoke all on function public.validate_report_submission_answers() from public, anon;
grant execute on function public.validate_report_submission_answers() to authenticated;

