BEGIN;

-- A submitted report is a review checkpoint. The task must remain visible as
-- report_submitted until the review RPC changes the report to approved/returned.
CREATE OR REPLACE FUNCTION public.guard_task_pending_report_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NEW.report_flow = 'multi_form'
     AND NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status <> 'report_submitted'
     AND EXISTS (
       SELECT 1
       FROM public.task_reports r
       WHERE r.task_id = NEW.id
         AND r.status = 'submitted'
     )
  THEN
    RAISE EXCEPTION USING
      errcode = '22023',
      message = 'task_waiting_for_report_review';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_task_pending_report_review ON public.tasks;
CREATE TRIGGER guard_task_pending_report_review
BEFORE UPDATE OF status ON public.tasks
FOR EACH ROW
EXECUTE FUNCTION public.guard_task_pending_report_review();

REVOKE ALL ON FUNCTION public.guard_task_pending_report_review() FROM PUBLIC, anon, authenticated;

COMMIT;
