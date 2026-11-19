import { supabase } from './supabase';
import type { MobileProfile } from './mobileData';
import { homeAccess, summarizeTasks } from './homeModel';

const PAGE_SIZE = 500;

export async function loadHomeSummary(profile: MobileProfile, branchId: string | null) {
  if (!supabase) throw new Error('supabase_not_configured');
  const access = homeAccess(profile);
  if (!access.tasks) return summarizeTasks([]);
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!auth.user) throw new Error('not_authenticated');
  // RLS remains authoritative. Employees explicitly count only their own tasks,
  // managers count all visible tasks, never records from another organization.
  const tasks: Array<{ id: string; status: string; due_at: string | null }> = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    let query = supabase.from('tasks').select('id,status,due_at')
      .eq('organization_id', profile.institutionId).order('id').range(offset, offset + PAGE_SIZE - 1);
    if (!access.manageTasks) query = query.eq('assigned_to', auth.user.id);
    if (branchId) query = query.eq('branch_id', branchId);
    const { data, error } = await query;
    if (error) throw error;
    tasks.push(...(data ?? []));
    if (!data || data.length < PAGE_SIZE) break;
  }
  // A multi-form task may have a report awaiting review before the whole task
  // changes status. Count the task once, using the same rule as the task screen.
  const awaitingReview = new Set<string>();
  for (let start = 0; start < tasks.length; start += 200) {
    const ids = tasks.slice(start, start + 200).map((task) => task.id);
    for (let offset = 0; ; offset += PAGE_SIZE) {
      const { data, error } = await supabase.from('task_reports').select('id,task_id')
        .in('task_id', ids).eq('status', 'submitted').order('id').range(offset, offset + PAGE_SIZE - 1);
      if (error) throw error;
      for (const report of data ?? []) awaitingReview.add(report.task_id);
      if (!data || data.length < PAGE_SIZE) break;
    }
  }
  return summarizeTasks(tasks.map((task) => ({ ...task, report_forms: awaitingReview.has(task.id) ? [{ status: 'submitted' }] : [] })));
}

export async function countUnreadNotifications(): Promise<number> {
  if (!supabase) throw new Error('supabase_not_configured');
  const { count, error } = await supabase.from('notifications').select('id', { count: 'exact', head: true }).is('read_at', null);
  if (error) {
    const missing = error.code === 'PGRST205' || (error.code === '42P01' && error.message.toLowerCase().includes('notifications'));
    if (missing) return 0; // Optional relation on older installations, as in mobileData.
    throw error;
  }
  return count ?? 0;
}
