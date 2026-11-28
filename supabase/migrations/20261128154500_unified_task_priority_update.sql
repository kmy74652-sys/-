BEGIN;

CREATE OR REPLACE FUNCTION public.admin_update_unified_task(
  p_organization_id uuid,
  p_task_id uuid,
  p_title text,
  p_description text,
  p_due_at timestamp with time zone,
  p_assigned_to uuid DEFAULT NULL::uuid,
  p_branch_id uuid DEFAULT NULL::uuid,
  p_role_code text DEFAULT NULL::text,
  p_priority text DEFAULT NULL::text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_priority public.task_priority;
BEGIN
  IF NOT public.management_role_allowed(p_organization_id) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'management_role_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.tasks t
    WHERE t.id = p_task_id
      AND t.organization_id = p_organization_id
      AND t.deleted_at IS NULL
      AND (t.title LIKE 'الجدول الموحد -%' OR COALESCE(t.description, '') LIKE '%الجدول الموحد الرسمي:%')
  ) THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'unified_task_not_found';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_priority, '')), '') IS NOT NULL THEN
    BEGIN
      v_priority := NULLIF(TRIM(p_priority), '')::public.task_priority;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'invalid_task_priority';
    END;
  END IF;

  UPDATE public.tasks
  SET title = COALESCE(NULLIF(TRIM(p_title), ''), title),
      description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
      due_at = COALESCE(p_due_at, due_at),
      priority = COALESCE(v_priority, priority),
      assigned_to = COALESCE(p_assigned_to, assigned_to),
      branch_id = p_branch_id,
      position_code = COALESCE(NULLIF(TRIM(p_role_code), ''), position_code),
      updated_at = now()
  WHERE id = p_task_id
    AND organization_id = p_organization_id
    AND deleted_at IS NULL;

  RETURN p_task_id;
END;
$$;

COMMIT;
