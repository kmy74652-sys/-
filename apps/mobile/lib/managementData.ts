import { supabase } from './supabase';

async function rpc<T>(name: string, params: Record<string, unknown>): Promise<T> {
  if (!supabase) throw new Error('supabase_unavailable');
  const { data, error } = await supabase.rpc(name, params);
  if (error) throw error;
  return data as T;
}

export function updateManagedTask(organizationId: string, taskId: string, title: string, description: string, dueAt: string | null) {
  return rpc<string>('admin_update_task', { p_organization_id: organizationId, p_task_id: taskId, p_title: title, p_description: description, p_due_at: dueAt });
}
export function deleteManagedTask(organizationId: string, taskId: string) {
  return rpc<string>('admin_delete_task', { p_organization_id: organizationId, p_task_id: taskId });
}
export function updateManagedBranch(organizationId: string, branchId: string, code: string, name: string) {
  return rpc<string>('admin_update_branch', { p_organization_id: organizationId, p_branch_id: branchId, p_code: code, p_name: name });
}
export function deleteManagedBranch(organizationId: string, branchId: string) {
  return rpc<string>('admin_delete_branch', { p_organization_id: organizationId, p_branch_id: branchId });
}
export function updateManagedReportTemplate(organizationId: string, templateId: string, title: string, description: string, isActive?: boolean) {
  return rpc<string>('admin_update_report_template', { p_organization_id: organizationId, p_template_id: templateId, p_title: title, p_description: description, p_is_active: isActive ?? null });
}
export function deleteManagedReport(organizationId: string, reportId: string) {
  return rpc<string>('admin_delete_report', { p_organization_id: organizationId, p_report_id: reportId });
}
export function deleteManagedReportTemplate(organizationId: string, templateId: string) {
  return rpc<string>('admin_delete_report_template', { p_organization_id: organizationId, p_template_id: templateId });
}
