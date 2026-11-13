create or replace function app.current_employee_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth, app
as $$
  select e.id
  from public.employees e
  where e.auth_user_id = auth.uid()
    and e.status = 'active'
  limit 1;
$$;

create or replace function app.current_institution_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth, app
as $$
  select e.institution_id
  from public.employees e
  where e.auth_user_id = auth.uid()
    and e.status = 'active'
  limit 1;
$$;

create or replace function app.has_permission(required_permission text)
returns boolean
language sql
stable
security definer
set search_path = public, auth, app
as $$
  select exists (
    select 1
    from public.employee_roles er
    join public.roles r on r.id = er.role_id and r.institution_id = er.institution_id
    join public.role_permissions rp on rp.role_id = r.id and rp.institution_id = r.institution_id
    where er.employee_id = app.current_employee_id()
      and er.institution_id = app.current_institution_id()
      and rp.permission_code = required_permission
  )
  or exists (
    select 1
    from public.employee_permission_overrides eo
    where eo.employee_id = app.current_employee_id()
      and eo.institution_id = app.current_institution_id()
      and eo.permission_code = required_permission
      and eo.allowed
  );
$$;

create or replace function app.has_branch_access(target_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth, app
as $$
  select exists (
    select 1
    from public.employee_branches eb
    where eb.institution_id = app.current_institution_id()
      and eb.employee_id = app.current_employee_id()
      and eb.branch_id = target_branch_id
  ) or app.has_permission('branches.read_all');
$$;

create or replace function app.prevent_audit_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_logs_are_append_only';
end;
$$;

alter table public.institutions enable row level security;
alter table public.branches enable row level security;
alter table public.employees enable row level security;
alter table public.employee_branches enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.employee_roles enable row level security;
alter table public.employee_permission_overrides enable row level security;
alter table public.tasks enable row level security;
alter table public.task_updates enable row level security;
alter table public.task_reviews enable row level security;
alter table public.recurring_task_templates enable row level security;
alter table public.task_runs enable row level security;
alter table public.attachments enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.units enable row level security;
alter table public.products enable row level security;
alter table public.warehouses enable row level security;
alter table public.accounts enable row level security;
alter table public.credit_limits enable row level security;
alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_items enable row level security;
alter table public.purchase_invoices enable row level security;
alter table public.purchase_invoice_items enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.inventory_transaction_items enable row level security;
alter table public.stocktakes enable row level security;
alter table public.stocktake_items enable row level security;
alter table public.account_ledger_entries enable row level security;
alter table public.receipts enable row level security;
alter table public.payments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.notifications enable row level security;
alter table public.operation_idempotency_keys enable row level security;

create policy institutions_read on public.institutions for select to authenticated
using (id = app.current_institution_id());
create policy institutions_update on public.institutions for update to authenticated
using (id = app.current_institution_id() and app.has_permission('institutions.update'))
with check (id = app.current_institution_id() and app.has_permission('institutions.update'));

create policy branches_read on public.branches for select to authenticated
using (institution_id = app.current_institution_id() and (app.has_permission('branches.read_all') or app.has_branch_access(id)));
create policy branches_write on public.branches for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('branches.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('branches.manage'));

create policy employees_read on public.employees for select to authenticated
using (institution_id = app.current_institution_id() and (id = app.current_employee_id() or app.has_permission('employees.read')));
create policy employees_manage on public.employees for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('employees.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('employees.manage'));

create policy employee_branches_read on public.employee_branches for select to authenticated
using (institution_id = app.current_institution_id() and (employee_id = app.current_employee_id() or app.has_permission('employees.read')));
create policy employee_branches_manage on public.employee_branches for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('employees.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('employees.manage'));

create policy roles_read on public.roles for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('roles.read'));
create policy roles_manage on public.roles for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('roles.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('roles.manage'));
create policy permissions_read on public.permissions for select to authenticated
using (app.has_permission('roles.read'));
create policy role_permissions_read on public.role_permissions for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('roles.read'));
create policy role_permissions_manage on public.role_permissions for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('roles.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('roles.manage'));
create policy employee_roles_read on public.employee_roles for select to authenticated
using (institution_id = app.current_institution_id() and (employee_id = app.current_employee_id() or app.has_permission('roles.read')));
create policy employee_roles_manage on public.employee_roles for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('roles.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('roles.manage'));

create policy tasks_read on public.tasks for select to authenticated
using (institution_id = app.current_institution_id() and (assignee_employee_id = app.current_employee_id() or created_by = app.current_employee_id() or app.has_permission('tasks.read_all')));
create policy tasks_write on public.tasks for all to authenticated
using (institution_id = app.current_institution_id() and (created_by = app.current_employee_id() or app.has_permission('tasks.manage')))
with check (institution_id = app.current_institution_id() and (created_by = app.current_employee_id() or app.has_permission('tasks.manage')));
create policy task_updates_read on public.task_updates for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('tasks.read'));
create policy task_updates_insert on public.task_updates for insert to authenticated
with check (institution_id = app.current_institution_id() and author_employee_id = app.current_employee_id());
create policy task_reviews_read on public.task_reviews for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('tasks.review'));
create policy task_reviews_insert on public.task_reviews for insert to authenticated
with check (institution_id = app.current_institution_id() and reviewer_employee_id = app.current_employee_id() and app.has_permission('tasks.review'));

create policy recurring_templates_read on public.recurring_task_templates for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('tasks.read'));
create policy recurring_templates_manage on public.recurring_task_templates for all to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('tasks.manage'))
with check (institution_id = app.current_institution_id() and app.has_permission('tasks.manage'));
create policy task_runs_read on public.task_runs for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('tasks.read'));

create policy audit_logs_read on public.audit_logs for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('audit.read'));
create policy audit_logs_insert on public.audit_logs for insert to authenticated
with check (institution_id = app.current_institution_id() and app.has_permission('audit.write'));
create trigger audit_logs_append_only_update before update on public.audit_logs
for each row execute function app.prevent_audit_mutation();
create trigger audit_logs_append_only_delete before delete on public.audit_logs
for each row execute function app.prevent_audit_mutation();

create policy notifications_read on public.notifications for select to authenticated
using (institution_id = app.current_institution_id() and (employee_id = app.current_employee_id() or app.has_permission('notifications.read_all')));
create policy notifications_update on public.notifications for update to authenticated
using (institution_id = app.current_institution_id() and employee_id = app.current_employee_id())
with check (institution_id = app.current_institution_id() and employee_id = app.current_employee_id());

create policy attachments_read on public.attachments for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('attachments.read'));
create policy attachments_insert on public.attachments for insert to authenticated
with check (institution_id = app.current_institution_id() and uploaded_by = app.current_employee_id());

-- Domain policies: access is narrowed by institution first; granular approval is enforced by API functions.
create policy customers_read on public.customers for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('customers.read'));
create policy suppliers_read on public.suppliers for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('suppliers.read'));
create policy products_read on public.products for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.read'));
create policy warehouses_read on public.warehouses for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.read'));
create policy sales_invoices_read on public.sales_invoices for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('sales.read'));
create policy purchase_invoices_read on public.purchase_invoices for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('purchases.read'));
create policy inventory_transactions_read on public.inventory_transactions for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.read'));
create policy stocktakes_read on public.stocktakes for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('inventory.read'));
create policy ledger_read on public.account_ledger_entries for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('finance.read'));
create policy receipts_read on public.receipts for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('finance.read'));
create policy payments_read on public.payments for select to authenticated
using (institution_id = app.current_institution_id() and app.has_permission('finance.read'));

revoke all on schema app from public;
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
