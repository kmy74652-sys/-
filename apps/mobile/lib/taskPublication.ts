import { supabase } from './supabase';

export type TaskPublicationRequest = {
  id: string;
  template_id: string;
  template_version: number;
  role_code: string;
  branch_id: string | null;
  due_at: string;
  template_snapshot: Record<string, any>;
  status: string;
  requested_at: string;
  requested_by: string;
};

async function publicationContext() {
  if (!supabase) throw new Error('supabase_not_configured');
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) throw authError ?? new Error('not_authenticated');
  const { data: memberships, error } = await supabase.from('organization_memberships')
    .select('organization_id').eq('user_id', auth.user.id).eq('is_active', true).limit(20);
  if (error) throw error;
  for (const row of memberships ?? []) {
    const { data: allowed, error: permissionError } = await supabase.rpc('task_library_allowed_for_org', {
      p_organization_id: row.organization_id,
      p_required_permission: 'task_library.manage',
    });
    if (permissionError) throw permissionError;
    if (allowed === true) return row.organization_id as string;
  }
  throw new Error('permission_denied');
}

export async function submitTaskPublicationRequest(templateId: string, branchId: string | null, dueAt: string) {
  const organizationId = await publicationContext();
  const { data, error } = await supabase!.rpc('submit_task_publication_request', {
    p_organization_id: organizationId,
    p_template_id: templateId,
    p_branch_id: branchId,
    p_due_at: dueAt,
  });
  if (error) throw error;
  if (typeof data !== 'string') throw new Error('task_publication_request_response_invalid');
  return data;
}

export async function listPendingTaskPublicationRequests(): Promise<TaskPublicationRequest[]> {
  const organizationId = await publicationContext();
  const { data, error } = await supabase!.from('task_publication_requests')
    .select('id,template_id,template_version,role_code,branch_id,due_at,template_snapshot,status,requested_at,requested_by')
    .eq('organization_id', organizationId).eq('status', 'pending_approval')
    .order('requested_at', { ascending: true }).limit(100);
  if (error) throw error;
  return (data ?? []) as TaskPublicationRequest[];
}

export async function reviewTaskPublicationRequest(requestId: string, approve: boolean, note = '') {
  const organizationId = await publicationContext();
  const { data, error } = await supabase!.rpc('review_and_publish_task_request', {
    p_organization_id: organizationId,
    p_request_id: requestId,
    p_approve: approve,
    p_review_note: note.trim() || null,
  });
  if (error) throw error;
  return Number(data ?? 0);
}
