-- Report drafts contain employee-entered values and must never be exposed
-- through a table-level authenticated grant without row-level filtering.
alter table public.task_report_drafts enable row level security;
