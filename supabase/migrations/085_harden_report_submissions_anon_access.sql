-- Restrict the report submission workflow to authenticated application users.
-- RLS policies already scope row access; remove the broader table/function grants
-- that could otherwise expose unnecessary API surface to anonymous clients.
revoke all on table public.report_submissions from anon;

-- Trigger functions are invoked by PostgreSQL triggers, not by client RPC calls.
-- Keep authenticated execution compatibility while preventing anonymous/public RPC access.
revoke execute on function public.prepare_report_submission() from public, anon;
