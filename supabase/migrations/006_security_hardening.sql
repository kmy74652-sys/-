create or replace function app.has_permission(required_permission text)
returns boolean
language sql
stable
security definer
set search_path = public, auth, app
as $$
  select coalesce(
    (
      select eo.allowed
      from public.employee_permission_overrides eo
      where eo.employee_id = app.current_employee_id()
        and eo.institution_id = app.current_institution_id()
        and eo.permission_code = required_permission
    ),
    exists (
      select 1
      from public.employee_roles er
      join public.roles r on r.id = er.role_id and r.institution_id = er.institution_id
      join public.role_permissions rp on rp.role_id = r.id and rp.institution_id = r.institution_id
      where er.employee_id = app.current_employee_id()
        and er.institution_id = app.current_institution_id()
        and rp.permission_code = required_permission
    )
  );
$$;

drop policy if exists tasks_write on public.tasks;
create policy tasks_insert on public.tasks for insert to authenticated
with check (
  institution_id = app.current_institution_id()
  and (created_by = app.current_employee_id() or app.has_permission('tasks.manage'))
);
create policy tasks_update on public.tasks for update to authenticated
using (
  institution_id = app.current_institution_id()
  and (created_by = app.current_employee_id() or app.has_permission('tasks.manage'))
)
with check (
  institution_id = app.current_institution_id()
  and (created_by = app.current_employee_id() or app.has_permission('tasks.manage'))
);

create policy employee_permission_overrides_read on public.employee_permission_overrides for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('roles.read'));
create policy employee_permission_overrides_manage on public.employee_permission_overrides for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('roles.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('roles.manage'));

create policy customers_manage on public.customers for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('customers.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('customers.manage'));
create policy suppliers_manage on public.suppliers for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('suppliers.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('suppliers.manage'));

create policy units_read on public.units for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.read'));
create policy units_manage on public.units for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.read'))
with check (institution_id = app.current_institution_id() and app.has_permission('inventory.read'));
create policy accounts_read on public.accounts for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('finance.read'));
create policy credit_limits_read on public.credit_limits for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('finance.read'));
create policy credit_limits_propose on public.credit_limits for insert to authenticated
with check (institution_id = app.current_institution_id() and proposed_by = app.current_employee_id() and app.has_permission('credit_limits.propose'));
create policy credit_limits_approve on public.credit_limits for update to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('credit_limits.approve'))
with check (institution_id = app.current_institution_id() and app.has_permission('credit_limits.approve'));

create policy sales_invoice_items_read on public.sales_invoice_items for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('sales.read'));
create policy sales_invoice_items_manage on public.sales_invoice_items for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('sales.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('sales.manage'));
create policy purchase_invoice_items_read on public.purchase_invoice_items for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('purchases.read'));
create policy purchase_invoice_items_manage on public.purchase_invoice_items for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('purchases.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('purchases.manage'));

create policy inventory_transaction_items_read on public.inventory_transaction_items for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.read'));
create policy inventory_transaction_items_insert on public.inventory_transaction_items for insert to authenticated
with check (institution_id = app.current_institution_id() and app.has_permission('inventory.receive'));
create policy stocktake_items_read on public.stocktake_items for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.read'));
create policy stocktake_items_insert on public.stocktake_items for insert to authenticated
with check (institution_id = app.current_institution_id() and app.has_permission('inventory.stocktake'));
create policy stocktake_items_update on public.stocktake_items for update to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.stocktake'))
with check (institution_id = app.current_institution_id() and app.has_permission('inventory.stocktake'));

create policy sales_invoices_manage on public.sales_invoices for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('sales.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('sales.manage'));
create policy purchase_invoices_manage on public.purchase_invoices for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('purchases.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('purchases.manage'));
create policy inventory_transactions_insert on public.inventory_transactions for insert to authenticated
with check (institution_id = app.current_institution_id() and (app.has_permission('inventory.receive') or app.has_permission('inventory.issue')));
create policy stocktakes_manage on public.stocktakes for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.stocktake'))
with check (institution_id = app.current_institution_id() and app.has_permission('inventory.stocktake'));
create policy receipts_manage on public.receipts for all to authenticated
using (institution_id = app.current_institution_id() and (app.has_permission('finance.receipts.create') or app.has_permission('finance.receipts.approve')))
with check (institution_id = app.current_institution_id() and (app.has_permission('finance.receipts.create') or app.has_permission('finance.receipts.approve')));
create policy payments_manage on public.payments for all to authenticated
using (institution_id = app.current_institution_id() and (app.has_permission('finance.payments.create') or app.has_permission('finance.payments.approve')))
with check (institution_id = app.current_institution_id() and (app.has_permission('finance.payments.create') or app.has_permission('finance.payments.approve')));
