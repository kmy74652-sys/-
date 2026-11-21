-- Apply least-privilege table grants to the isolated report workflow.
-- RLS controls which rows authenticated users can access; SQL grants control
-- which operations are available at all. In particular, TRUNCATE bypasses RLS.
revoke all on table public.report_submissions from anon, authenticated;
grant select, insert, update on table public.report_submissions to authenticated;
