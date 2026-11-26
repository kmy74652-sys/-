-- Production repair: some environments retained the snapshot table after the
-- legacy task designer was removed, but later RPCs still insert this column.
alter table public.task_report_form_snapshots
  add column if not exists task_report_form_id uuid;

create index if not exists task_report_form_snapshots_form_idx
  on public.task_report_form_snapshots(task_report_form_id);
