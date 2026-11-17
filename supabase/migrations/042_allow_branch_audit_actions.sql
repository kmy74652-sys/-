-- Allow the branch lifecycle events emitted by admin_manage_branch().
-- The function writes these values to employee_access_audit_log.action.
ALTER TABLE public.employee_access_audit_log
  DROP CONSTRAINT IF EXISTS employee_access_audit_log_action_check;

ALTER TABLE public.employee_access_audit_log
  ADD CONSTRAINT employee_access_audit_log_action_check
  CHECK (
    action = ANY (
      ARRAY[
        'created',
        'updated',
        'code_set',
        'password_reset',
        'code_revoked',
        'suspended',
        'reactivated',
        'role_changed',
        'branch_changed',
        'branch_created',
        'branch_updated',
        'branch_archived',
        'branch_reactivated'
      ]::text[]
    )
  );
