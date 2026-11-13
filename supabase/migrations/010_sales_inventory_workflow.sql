create or replace function app.create_sales_invoice_with_items(
  p_institution_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_invoice_no text,
  p_created_by uuid,
  p_items jsonb,
  p_discount numeric default 0,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  invoice_id uuid;
  row_item jsonb;
  line_total numeric;
  subtotal numeric := 0;
  quantity numeric;
  unit_price numeric;
  item_discount numeric;
  product_id uuid;
  unit_id uuid;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'invoice_items_required'; end if;
  if p_discount < 0 then raise exception 'invalid_discount'; end if;
  if not exists (select 1 from public.branches where institution_id = p_institution_id and id = p_branch_id and is_active) then raise exception 'branch_not_found'; end if;
  if not exists (select 1 from public.customers where institution_id = p_institution_id and id = p_customer_id and is_active) then raise exception 'customer_not_found'; end if;
  insert into public.sales_invoices (institution_id, branch_id, customer_id, invoice_no, status, subtotal, discount, total, created_by, idempotency_key)
  values (p_institution_id, p_branch_id, p_customer_id, trim(p_invoice_no), 'submitted', 0, p_discount, 0, p_created_by, coalesce(p_idempotency_key, gen_random_uuid()::text))
  on conflict (institution_id, idempotency_key) do nothing
  returning id into invoice_id;
  if invoice_id is null then
    select id into invoice_id from public.sales_invoices where institution_id = p_institution_id and idempotency_key = p_idempotency_key;
    return invoice_id;
  end if;
  for row_item in select * from jsonb_array_elements(p_items) loop
    product_id := (row_item->>'productId')::uuid;
    unit_id := (row_item->>'unitId')::uuid;
    quantity := (row_item->>'quantity')::numeric;
    unit_price := (row_item->>'unitPrice')::numeric;
    item_discount := coalesce((row_item->>'discount')::numeric, 0);
    if quantity <= 0 or unit_price < 0 or item_discount < 0 then raise exception 'invalid_invoice_item'; end if;
    if not exists (select 1 from public.products where institution_id = p_institution_id and id = product_id and is_active) then raise exception 'product_not_found'; end if;
    if not exists (select 1 from public.units where institution_id = p_institution_id and id = unit_id) then raise exception 'unit_not_found'; end if;
    line_total := greatest((quantity * unit_price) - item_discount, 0);
    subtotal := subtotal + line_total;
    insert into public.sales_invoice_items (institution_id, invoice_id, product_id, unit_id, quantity, unit_price, discount, line_total)
    values (p_institution_id, invoice_id, product_id, unit_id, quantity, unit_price, item_discount, line_total);
  end loop;
  update public.sales_invoices set subtotal = subtotal, total = greatest(subtotal - p_discount, 0) where id = invoice_id;
  return invoice_id;
exception when unique_violation then
  raise exception 'invoice_number_exists';
end;
$$;

create or replace function app.create_purchase_invoice_with_items(
  p_institution_id uuid,
  p_branch_id uuid,
  p_supplier_id uuid,
  p_invoice_no text,
  p_created_by uuid,
  p_items jsonb,
  p_discount numeric default 0,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  invoice_id uuid;
  row_item jsonb;
  line_total numeric;
  subtotal numeric := 0;
  quantity numeric;
  unit_price numeric;
  item_discount numeric;
  product_id uuid;
  unit_id uuid;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'invoice_items_required'; end if;
  if p_discount < 0 then raise exception 'invalid_discount'; end if;
  if not exists (select 1 from public.branches where institution_id = p_institution_id and id = p_branch_id and is_active) then raise exception 'branch_not_found'; end if;
  if not exists (select 1 from public.suppliers where institution_id = p_institution_id and id = p_supplier_id and is_active) then raise exception 'supplier_not_found'; end if;
  insert into public.purchase_invoices (institution_id, branch_id, supplier_id, invoice_no, status, subtotal, discount, total, created_by, idempotency_key)
  values (p_institution_id, p_branch_id, p_supplier_id, trim(p_invoice_no), 'submitted', 0, p_discount, 0, p_created_by, coalesce(p_idempotency_key, gen_random_uuid()::text))
  on conflict (institution_id, idempotency_key) do nothing
  returning id into invoice_id;
  if invoice_id is null then
    select id into invoice_id from public.purchase_invoices where institution_id = p_institution_id and idempotency_key = p_idempotency_key;
    return invoice_id;
  end if;
  for row_item in select * from jsonb_array_elements(p_items) loop
    product_id := (row_item->>'productId')::uuid;
    unit_id := (row_item->>'unitId')::uuid;
    quantity := (row_item->>'quantity')::numeric;
    unit_price := (row_item->>'unitPrice')::numeric;
    item_discount := coalesce((row_item->>'discount')::numeric, 0);
    if quantity <= 0 or unit_price < 0 or item_discount < 0 then raise exception 'invalid_invoice_item'; end if;
    if not exists (select 1 from public.products where institution_id = p_institution_id and id = product_id and is_active) then raise exception 'product_not_found'; end if;
    if not exists (select 1 from public.units where institution_id = p_institution_id and id = unit_id) then raise exception 'unit_not_found'; end if;
    line_total := greatest((quantity * unit_price) - item_discount, 0);
    subtotal := subtotal + line_total;
    insert into public.purchase_invoice_items (institution_id, invoice_id, product_id, unit_id, quantity, unit_price, discount, line_total)
    values (p_institution_id, invoice_id, product_id, unit_id, quantity, unit_price, item_discount, line_total);
  end loop;
  update public.purchase_invoices set subtotal = subtotal, total = greatest(subtotal - p_discount, 0) where id = invoice_id;
  return invoice_id;
exception when unique_violation then
  raise exception 'invoice_number_exists';
end;
$$;

create or replace function app.approve_purchase_invoice(p_invoice_id uuid, p_warehouse_id uuid, p_approver_employee_id uuid)
returns uuid language plpgsql security definer set search_path = public, app as $$
declare
  invoice public.purchase_invoices%rowtype;
  transaction_id uuid;
begin
  select * into invoice from public.purchase_invoices where id = p_invoice_id for update;
  if not found then raise exception 'purchase_invoice_not_found'; end if;
  if invoice.status <> 'submitted' then raise exception 'invoice_must_be_submitted'; end if;
  if invoice.created_by = p_approver_employee_id then raise exception 'invoice_approver_not_independent'; end if;
  if not exists (select 1 from public.warehouses where institution_id = invoice.institution_id and id = p_warehouse_id and is_active) then raise exception 'warehouse_not_found'; end if;
  insert into public.inventory_transactions (institution_id, warehouse_id, transaction_type, source_type, source_id, created_by, idempotency_key, notes)
  values (invoice.institution_id, p_warehouse_id, 'purchase_receipt', 'purchase_invoice', invoice.id, p_approver_employee_id, 'purchase-invoice:' || invoice.id, 'استلام مرتبط بفاتورة شراء')
  on conflict (institution_id, idempotency_key) do nothing returning id into transaction_id;
  if transaction_id is not null then
    insert into public.inventory_transaction_items (institution_id, transaction_id, product_id, unit_id, quantity, unit_cost)
    select institution_id, transaction_id, product_id, unit_id, quantity, unit_price from public.purchase_invoice_items where institution_id = invoice.institution_id and invoice_id = invoice.id;
  else
    select id into transaction_id from public.inventory_transactions where institution_id = invoice.institution_id and idempotency_key = 'purchase-invoice:' || invoice.id;
  end if;
  update public.purchase_invoices set status = 'approved', approved_by = p_approver_employee_id, approved_at = now() where id = invoice.id;
  return invoice.id;
end; $$;

create or replace function app.approve_sales_invoice(p_invoice_id uuid, p_warehouse_id uuid, p_approver_employee_id uuid)
returns uuid language plpgsql security definer set search_path = public, app as $$
declare
  invoice public.sales_invoices%rowtype;
  transaction_id uuid;
  row_item record;
  available numeric;
  signed_quantity numeric;
begin
  select * into invoice from public.sales_invoices where id = p_invoice_id for update;
  if not found then raise exception 'sales_invoice_not_found'; end if;
  if invoice.status <> 'submitted' then raise exception 'invoice_must_be_submitted'; end if;
  if invoice.created_by = p_approver_employee_id then raise exception 'invoice_approver_not_independent'; end if;
  if not exists (select 1 from public.warehouses where institution_id = invoice.institution_id and id = p_warehouse_id and is_active) then raise exception 'warehouse_not_found'; end if;
  for row_item in select product_id, unit_id, quantity from public.sales_invoice_items where institution_id = invoice.institution_id and invoice_id = invoice.id loop
    select coalesce(sum(case when it.transaction_type in ('purchase_receipt','sales_return','transfer_in','opening_balance','stocktake_adjustment') then iti.quantity else -iti.quantity end), 0) into available
    from public.inventory_transactions it join public.inventory_transaction_items iti on iti.institution_id = it.institution_id and iti.transaction_id = it.id
    where it.institution_id = invoice.institution_id and it.warehouse_id = p_warehouse_id and iti.product_id = row_item.product_id and iti.unit_id = row_item.unit_id;
    if available < row_item.quantity then raise exception 'insufficient_stock'; end if;
  end loop;
  insert into public.inventory_transactions (institution_id, warehouse_id, transaction_type, source_type, source_id, created_by, idempotency_key, notes)
  values (invoice.institution_id, p_warehouse_id, 'sales_issue', 'sales_invoice', invoice.id, p_approver_employee_id, 'sales-invoice:' || invoice.id, 'صرف مرتبط بفاتورة مبيعات')
  on conflict (institution_id, idempotency_key) do nothing returning id into transaction_id;
  if transaction_id is not null then
    insert into public.inventory_transaction_items (institution_id, transaction_id, product_id, unit_id, quantity, unit_cost)
    select institution_id, transaction_id, product_id, unit_id, quantity, unit_price from public.sales_invoice_items where institution_id = invoice.institution_id and invoice_id = invoice.id;
  end if;
  update public.sales_invoices set status = 'approved', approved_by = p_approver_employee_id, approved_at = now() where id = invoice.id;
  return invoice.id;
end; $$;

revoke all on function app.create_sales_invoice_with_items(uuid,uuid,uuid,text,uuid,jsonb,numeric,text) from public, anon, authenticated;
revoke all on function app.create_purchase_invoice_with_items(uuid,uuid,uuid,text,uuid,jsonb,numeric,text) from public, anon, authenticated;
revoke all on function app.approve_purchase_invoice(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function app.approve_sales_invoice(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function app.create_sales_invoice_with_items(uuid,uuid,uuid,text,uuid,jsonb,numeric,text) to service_role;
grant execute on function app.create_purchase_invoice_with_items(uuid,uuid,uuid,text,uuid,jsonb,numeric,text) to service_role;
grant execute on function app.approve_purchase_invoice(uuid,uuid,uuid) to service_role;
grant execute on function app.approve_sales_invoice(uuid,uuid,uuid) to service_role;

create index if not exists sales_invoice_status_date_idx on public.sales_invoices (institution_id, status, invoice_date);
create index if not exists purchase_invoice_status_date_idx on public.purchase_invoices (institution_id, status, invoice_date);
create index if not exists inventory_transaction_source_idx on public.inventory_transactions (institution_id, source_type, source_id);
