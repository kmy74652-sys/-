create or replace function app.create_customer_with_account(
  p_institution_id uuid,
  p_branch_id uuid,
  p_code text,
  p_name text,
  p_phone text default null,
  p_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  customer_id uuid;
begin
  insert into public.customers (institution_id, branch_id, code, name, phone, address)
  values (p_institution_id, p_branch_id, trim(p_code), trim(p_name), nullif(trim(p_phone), ''), nullif(trim(p_address), ''))
  returning id into customer_id;
  insert into public.accounts (institution_id, code, name, account_type, customer_id)
  values (p_institution_id, 'CUS-' || upper(trim(p_code)), trim(p_name), 'customer', customer_id);
  return customer_id;
exception when unique_violation then
  raise exception 'customer_code_or_account_exists';
end;
$$;

create or replace function app.approve_credit_limit(
  p_credit_limit_id uuid,
  p_approver_employee_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  proposal public.credit_limits%rowtype;
begin
  select * into proposal from public.credit_limits where id = p_credit_limit_id for update;
  if not found then raise exception 'credit_limit_not_found'; end if;
  if proposal.approved_by is not null then raise exception 'credit_limit_already_approved'; end if;
  if proposal.proposed_by = p_approver_employee_id then raise exception 'credit_limit_approver_not_independent'; end if;
  update public.credit_limits set approved_by = p_approver_employee_id, approved_at = now() where id = p_credit_limit_id;
  return p_credit_limit_id;
end;
$$;

create or replace function app.approve_receipt(
  p_receipt_id uuid,
  p_approver_employee_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  receipt public.receipts%rowtype;
  ledger_key text;
begin
  select * into receipt from public.receipts where id = p_receipt_id for update;
  if not found then raise exception 'receipt_not_found'; end if;
  if receipt.status <> 'submitted' then raise exception 'receipt_must_be_submitted'; end if;
  if receipt.created_by = p_approver_employee_id then raise exception 'receipt_approver_not_independent'; end if;
  ledger_key := 'receipt:' || receipt.id::text;
  insert into public.account_ledger_entries (institution_id, account_id, amount, entry_type, source_type, source_id, idempotency_key, created_by)
  values (receipt.institution_id, receipt.account_id, receipt.amount, 'credit', 'receipt', receipt.id, ledger_key, p_approver_employee_id)
  on conflict (institution_id, idempotency_key) do nothing;
  update public.receipts set status = 'approved', approved_by = p_approver_employee_id, approved_at = now() where id = receipt.id;
  return receipt.id;
end;
$$;

revoke all on function app.create_customer_with_account(uuid, uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function app.approve_credit_limit(uuid, uuid) from public, anon, authenticated;
revoke all on function app.approve_receipt(uuid, uuid) from public, anon, authenticated;
grant execute on function app.create_customer_with_account(uuid, uuid, text, text, text, text) to service_role;
grant execute on function app.approve_credit_limit(uuid, uuid) to service_role;
grant execute on function app.approve_receipt(uuid, uuid) to service_role;

drop policy if exists customers_manage on public.customers;
create policy customers_manage on public.customers for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('customers.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('customers.manage'));
drop policy if exists accounts_read on public.accounts;
create policy accounts_read on public.accounts for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('finance.read'));
drop policy if exists credit_limits_read on public.credit_limits;
create policy credit_limits_read on public.credit_limits for select to authenticated
using (institution_id = app.current_institution_id() and (app.has_permission('finance.read') or app.has_permission('credit_limits.propose') or app.has_permission('credit_limits.approve')));
drop policy if exists credit_limits_propose on public.credit_limits;
create policy credit_limits_propose on public.credit_limits for insert to authenticated
with check (institution_id = app.current_institution_id() and proposed_by = app.current_employee_id() and app.has_permission('credit_limits.propose'));
drop policy if exists receipts_create on public.receipts;
create policy receipts_create on public.receipts for insert to authenticated
with check (institution_id = app.current_institution_id() and created_by = app.current_employee_id() and app.has_permission('finance.receipts.create'));
drop policy if exists receipts_approve on public.receipts;
create policy receipts_approve on public.receipts for update to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('finance.receipts.approve'))
with check (institution_id = app.current_institution_id() and app.has_permission('finance.receipts.approve'));
drop policy if exists ledger_insert on public.account_ledger_entries;
create policy ledger_insert on public.account_ledger_entries for insert to authenticated
with check (institution_id = app.current_institution_id() and app.has_permission('finance.receipts.approve'));
