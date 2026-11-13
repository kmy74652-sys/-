alter table public.inventory_transaction_items
  add column if not exists movement_sign smallint not null default 1 check (movement_sign in (-1, 1));

create or replace function app.create_stocktake_with_items(p_institution_id uuid, p_warehouse_id uuid, p_created_by uuid, p_items jsonb)
returns uuid language plpgsql security definer set search_path = public, app as $$
declare
  stocktake_id uuid;
  row_item jsonb;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'stocktake_items_required'; end if;
  if not exists (select 1 from public.warehouses where institution_id = p_institution_id and id = p_warehouse_id and is_active) then raise exception 'warehouse_not_found'; end if;
  insert into public.stocktakes (institution_id, warehouse_id, status, counted_at, created_by)
  values (p_institution_id, p_warehouse_id, 'submitted', now(), p_created_by) returning id into stocktake_id;
  for row_item in select * from jsonb_array_elements(p_items) loop
    insert into public.stocktake_items (institution_id, stocktake_id, product_id, book_quantity, counted_quantity)
    values (p_institution_id, stocktake_id, (row_item->>'productId')::uuid, (row_item->>'bookQuantity')::numeric, (row_item->>'countedQuantity')::numeric);
  end loop;
  return stocktake_id;
end; $$;

create or replace function app.create_return_transaction(
  p_institution_id uuid,
  p_warehouse_id uuid,
  p_transaction_type public.inventory_transaction_type,
  p_source_type text,
  p_source_id uuid,
  p_created_by uuid,
  p_idempotency_key text,
  p_items jsonb
)
returns uuid
language plpgsql security definer set search_path = public, app as $$
declare
  transaction_id uuid;
  row_item jsonb;
  movement smallint;
begin
  if p_transaction_type not in ('sales_return', 'purchase_return') then raise exception 'invalid_return_type'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'return_items_required'; end if;
  if not exists (select 1 from public.warehouses where institution_id = p_institution_id and id = p_warehouse_id and is_active) then raise exception 'warehouse_not_found'; end if;
  movement := case when p_transaction_type = 'sales_return' then 1 else -1 end;
  insert into public.inventory_transactions (institution_id, warehouse_id, transaction_type, source_type, source_id, created_by, idempotency_key, notes)
  values (p_institution_id, p_warehouse_id, p_transaction_type, p_source_type, p_source_id, p_created_by, p_idempotency_key, 'مرتجع مرتبط بالمستند المصدر')
  on conflict (institution_id, idempotency_key) do nothing returning id into transaction_id;
  if transaction_id is null then select id into transaction_id from public.inventory_transactions where institution_id = p_institution_id and idempotency_key = p_idempotency_key; return transaction_id; end if;
  for row_item in select * from jsonb_array_elements(p_items) loop
    insert into public.inventory_transaction_items (institution_id, transaction_id, product_id, unit_id, quantity, unit_cost, movement_sign)
    values (p_institution_id, transaction_id, (row_item->>'productId')::uuid, (row_item->>'unitId')::uuid, (row_item->>'quantity')::numeric, coalesce((row_item->>'unitCost')::numeric, 0), movement);
  end loop;
  return transaction_id;
end; $$;

create or replace function app.approve_stocktake(p_stocktake_id uuid, p_approver_employee_id uuid)
returns uuid
language plpgsql security definer set search_path = public, app as $$
declare
  stocktake public.stocktakes%rowtype;
  transaction_id uuid;
  item record;
begin
  select * into stocktake from public.stocktakes where id = p_stocktake_id for update;
  if not found then raise exception 'stocktake_not_found'; end if;
  if stocktake.status <> 'submitted' then raise exception 'stocktake_must_be_submitted'; end if;
  if stocktake.created_by = p_approver_employee_id then raise exception 'stocktake_approver_not_independent'; end if;
  insert into public.inventory_transactions (institution_id, warehouse_id, transaction_type, source_type, source_id, created_by, idempotency_key, notes)
  values (stocktake.institution_id, stocktake.warehouse_id, 'stocktake_adjustment', 'stocktake', stocktake.id, p_approver_employee_id, 'stocktake:' || stocktake.id, 'تسوية ناتجة عن الجرد')
  on conflict (institution_id, idempotency_key) do nothing returning id into transaction_id;
  if transaction_id is not null then
    for item in select product_id, book_quantity, counted_quantity from public.stocktake_items where institution_id = stocktake.institution_id and stocktake_id = stocktake.id and counted_quantity <> book_quantity loop
      insert into public.inventory_transaction_items (institution_id, transaction_id, product_id, unit_id, quantity, unit_cost, movement_sign)
      select stocktake.institution_id, transaction_id, item.product_id, p.base_unit_id, abs(item.counted_quantity - item.book_quantity), 0, case when item.counted_quantity > item.book_quantity then 1 else -1 end
      from public.products p where p.institution_id = stocktake.institution_id and p.id = item.product_id;
    end loop;
  end if;
  update public.stocktakes set status = 'approved', approved_by = p_approver_employee_id, counted_at = coalesce(counted_at, now()) where id = stocktake.id;
  return stocktake.id;
end; $$;

revoke all on function app.create_return_transaction(uuid,uuid,public.inventory_transaction_type,text,uuid,uuid,text,jsonb) from public, anon, authenticated;
revoke all on function app.create_stocktake_with_items(uuid,uuid,uuid,jsonb) from public, anon, authenticated;
revoke all on function app.approve_stocktake(uuid,uuid) from public, anon, authenticated;
grant execute on function app.create_return_transaction(uuid,uuid,public.inventory_transaction_type,text,uuid,uuid,text,jsonb) to service_role;
grant execute on function app.create_stocktake_with_items(uuid,uuid,uuid,jsonb) to service_role;
grant execute on function app.approve_stocktake(uuid,uuid) to service_role;
