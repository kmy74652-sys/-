begin;

-- إزالة الدوال التجارية قبل حذف الجداول التي تعتمد عليها.
drop function if exists app.approve_stocktake(uuid, uuid);
drop function if exists app.create_stocktake_with_items(uuid, uuid, uuid, jsonb);
drop function if exists app.create_return_transaction(uuid, uuid, public.inventory_transaction_type, text, uuid, uuid, text, jsonb);
drop function if exists app.approve_sales_invoice(uuid, uuid, uuid);
drop function if exists app.approve_purchase_invoice(uuid, uuid, uuid);
drop function if exists app.create_sales_invoice_with_items(uuid, uuid, uuid, text, uuid, jsonb, numeric, text);
drop function if exists app.create_purchase_invoice_with_items(uuid, uuid, uuid, text, uuid, jsonb, numeric, text);

-- حذف البيانات والجداول التجارية نهائيًا، مع إبقاء العملاء والحسابات والموظفين والفروع.
drop table if exists public.stocktake_items;
drop table if exists public.stocktakes;
drop table if exists public.sales_invoice_items;
drop table if exists public.sales_invoices;
drop table if exists public.purchase_invoice_items;
drop table if exists public.purchase_invoices;
drop table if exists public.inventory_transaction_items;
drop table if exists public.inventory_transactions;
drop table if exists public.products;
drop table if exists public.units;
drop table if exists public.warehouses;

drop type if exists public.inventory_transaction_type;

-- إزالة الصلاحيات التجارية حتى لا تظهر الوحدات أو تبقى قابلة للمنح.
delete from public.employee_permission_overrides
where permission_code like 'sales.%'
   or permission_code like 'purchases.%'
   or permission_code like 'inventory.%';

delete from public.role_permissions
where permission_code like 'sales.%'
   or permission_code like 'purchases.%'
   or permission_code like 'inventory.%';

delete from public.permissions
where code like 'sales.%'
   or code like 'purchases.%'
   or code like 'inventory.%';

commit;
