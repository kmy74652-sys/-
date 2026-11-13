create or replace function app.record_task_update(
  p_task_id uuid,
  p_author_employee_id uuid,
  p_status public.task_status,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  current_task public.tasks%rowtype;
begin
  select * into current_task from public.tasks where id = p_task_id for update;
  if not found then raise exception 'task_not_found'; end if;
  if current_task.assignee_employee_id <> p_author_employee_id and current_task.created_by <> p_author_employee_id then raise exception 'task_actor_not_allowed'; end if;
  if p_status not in ('pending', 'in_progress', 'submitted', 'rejected') then raise exception 'invalid_progress_status'; end if;
  if p_status = 'submitted' and current_task.proof_required and not exists (
    select 1 from public.attachments a where a.institution_id = current_task.institution_id and a.entity_type = 'task_evidence' and a.entity_id = p_task_id and not a.is_deleted
  ) then raise exception 'task_proof_required'; end if;
  if p_status = 'submitted' and current_task.status not in ('in_progress', 'rejected') then raise exception 'task_must_be_in_progress'; end if;
  if p_status = 'in_progress' and current_task.status not in ('pending', 'in_progress', 'rejected') then raise exception 'invalid_progress_transition'; end if;
  if p_status = 'rejected' then raise exception 'rejected_is_review_decision'; end if;

  insert into public.task_updates (institution_id, task_id, author_employee_id, status, note)
  values (current_task.institution_id, p_task_id, p_author_employee_id, p_status, nullif(trim(p_note), ''));
  update public.tasks set status = p_status where id = p_task_id;
  return p_task_id;
end;
$$;

create or replace function app.review_task(
  p_task_id uuid,
  p_reviewer_employee_id uuid,
  p_decision public.task_status,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  current_task public.tasks%rowtype;
begin
  select * into current_task from public.tasks where id = p_task_id for update;
  if not found then raise exception 'task_not_found'; end if;
  if current_task.status <> 'submitted' then raise exception 'task_must_be_submitted'; end if;
  if current_task.assignee_employee_id = p_reviewer_employee_id or current_task.created_by = p_reviewer_employee_id then raise exception 'task_reviewer_not_independent'; end if;
  if p_decision not in ('approved', 'rejected') then raise exception 'invalid_review_decision'; end if;

  insert into public.task_reviews (institution_id, task_id, reviewer_employee_id, decision, note)
  values (current_task.institution_id, p_task_id, p_reviewer_employee_id, p_decision, nullif(trim(p_note), ''));
  insert into public.task_updates (institution_id, task_id, author_employee_id, status, note)
  values (current_task.institution_id, p_task_id, p_reviewer_employee_id, p_decision, nullif(trim(p_note), ''));
  update public.tasks set status = p_decision where id = p_task_id;
  return p_task_id;
end;
$$;

create or replace function app.generate_recurring_tasks(p_from_date date, p_to_date date)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare
  template record;
  occurrence date;
  run_id uuid;
  institution_timezone text;
  generated_count integer := 0;
  is_due boolean;
begin
  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or p_to_date > p_from_date + 31 then raise exception 'invalid_recurrence_window'; end if;

  for template in select t.*, i.timezone from public.recurring_task_templates t join public.institutions i on i.id = t.institution_id where t.is_active and t.starts_on <= p_to_date and (t.ends_on is null or t.ends_on >= p_from_date) loop
    institution_timezone := coalesce(template.timezone, 'UTC');
    for occurrence in select generate_series(greatest(p_from_date, template.starts_on), least(p_to_date, coalesce(template.ends_on, p_to_date)), interval '1 day')::date loop
      is_due := case
        when template.recurrence = 'daily' then true
        when template.recurrence = 'weekly' then ((((extract(dow from occurrence)::integer + 1) % 7) + 1) = template.week_day)
        when template.recurrence = 'monthly' then extract(day from occurrence)::integer = template.month_day
        else false
      end;
      if not is_due then continue; end if;

      run_id := null;
      insert into public.task_runs (institution_id, template_id, scheduled_for, status)
      values (template.institution_id, template.id, occurrence, 'started')
      on conflict (institution_id, template_id, scheduled_for) do nothing
      returning id into run_id;
      if run_id is null then continue; end if;

      begin
        insert into public.tasks (institution_id, branch_id, created_by, assignee_employee_id, title, description, starts_at, due_at, priority, proof_required, recurring_template_id, idempotency_key)
        values (template.institution_id, template.branch_id, template.created_by, template.assignee_employee_id, template.title, template.description, occurrence::timestamp at time zone institution_timezone, ((occurrence + 1)::timestamp at time zone institution_timezone) - interval '1 second', 'normal', false, template.id, 'recurring:' || template.id::text || ':' || occurrence::text)
        on conflict (institution_id, idempotency_key) do nothing;
        update public.task_runs set status = 'completed', completed_at = now() where id = run_id;
        generated_count := generated_count + 1;
      exception when others then
        update public.task_runs set status = 'failed', error_message = sqlerrm, completed_at = now() where id = run_id;
      end;
    end loop;
    update public.recurring_task_templates set last_generated_for = greatest(coalesce(last_generated_for, p_from_date - 1), p_to_date) where id = template.id;
  end loop;
  return generated_count;
end;
$$;

revoke all on function app.record_task_update(uuid, uuid, public.task_status, text) from public, anon, authenticated;
revoke all on function app.review_task(uuid, uuid, public.task_status, text) from public, anon, authenticated;
revoke all on function app.generate_recurring_tasks(date, date) from public, anon, authenticated;
grant execute on function app.record_task_update(uuid, uuid, public.task_status, text) to service_role;
grant execute on function app.review_task(uuid, uuid, public.task_status, text) to service_role;
grant execute on function app.generate_recurring_tasks(date, date) to service_role;
