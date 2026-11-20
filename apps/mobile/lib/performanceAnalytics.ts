import { supabase } from './supabase';

export type PerformanceEmployee = { id: string; name: string; roleCode: string; roleName: string; branchName: string; criticalRequired: number; criticalDone: number; urgentRequired: number; urgentDone: number; importantRequired: number; importantDone: number; normalRequired: number; normalDone: number; delayedCount: number; reportsSubmitted: number; tasks: Array<{ id: string; title: string; priority: string; status: string; dueAt: string | null; done: boolean }> };
export type PerformanceBranch = { name: string; staffCount: number; required: number; done: number; highRequired: number; highDone: number };
const roleNames: Record<string, string> = { owner: 'صاحب المؤسسة', admin_followup: 'المدير التنفيذي', accountant: 'المحاسب', warehouse_keeper: 'أمين المخازن', warehouse_worker: 'عمال التحميل' };
function db() { if (!supabase) throw new Error('supabase_not_configured'); return supabase; }
function done(status: string) { return ['completed_approved', 'approved'].includes(status); }
function late(status: string, dueAt: string | null) { return !done(status) && status !== 'cancelled' && Boolean(dueAt && Date.parse(dueAt) < Date.now()); }
export async function loadPerformanceAnalytics(): Promise<{ employees: PerformanceEmployee[]; branches: PerformanceBranch[] }> {
  const client = db();
  const [tasksResult, membersResult, assignmentsResult, branchesResult, reportsResult, roleReportsResult] = await Promise.all([
    client.from('tasks').select('id,title,assigned_to,position_code,branch_id,priority,status,due_at').order('due_at', { ascending: true }).limit(2000),
    client.from('organization_memberships').select('id,user_id,display_name,is_active').eq('is_active', true).order('display_name').limit(500),
    client.from('role_assignments').select('membership_id,role_code,branch_id').limit(1000),
    client.from('branches').select('id,name').eq('is_active', true).order('name').limit(200),
    client.from('task_reports').select('id,task_id,submitted_by,status').limit(2000),
    client.from('employee_role_reports').select('id,employee_user_id,status').limit(2000),
  ]);
  for (const result of [tasksResult, membersResult, assignmentsResult, branchesResult, reportsResult, roleReportsResult]) if (result.error) throw result.error;
  const branchMap = new Map((branchesResult.data ?? []).map((row) => [row.id, row.name]));
  const memberMap = new Map((membersResult.data ?? []).map((row) => [row.user_id, row]));
  const assignments = assignmentsResult.data ?? [];
  const primaryAssignment = new Map<string, { roleCode: string; branchId: string | null }>();
  for (const assignment of assignments) { const member = (membersResult.data ?? []).find((item) => item.id === assignment.membership_id); if (member && !primaryAssignment.has(member.user_id)) primaryAssignment.set(member.user_id, { roleCode: assignment.role_code, branchId: assignment.branch_id }); }
  const reportsByEmployee = new Map<string, number>();
  for (const report of reportsResult.data ?? []) if (report.status) reportsByEmployee.set(report.submitted_by, (reportsByEmployee.get(report.submitted_by) ?? 0) + 1);
  for (const report of roleReportsResult.data ?? []) if (report.status) reportsByEmployee.set(report.employee_user_id, (reportsByEmployee.get(report.employee_user_id) ?? 0) + 1);
  const grouped = new Map<string, PerformanceEmployee>();
  for (const member of membersResult.data ?? []) {
    const assignment = primaryAssignment.get(member.user_id); const roleCode = assignment?.roleCode ?? 'accountant';
    grouped.set(member.user_id, { id: member.id, name: member.display_name, roleCode, roleName: roleNames[roleCode] ?? roleCode, branchName: assignment?.branchId ? branchMap.get(assignment.branchId) ?? 'فرع غير محدد' : 'كل الفروع', criticalRequired: 0, criticalDone: 0, urgentRequired: 0, urgentDone: 0, importantRequired: 0, importantDone: 0, normalRequired: 0, normalDone: 0, delayedCount: 0, reportsSubmitted: reportsByEmployee.get(member.user_id) ?? 0, tasks: [] });
  }
  for (const task of tasksResult.data ?? []) {
    const employee = grouped.get(task.assigned_to); if (!employee) continue; const isDone = done(task.status); const priority = task.priority ?? 'normal'; const key = priority === 'critical' ? 'critical' : priority === 'urgent' ? 'urgent' : priority === 'important' ? 'important' : 'normal'; const counters = employee as unknown as Record<string, number>; counters[`${key}Required`] += 1; if (isDone) counters[`${key}Done`] += 1; if (late(task.status, task.due_at)) employee.delayedCount += 1; employee.tasks.push({ id: task.id, title: task.title, priority, status: task.status, dueAt: task.due_at, done: isDone });
  }
  const employees = [...grouped.values()].filter((employee) => employee.tasks.length || employee.reportsSubmitted).sort((a, b) => completionRate(b) - completionRate(a));
  const branchGroups = new Map<string, PerformanceBranch>();
  for (const employee of employees) { const branch = branchGroups.get(employee.branchName) ?? { name: employee.branchName, staffCount: 0, required: 0, done: 0, highRequired: 0, highDone: 0 }; branch.staffCount += 1; branch.required += employee.criticalRequired + employee.urgentRequired + employee.importantRequired + employee.normalRequired; branch.done += employee.criticalDone + employee.urgentDone + employee.importantDone + employee.normalDone; branch.highRequired += employee.criticalRequired + employee.urgentRequired; branch.highDone += employee.criticalDone + employee.urgentDone; branchGroups.set(employee.branchName, branch); }
  return { employees, branches: [...branchGroups.values()].sort((a, b) => branchRate(b) - branchRate(a)) };
}
export function completionRate(employee: PerformanceEmployee) { const required = employee.criticalRequired + employee.urgentRequired + employee.importantRequired + employee.normalRequired; const finished = employee.criticalDone + employee.urgentDone + employee.importantDone + employee.normalDone; return required ? finished / required * 100 : 0; }
export function highPriorityRate(employee: PerformanceEmployee) { const required = employee.criticalRequired + employee.urgentRequired; const finished = employee.criticalDone + employee.urgentDone; return required ? finished / required * 100 : 100; }
export function branchRate(branch: PerformanceBranch) { return branch.required ? branch.done / branch.required * 100 : 0; }
