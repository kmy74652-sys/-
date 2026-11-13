create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid,
  code text not null,
  name text not null,
  phone text,
  address text,
  credit_limit numeric(18,3) not null default 0 check (credit_limit >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id),
  foreign key (institution_id, branch_id) references public.branches(institution_id, id)
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid,
  code text not null,
  name text not null,
  phone text,
  address text,
  payment_terms_days integer not null default 0 check (payment_terms_days >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id),
  foreign key (institution_id, branch_id) references public.branches(institution_id, id)
);

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  code text not null,
  name text not null,
  conversion_to_base numeric(18,6) not null default 1 check (conversion_to_base > 0),
  created_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id)
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  sku text not null,
  name text not null,
  base_unit_id uuid not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, sku),
  unique (institution_id, id),
  foreign key (institution_id, base_unit_id) references public.units(institution_id, id)
);

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid not null,
  code text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id),
  foreign key (institution_id, branch_id) references public.branches(institution_id, id)
);

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  code text not null,
  name text not null,
  account_type text not null check (account_type in ('customer', 'supplier', 'cash', 'bank', 'income', 'expense', 'inventory', 'other')),
  customer_id uuid,
  supplier_id uuid,
  created_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id),
  unique (institution_id, customer_id),
  unique (institution_id, supplier_id),
  foreign key (institution_id, customer_id) references public.customers(institution_id, id),
  foreign key (institution_id, supplier_id) references public.suppliers(institution_id, id),
  check ((account_type = 'customer' and customer_id is not null and supplier_id is null) or
         (account_type = 'supplier' and supplier_id is not null and customer_id is null) or
         (account_type not in ('customer', 'supplier') and customer_id is null and supplier_id is null))
);

create table if not exists public.credit_limits (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  customer_id uuid not null,
  amount numeric(18,3) not null check (amount >= 0),
  valid_from date not null,
  valid_to date,
  proposed_by uuid not null,
  approved_by uuid,
  approved_at timestamptz,
  reason text not null,
  created_at timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from),
  foreign key (institution_id, customer_id) references public.customers(institution_id, id),
  foreign key (institution_id, proposed_by) references public.employees(institution_id, id),
  foreign key (institution_id, approved_by) references public.employees(institution_id, id)
);

create table if not exists public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid not null,
  customer_id uuid not null,
  invoice_no text not null,
  status public.document_status not null default 'draft',
  invoice_date date not null default current_date,
  subtotal numeric(18,3) not null default 0 check (subtotal >= 0),
  discount numeric(18,3) not null default 0 check (discount >= 0),
  total numeric(18,3) not null default 0 check (total >= 0),
  created_by uuid not null,
  approved_by uuid,
  approved_at timestamptz,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, invoice_no),
  unique (institution_id, idempotency_key),
  foreign key (institution_id, branch_id) references public.branches(institution_id, id),
  foreign key (institution_id, customer_id) references public.customers(institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  foreign key (institution_id, approved_by) references public.employees(institution_id, id),
  unique (institution_id, id)
);

create table if not exists public.sales_invoice_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  invoice_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  quantity numeric(18,6) not null check (quantity > 0),
  unit_price numeric(18,3) not null check (unit_price >= 0),
  discount numeric(18,3) not null default 0 check (discount >= 0),
  line_total numeric(18,3) not null check (line_total >= 0),
  foreign key (institution_id, invoice_id) references public.sales_invoices(institution_id, id) on delete cascade,
  foreign key (institution_id, product_id) references public.products(institution_id, id),
  foreign key (institution_id, unit_id) references public.units(institution_id, id)
);

create table if not exists public.purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid not null,
  supplier_id uuid not null,
  invoice_no text not null,
  status public.document_status not null default 'draft',
  invoice_date date not null default current_date,
  subtotal numeric(18,3) not null default 0 check (subtotal >= 0),
  discount numeric(18,3) not null default 0 check (discount >= 0),
  total numeric(18,3) not null default 0 check (total >= 0),
  created_by uuid not null,
  approved_by uuid,
  approved_at timestamptz,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, invoice_no),
  unique (institution_id, idempotency_key),
  foreign key (institution_id, branch_id) references public.branches(institution_id, id),
  foreign key (institution_id, supplier_id) references public.suppliers(institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  foreign key (institution_id, approved_by) references public.employees(institution_id, id),
  unique (institution_id, id)
);

create table if not exists public.purchase_invoice_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  invoice_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  quantity numeric(18,6) not null check (quantity > 0),
  unit_price numeric(18,3) not null check (unit_price >= 0),
  discount numeric(18,3) not null default 0 check (discount >= 0),
  line_total numeric(18,3) not null check (line_total >= 0),
  foreign key (institution_id, invoice_id) references public.purchase_invoices(institution_id, id) on delete cascade,
  foreign key (institution_id, product_id) references public.products(institution_id, id),
  foreign key (institution_id, unit_id) references public.units(institution_id, id)
);

create table if not exists public.inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  warehouse_id uuid not null,
  transaction_type public.inventory_transaction_type not null,
  source_type text,
  source_id uuid,
  transaction_date timestamptz not null default now(),
  created_by uuid not null,
  idempotency_key text not null,
  notes text,
  created_at timestamptz not null default now(),
  unique (institution_id, idempotency_key),
  foreign key (institution_id, warehouse_id) references public.warehouses(institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  unique (institution_id, id)
);

create table if not exists public.inventory_transaction_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  transaction_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  quantity numeric(18,6) not null check (quantity > 0),
  unit_cost numeric(18,3) not null default 0 check (unit_cost >= 0),
  foreign key (institution_id, transaction_id) references public.inventory_transactions(institution_id, id) on delete cascade,
  foreign key (institution_id, product_id) references public.products(institution_id, id),
  foreign key (institution_id, unit_id) references public.units(institution_id, id)
);

create table if not exists public.stocktakes (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  warehouse_id uuid not null,
  status public.document_status not null default 'draft',
  counted_at timestamptz,
  created_by uuid not null,
  approved_by uuid,
  created_at timestamptz not null default now(),
  foreign key (institution_id, warehouse_id) references public.warehouses(institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  foreign key (institution_id, approved_by) references public.employees(institution_id, id),
  unique (institution_id, id)
);

create table if not exists public.stocktake_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  stocktake_id uuid not null,
  product_id uuid not null,
  book_quantity numeric(18,6) not null check (book_quantity >= 0),
  counted_quantity numeric(18,6) not null check (counted_quantity >= 0),
  difference numeric(18,6) generated always as (counted_quantity - book_quantity) stored,
  foreign key (institution_id, stocktake_id) references public.stocktakes(institution_id, id) on delete cascade,
  foreign key (institution_id, product_id) references public.products(institution_id, id)
);

create table if not exists public.account_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  account_id uuid not null,
  amount numeric(18,3) not null check (amount <> 0),
  entry_type text not null check (entry_type in ('debit', 'credit')),
  source_type text not null,
  source_id uuid not null,
  idempotency_key text not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique (institution_id, idempotency_key),
  foreign key (institution_id, account_id) references public.accounts(institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id)
);

create table if not exists public.receipts (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid not null,
  customer_id uuid,
  account_id uuid not null,
  amount numeric(18,3) not null check (amount > 0),
  receipt_no text not null,
  status public.document_status not null default 'draft',
  created_by uuid not null,
  approved_by uuid,
  idempotency_key text,
  created_at timestamptz not null default now(),
  unique (institution_id, receipt_no),
  unique (institution_id, idempotency_key),
  foreign key (institution_id, branch_id) references public.branches(institution_id, id),
  foreign key (institution_id, customer_id) references public.customers(institution_id, id),
  foreign key (institution_id, account_id) references public.accounts(institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  foreign key (institution_id, approved_by) references public.employees(institution_id, id)
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  branch_id uuid not null,
  supplier_id uuid,
  account_id uuid not null,
  amount numeric(18,3) not null check (amount > 0),
  payment_no text not null,
  status public.document_status not null default 'draft',
  created_by uuid not null,
  approved_by uuid,
  idempotency_key text,
  created_at timestamptz not null default now(),
  unique (institution_id, payment_no),
  unique (institution_id, idempotency_key),
  foreign key (institution_id, branch_id) references public.branches(institution_id, id),
  foreign key (institution_id, supplier_id) references public.suppliers(institution_id, id),
  foreign key (institution_id, account_id) references public.accounts(institution_id, id),
  foreign key (institution_id, created_by) references public.employees(institution_id, id),
  foreign key (institution_id, approved_by) references public.employees(institution_id, id)
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  actor_employee_id uuid,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  request_id text,
  ip_address inet,
  created_at timestamptz not null default now(),
  foreign key (institution_id, actor_employee_id) references public.employees(institution_id, id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  employee_id uuid not null,
  title text not null,
  body text not null,
  severity text not null default 'info' check (severity in ('info', 'success', 'warning', 'error')),
  read_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (institution_id, employee_id) references public.employees(institution_id, id) on delete cascade
);

create table if not exists public.operation_idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  operation_name text not null,
  key text not null,
  response jsonb,
  created_at timestamptz not null default now(),
  unique (institution_id, operation_name, key)
);

create index if not exists branches_institution_active_idx on public.branches (institution_id, is_active);
create index if not exists employees_institution_status_idx on public.employees (institution_id, status);
create index if not exists tasks_assignee_status_due_idx on public.tasks (institution_id, assignee_employee_id, status, due_at);
create index if not exists tasks_branch_status_idx on public.tasks (institution_id, branch_id, status);
create index if not exists ledger_account_date_idx on public.account_ledger_entries (institution_id, account_id, created_at);
create index if not exists inventory_warehouse_product_idx on public.inventory_transaction_items (institution_id, product_id);
create index if not exists audit_entity_date_idx on public.audit_logs (institution_id, entity_type, entity_id, created_at);
create index if not exists notifications_employee_unread_idx on public.notifications (institution_id, employee_id, read_at);

create trigger customers_set_updated_at before update on public.customers
for each row execute function app.set_updated_at();
create trigger suppliers_set_updated_at before update on public.suppliers
for each row execute function app.set_updated_at();
create trigger products_set_updated_at before update on public.products
for each row execute function app.set_updated_at();
create trigger sales_invoices_set_updated_at before update on public.sales_invoices
for each row execute function app.set_updated_at();
create trigger purchase_invoices_set_updated_at before update on public.purchase_invoices
for each row execute function app.set_updated_at();
