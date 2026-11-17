begin;

-- Retire the old seeded task catalog. Existing tasks and immutable report snapshots
-- remain intact; newly designed templates are unaffected.
update public.task_templates
set is_active = false,
    updated_at = now()
where code in (
  'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation',
  'acct_debts_followup', 'acct_purchase_review', 'wh_receive_goods',
  'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
  'load_order_preparation', 'load_delivery_handover',
  'admin_daily_branch_followup', 'admin_weekly_consolidated_report',
  'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review'
);

commit;
