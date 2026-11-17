begin;

-- Preserve historical tasks while removing their obsolete template reference.
update public.tasks
set template_id = null,
    updated_at = now()
where template_id in (
  select id from public.task_templates
  where code in (
    'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation',
    'acct_debts_followup', 'acct_purchase_review', 'wh_receive_goods',
    'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
    'load_order_preparation', 'load_delivery_handover',
    'admin_daily_branch_followup', 'admin_weekly_consolidated_report',
    'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review'
  )
);

-- Remove only dependent library records belonging to the retired starter catalog.
delete from public.task_template_steps
where template_id in (
  select id from public.task_templates where code in (
    'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation',
    'acct_debts_followup', 'acct_purchase_review', 'wh_receive_goods',
    'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
    'load_order_preparation', 'load_delivery_handover',
    'admin_daily_branch_followup', 'admin_weekly_consolidated_report',
    'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review'
  )
);

delete from public.task_template_report_forms
where template_id in (
  select id from public.task_templates where code in (
    'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation',
    'acct_debts_followup', 'acct_purchase_review', 'wh_receive_goods',
    'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
    'load_order_preparation', 'load_delivery_handover',
    'admin_daily_branch_followup', 'admin_weekly_consolidated_report',
    'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review'
  )
);

delete from public.task_template_report_fields
where template_id in (
  select id from public.task_templates where code in (
    'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation',
    'acct_debts_followup', 'acct_purchase_review', 'wh_receive_goods',
    'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
    'load_order_preparation', 'load_delivery_handover',
    'admin_daily_branch_followup', 'admin_weekly_consolidated_report',
    'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review'
  )
);

delete from public.task_template_assignments
where template_id in (
  select id from public.task_templates where code in (
    'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation',
    'acct_debts_followup', 'acct_purchase_review', 'wh_receive_goods',
    'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
    'load_order_preparation', 'load_delivery_handover',
    'admin_daily_branch_followup', 'admin_weekly_consolidated_report',
    'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review'
  )
);

delete from public.task_import_rows
where task_template_id in (
  select id from public.task_templates where code in (
    'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation',
    'acct_debts_followup', 'acct_purchase_review', 'wh_receive_goods',
    'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
    'load_order_preparation', 'load_delivery_handover',
    'admin_daily_branch_followup', 'admin_weekly_consolidated_report',
    'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review'
  )
);

delete from public.task_templates
where code in (
  'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation',
  'acct_debts_followup', 'acct_purchase_review', 'wh_receive_goods',
  'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
  'load_order_preparation', 'load_delivery_handover',
  'admin_daily_branch_followup', 'admin_weekly_consolidated_report',
  'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review'
);

commit;
