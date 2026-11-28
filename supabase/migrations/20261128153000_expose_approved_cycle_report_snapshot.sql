-- Expose the approved cycle report snapshot to the unified table editor.
CREATE OR REPLACE FUNCTION public.list_approved_task_cycles()
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', c.id,
    'organization_id', c.organization_id,
    'source_task_id', c.source_task_id,
    'source_report_id', c.source_report_id,
    'employee_user_id', c.employee_user_id,
    'employee_name', coalesce(m.display_name, 'موظف'),
    'branch_id', c.branch_id,
    'branch_name', coalesce(b.name, 'كل الفروع'),
    'title', c.title,
    'description', c.description,
    'expected_result', c.expected_result,
    'priority', c.priority,
    'task_instructions', c.task_instructions,
    'report_required', c.report_required,
    'report_snapshots', c.report_snapshots,
    'active', c.active,
    'approved_at', c.approved_at,
    'next_issue_date', c.next_issue_date,
    'last_issued_date', c.last_issued_date,
    'issued_count', (SELECT count(*) FROM public.approved_task_cycle_issues i WHERE i.cycle_id = c.id),
    'next_issue_overrides', c.next_issue_overrides,
    'next_issue_title', coalesce(nullif(c.next_issue_overrides->>'title', ''), c.title),
    'next_issue_description', coalesce(nullif(c.next_issue_overrides->>'description', ''), c.description),
    'next_issue_expected_result', coalesce(nullif(c.next_issue_overrides->>'expected_result', ''), c.expected_result),
    'next_issue_priority', coalesce(nullif(c.next_issue_overrides->>'priority', ''), c.priority::text),
    'next_issue_instructions', coalesce(nullif(c.next_issue_overrides->>'task_instructions', ''), c.task_instructions),
    'has_next_issue_override', c.next_issue_overrides <> '{}'::jsonb
  )
  FROM public.approved_task_cycles c
  LEFT JOIN public.organization_memberships m
    ON m.organization_id = c.organization_id
   AND m.user_id = c.employee_user_id
  LEFT JOIN public.branches b ON b.id = c.branch_id
  WHERE public.has_org_permission(c.organization_id, 'tasks.review', NULL::uuid)
     OR public.has_org_permission(c.organization_id, 'tasks.manage', NULL::uuid)
     OR public.has_org_permission(c.organization_id, 'reports.read_all', NULL::uuid)
  ORDER BY c.active DESC, c.next_issue_date, c.approved_at DESC;
END;
$$;
