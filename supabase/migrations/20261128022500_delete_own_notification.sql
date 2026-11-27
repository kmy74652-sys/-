BEGIN;

CREATE OR REPLACE FUNCTION public.delete_notification(p_notification_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM public.notifications
  WHERE id = p_notification_id
    AND recipient_user_id = auth.uid();

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count = 1;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_notification(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_notification(uuid) TO authenticated;

COMMIT;
