BEGIN;

CREATE TABLE IF NOT EXISTS public.pending_report_review_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.task_reports(id) ON DELETE CASCADE,
  recipient_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reminder_date date NOT NULL,
  reminder_level text NOT NULL DEFAULT 'normal'
    CHECK (reminder_level IN ('normal', 'important', 'escalated')),
  notification_id uuid REFERENCES public.notifications(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (report_id, recipient_user_id, reminder_date)
);

CREATE INDEX IF NOT EXISTS pending_report_review_reminders_report_idx
  ON public.pending_report_review_reminders (report_id, reminder_date DESC);

ALTER TABLE public.pending_report_review_reminders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pending_report_review_reminders_management_read
  ON public.pending_report_review_reminders;
CREATE POLICY pending_report_review_reminders_management_read
  ON public.pending_report_review_reminders FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public.task_reports r
    JOIN public.tasks t ON t.id = r.task_id
    WHERE r.id = report_id
      AND public.has_org_permission(t.organization_id, 'tasks.review', NULL::uuid)
  ));

CREATE OR REPLACE FUNCTION public.issue_pending_report_review_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_report record;
  v_manager record;
  v_local_now timestamp;
  v_today date;
  v_age_hours numeric;
  v_level text;
  v_severity text;
  v_notification_id uuid;
  v_count integer := 0;
BEGIN
  FOR v_report IN
    SELECT
      r.id AS report_id,
      r.submitted_at,
      t.id AS task_id,
      t.organization_id,
      t.title AS task_title,
      t.assigned_to,
      coalesce(m.display_name, 'الموظف') AS employee_name,
      coalesce(o.timezone, 'Asia/Aden') AS organization_timezone
    FROM public.task_reports r
    JOIN public.tasks t ON t.id = r.task_id
    JOIN public.organizations o ON o.id = t.organization_id
    LEFT JOIN public.organization_memberships m
      ON m.organization_id = t.organization_id
     AND m.user_id = t.assigned_to
    WHERE r.status = 'submitted'
      AND t.deleted_at IS NULL
      AND t.status = 'report_submitted'
    ORDER BY r.submitted_at
    LIMIT 500
  LOOP
    v_local_now := now() AT TIME ZONE v_report.organization_timezone;
    v_today := v_local_now::date;
    v_age_hours := extract(epoch FROM (now() - v_report.submitted_at)) / 3600;
    v_level := CASE
      WHEN v_age_hours >= 72 THEN 'escalated'
      WHEN v_age_hours >= 48 THEN 'important'
      ELSE 'normal'
    END;
    v_severity := CASE
      WHEN v_level = 'escalated' THEN 'urgent'
      WHEN v_level = 'important' THEN 'warning'
      ELSE 'info'
    END;

    FOR v_manager IN
      SELECT DISTINCT m.user_id
      FROM public.organization_memberships m
      JOIN public.role_assignments ra
        ON ra.organization_id = m.organization_id
       AND ra.membership_id = m.id
      JOIN public.role_permissions rp
        ON rp.role_code = ra.role_code
       AND rp.permission_code = 'tasks.review'
      WHERE m.organization_id = v_report.organization_id
        AND m.is_active
        AND m.user_id <> v_report.assigned_to
    LOOP
      IF EXISTS (
        SELECT 1
        FROM public.pending_report_review_reminders pr
        WHERE pr.report_id = v_report.report_id
          AND pr.recipient_user_id = v_manager.user_id
          AND pr.reminder_date = v_today
      ) THEN
        CONTINUE;
      END IF;

      INSERT INTO public.notifications (
        organization_id, recipient_user_id, task_id, title, body, severity
      ) VALUES (
        v_report.organization_id,
        v_manager.user_id,
        v_report.task_id,
        CASE v_level
          WHEN 'escalated' THEN 'تصعيد: تقرير معلق للمراجعة'
          WHEN 'important' THEN 'تذكير مهم: تقرير معلق للمراجعة'
          ELSE 'تذكير: تقرير بانتظار المراجعة'
        END,
        v_report.employee_name || ' أرسل تقرير المهمة «' || v_report.task_title
          || '» بتاريخ ' || to_char(v_report.submitted_at AT TIME ZONE v_report.organization_timezone, 'DD/MM/YYYY')
          || ' الساعة ' || to_char(v_report.submitted_at AT TIME ZONE v_report.organization_timezone, 'HH12:MI AM')
          || '. مدة الانتظار: ' || floor(v_age_hours)::text || ' ساعة.',
        v_severity
      ) RETURNING id INTO v_notification_id;

      INSERT INTO public.pending_report_review_reminders (
        report_id, recipient_user_id, reminder_date, reminder_level, notification_id
      ) VALUES (
        v_report.report_id, v_manager.user_id, v_today, v_level, v_notification_id
      ) ON CONFLICT (report_id, recipient_user_id, reminder_date) DO NOTHING;

      IF FOUND THEN
        v_count := v_count + 1;
      END IF;
    END LOOP;
  END LOOP;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_pending_report_review_reminders()
  FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF to_regnamespace('cron') IS NOT NULL THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'alshaeri-pending-report-review-reminders';
    PERFORM cron.schedule(
      'alshaeri-pending-report-review-reminders',
      '0 7 * * *',
      $job$SELECT public.issue_pending_report_review_reminders();$job$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Pending report reminder scheduler was not installed: %', SQLERRM;
END;
$$;

COMMIT;
