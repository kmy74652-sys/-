import type { MobileProfile } from './mobileData';

export type TaskFilter = 'all' | 'pending' | 'in_progress' | 'submitted' | 'rejected' | 'approved' | 'late';
export type HomeDestination = 'tasks' | 'reports' | 'employees' | 'branches' | 'task-designer' | 'report-designer' | 'permissions' | 'settings';
export type TaskSummaryRow = {
  status: string;
  due_at?: string | null;
  dueAt?: string | null;
  report_forms?: Array<{ status: string | null }>;
};

export function normalizeTaskStatus(status: string): string {
  return ({ new: 'pending', received: 'pending', on_hold: 'in_progress', report_submitted: 'submitted', completed_approved: 'approved', needs_revision: 'rejected' } as Record<string, string>)[status] ?? status;
}

export function taskMatchesFilter(task: TaskSummaryRow, filter: string, now = Date.now()): boolean {
  const status = normalizeTaskStatus(task.status);
  if (filter === 'all') return true;
  if (filter === 'late') {
    if (['approved', 'cancelled'].includes(status)) return false;
    const due = Date.parse(task.due_at ?? task.dueAt ?? '');
    return status === 'late' || (Number.isFinite(due) && due < now);
  }
  if (filter === 'submitted') return status === 'submitted' || Boolean(task.report_forms?.some((form) => form.status === 'submitted'));
  return status === filter;
}

export function summarizeTasks(tasks: TaskSummaryRow[], now = Date.now()) {
  return {
    all: tasks.length,
    in_progress: tasks.filter((task) => taskMatchesFilter(task, 'in_progress', now)).length,
    submitted: tasks.filter((task) => taskMatchesFilter(task, 'submitted', now)).length,
    late: tasks.filter((task) => taskMatchesFilter(task, 'late', now)).length,
  };
}

export function homeAccess(profile: MobileProfile) {
  const allowed = new Set(profile.permissions);
  const manages = allowed.has('tasks.manage');
  const employeeManager = profile.roles.some((role) => ['owner', 'admin_followup'].includes(role.code)) && allowed.has('employees.manage');
  return {
    tasks: manages || allowed.has('tasks.execute'),
    manageTasks: manages,
    reports: manages ? allowed.has('reports.read_all') || allowed.has('tasks.review') : allowed.has('tasks.execute'),
    employees: employeeManager || (manages && allowed.has('employees.read')),
    branches: manages && (allowed.has('branches.manage') || allowed.has('branches.read_all')),
    'task-designer': manages && allowed.has('task_library.manage'),
    'report-designer': manages && allowed.has('report_forms.manage'),
    permissions: employeeManager,
    settings: employeeManager,
  };
}
