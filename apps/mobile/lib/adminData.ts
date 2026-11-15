import { supabase } from './supabase';

export type AdminTask = {
  id: string;
  title: string;
  description: string | null;
  branchId: string | null;
  branchName: string | null;
  assignedTo: string | null;
  dueAt: string | null;
  priority: string;
  status: string;
};
export type AdminBranch = { id: string; code: string; name: string; isActive: boolean; level: string | null };
export type AdminEmployee = { id: string; name: string; employeeNo: string | null; active: boolean; roles: string[] };
export type AdminActivity = { id: string; taskId: string; action: string; createdAt: string };
export type DashboardData = {
  tasks: AdminTask[];
  branches: AdminBranch[];
  employees: AdminEmployee[];
  reports: Array<{ id: string; status: string; submittedAt: string }>;
  activity: AdminActivity[];
};

function client() { if (!supabase) throw new Error('supabase_not_configured'); return supabase; }

export async function loadDashboardData(): Promise<DashboardData> {
  const db = client();
  const [tasksResult, branchesResult, employeesResult, reportsResult, activityResult] = await Promise.all([
    db.from('tasks').select('id,title,description,branch_id,assigned_to,due_at,priority,status').order('due_at', { ascending: true }).limit(200),
    db.from('branches').select('id,code,name,is_active,branch_level').order('code', { ascending: true }).limit(100),
    db.from('organization_memberships').select('id,user_id,display_name,employee_no,is_active').order('display_name', { ascending: true }).limit(200),
    db.from('task_reports').select('id,status,submitted_at').order('submitted_at', { ascending: false }).limit(100),
    db.from('task_activity_log').select('id,task_id,action,created_at').order('created_at', { ascending: false }).limit(100),
  ]);
  for (const result of [tasksResult, branchesResult, employeesResult, reportsResult, activityResult]) if (result.error) throw result.error;
  const branches = (branchesResult.data ?? []).map((row) => ({ id: row.id, code: row.code, name: row.name, isActive: row.is_active, level: row.branch_level }));
  const branchNames = new Map(branches.map((branch) => [branch.id, branch.name]));
  const membershipIds = (employeesResult.data ?? []).map((row) => row.id);
  const assignments = membershipIds.length ? await db.from('role_assignments').select('membership_id,role_code').in('membership_id', membershipIds).limit(500) : { data: [], error: null };
  if (assignments.error) throw assignments.error;
  const rolesByMembership = new Map<string, string[]>();
  for (const row of assignments.data ?? []) rolesByMembership.set(row.membership_id, [...(rolesByMembership.get(row.membership_id) ?? []), row.role_code]);
  const employees = (employeesResult.data ?? []).map((row) => ({ id: row.user_id, name: row.display_name, employeeNo: row.employee_no, active: row.is_active, roles: rolesByMembership.get(row.id) ?? [] }));
  const tasks = (tasksResult.data ?? []).map((row) => ({ id: row.id, title: row.title, description: row.description, branchId: row.branch_id, branchName: row.branch_id ? branchNames.get(row.branch_id) ?? null : null, assignedTo: row.assigned_to, dueAt: row.due_at, priority: row.priority, status: row.status }));
  return {
    tasks,
    branches,
    employees,
    reports: (reportsResult.data ?? []).map((row) => ({ id: row.id, status: row.status, submittedAt: row.submitted_at })),
    activity: (activityResult.data ?? []).map((row) => ({ id: row.id, taskId: row.task_id, action: row.action, createdAt: row.created_at })),
  };
}

export async function listTaskTemplates() {
  const { data, error } = await client().from('task_templates').select('id,code,title,description,role_code,branch_level,recurrence_type,is_active').eq('is_active', true).order('title').limit(100);
  if (error) throw error;
  return data ?? [];
}

export async function createAdministrativeTask(input: { title: string; description: string; dueAt: string; priority: string; branchId: string | null; roleCode: string; templateId: string | null }) {
  const db = client();
  const { data: authData, error: authError } = await db.auth.getUser();
  if (authError || !authData.user) throw authError ?? new Error('not_authenticated');
  let assignmentQuery = db.from('role_assignments').select('membership_id,organization_id,branch_id').eq('role_code', input.roleCode).limit(20);
  if (input.branchId) assignmentQuery = assignmentQuery.eq('branch_id', input.branchId);
  const { data: assignments, error: assignmentError } = await assignmentQuery;
  if (assignmentError) throw assignmentError;
  if (!assignments?.length) throw new Error('no_employee_for_role');
  const membershipIds = assignments.map((row) => row.membership_id);
  const { data: memberships, error: membershipError } = await db.from('organization_memberships').select('id,user_id,is_active').in('id', membershipIds).eq('is_active', true).limit(20);
  if (membershipError) throw membershipError;
  const assignee = memberships?.[0];
  const assignment = assignments.find((row) => row.membership_id === assignee?.id);
  if (!assignee || !assignment) throw new Error('no_employee_for_role');
  const { data: task, error } = await db.from('tasks').insert({
    organization_id: assignment.organization_id,
    branch_id: input.branchId,
    title: input.title.trim(),
    description: input.description.trim() || null,
    assigned_to: assignee.user_id,
    created_by: authData.user.id,
    due_at: input.dueAt,
    priority: input.priority,
    template_id: input.templateId,
  }).select('id').single();
  if (error) throw error;
  if (input.templateId && task?.id) {
    const { data: templateFields, error: fieldsError } = await db.from('task_template_report_fields').select('label,field_key,field_type,is_required,options,sort_order').eq('template_id', input.templateId).order('sort_order', { ascending: true }).limit(100);
    if (fieldsError) throw fieldsError;
    if (templateFields?.length) {
      const { error: copyError } = await db.from('task_report_fields').insert(templateFields.map((field) => ({ ...field, task_id: task.id })));
      if (copyError) throw copyError;
    }
  }
  return task;
}

export const statusLabel = (status: string) => ({ new: 'جديدة', received: 'مستلمة', in_progress: 'قيد التنفيذ', on_hold: 'معلّقة', report_submitted: 'بانتظار المراجعة', needs_revision: 'تحتاج تصحيحًا', completed_approved: 'منجزة ومعتمدة', late: 'متأخرة' }[status] ?? status);
export const roleLabel = (role: string) => ({ owner: 'صاحب المؤسسة', admin_followup: 'المدير التنفيذي', accountant: 'المحاسب', warehouse_keeper: 'أمين المخازن', warehouse_worker: 'عمال التحميل' }[role] ?? role);
