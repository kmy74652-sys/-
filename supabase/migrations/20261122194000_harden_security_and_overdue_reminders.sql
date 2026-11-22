-- Harden public API grants and repair overdue reminders.
-- The production and staging schemas are not identical, so optional objects
-- are guarded to keep this migration safe in either environment.

DO $$
BEGIN
  IF to_regclass('public.employee_performance_analytics') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON TABLE public.employee_performance_analytics FROM public, anon, authenticated';
    EXECUTE 'GRANT SELECT ON TABLE public.employee_performance_analytics TO authenticated';
  END IF;
END
$$;

DO $$
BEGIN
  IF to_regprocedure('public.mark_notification_read(uuid)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.mark_notification_read(uuid) FROM public, anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated';
  END IF;

  IF to_regprocedure('public.employee_agreement_can(uuid,text)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.employee_agreement_can(uuid,text) FROM public, anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.employee_agreement_can(uuid,text) TO authenticated';
  END IF;

  IF to_regprocedure('public.employee_agreement_can(uuid,text,uuid)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.employee_agreement_can(uuid,text,uuid) FROM public, anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.employee_agreement_can(uuid,text,uuid) TO authenticated';
  END IF;

  IF to_regprocedure('public.dispatch_notification_push()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.dispatch_notification_push() FROM public, anon, authenticated';
  END IF;
  IF to_regprocedure('public.notify_report_cycle()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.notify_report_cycle() FROM public, anon, authenticated';
  END IF;
  IF to_regprocedure('public.notify_task_assignee()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.notify_task_assignee() FROM public, anon, authenticated';
  END IF;
  IF to_regprocedure('public.employee_agreement_audit_guard()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.employee_agreement_audit_guard() FROM public, anon, authenticated';
    EXECUTE 'ALTER FUNCTION public.employee_agreement_audit_guard() SET search_path = pg_catalog, public, auth';
  END IF;
  IF to_regprocedure('public.prevent_task_activity_mutation()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.prevent_task_activity_mutation() FROM public, anon, authenticated';
  END IF;
  IF to_regprocedure('public.sync_employee_agreement_responsibilities()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.sync_employee_agreement_responsibilities() FROM public, anon, authenticated';
    EXECUTE 'ALTER FUNCTION public.sync_employee_agreement_responsibilities() SET search_path = pg_catalog, public, auth';
  END IF;
END
$$;

-- Production's overdue reminder function referenced enum labels that no longer
-- exist. Recreate it only where the newer enum contract is present.
DO $$
BEGIN
  IF to_regprocedure('public.dispatch_overdue_task_reminders()') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM pg_type t
       JOIN pg_enum e ON e.enumtypid = t.oid
       WHERE t.typname = 'task_status'
         AND e.enumlabel = 'completed_approved'
     )
     AND EXISTS (
       SELECT 1
       FROM pg_type t
       JOIN pg_enum e ON e.enumtypid = t.oid
       WHERE t.typname = 'task_status'
         AND e.enumlabel = 'report_submitted'
     )
  THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.dispatch_overdue_task_reminders()
      RETURNS integer
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, auth
      AS $body$
      DECLARE
        v_task record;
        v_logged_task uuid;
        v_sent integer := 0;
      BEGIN
        FOR v_task IN
          SELECT t.id, t.organization_id, t.assigned_to, t.title, t.due_at
          FROM public.tasks t
          WHERE t.assigned_to IS NOT NULL
            AND t.deleted_at IS NULL
            AND t.due_at < now()
            AND t.status NOT IN (
              'completed_approved'::public.task_status,
              'report_submitted'::public.task_status
            )
        LOOP
          v_logged_task := NULL;
          INSERT INTO public.notification_reminder_log(task_id, recipient_user_id, reminder_date)
          VALUES (v_task.id, v_task.assigned_to, current_date)
          ON CONFLICT (task_id, recipient_user_id, reminder_date) DO NOTHING
          RETURNING task_id INTO v_logged_task;

          IF v_logged_task IS NOT NULL THEN
            INSERT INTO public.notifications(
              organization_id, recipient_user_id, task_id, title, body, severity
            )
            VALUES (
              v_task.organization_id,
              v_task.assigned_to,
              v_task.id,
              'تذكير بمهمة متأخرة',
              'المهمة «' || coalesce(v_task.title, 'مهمة') || '» تجاوزت موعدها المحدد. افتح تبويب المهام لاستكمالها.',
              'warning'
            );
            v_sent := v_sent + 1;
          END IF;
        END LOOP;
        RETURN v_sent;
      END;
      $body$;
    $fn$;
  END IF;
END
$$;
