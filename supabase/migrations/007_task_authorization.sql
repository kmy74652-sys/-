drop policy if exists task_updates_insert on public.task_updates;
create policy task_updates_insert on public.task_updates for insert to authenticated
with check (
  institution_id = app.current_institution_id()
  and author_employee_id = app.current_employee_id()
  and exists (
    select 1
    from public.tasks t
    where t.institution_id = task_updates.institution_id
      and t.id = task_updates.task_id
      and (
        t.assignee_employee_id = app.current_employee_id()
        or t.created_by = app.current_employee_id()
        or app.has_permission('tasks.manage')
      )
  )
);

drop policy if exists task_reviews_insert on public.task_reviews;
create policy task_reviews_insert on public.task_reviews for insert to authenticated
with check (
  institution_id = app.current_institution_id()
  and reviewer_employee_id = app.current_employee_id()
  and app.has_permission('tasks.review')
  and exists (
    select 1
    from public.tasks t
    where t.institution_id = task_reviews.institution_id
      and t.id = task_reviews.task_id
      and t.status = 'submitted'
      and t.assignee_employee_id <> app.current_employee_id()
      and t.created_by <> app.current_employee_id()
  )
);
