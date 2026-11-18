begin;

-- admin_update_employee records an inactive employee as "archived".
-- The original audit constraint omitted that event, causing the entire
-- employee update transaction to roll back when an employee was suspended.
alter table public.employee_access_audit_log
  drop constraint if exists employee_access_audit_log_action_check;

alter table public.employee_access_audit_log
  add constraint employee_access_audit_log_action_check
  check (action in (
    'created', 'updated', 'code_set', 'password_reset', 'code_revoked',
    'suspended', 'archived', 'reactivated', 'role_changed', 'branch_changed',
    'branch_created', 'branch_updated', 'branch_archived', 'branch_reactivated'
  ));

commit;
