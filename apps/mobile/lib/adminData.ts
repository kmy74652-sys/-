import { supabase } from './supabase';
import { roleReportConfig } from './employeeRoleReports';

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
  budgetAmount: number;
  estimatedAmount: number;
  spentAmount: number;
  costNotes: string | null;
  costProposedAt?: string | null;
  costApprovedAt?: string | null;
};
export type AdminBranch = { id: string; code: string; name: string; isActive: boolean; level: string | null };
export type AdminEmployee = { id: string; userId: string | null; name: string; employeeNo: string | null; active: boolean; roles: string[]; branchId: string | null; branchName: string | null; assignments: Array<{ roleCode: string; branchId: string | null }> };
export type AdminActivity = { id: string; taskId: string; action: string; createdAt: string };
export type AdminReport = { id: string; taskId: string | null; source: 'task' | 'role'; roleCode?: string; branchName?: string | null; taskTitle: string; employeeName: string; status: string; submittedAt: string | null; reviewNote: string | null; values: Record<string, unknown>; fields: Array<{ key: string; label: string }> };
export type DashboardData = {
  tasks: AdminTask[];
  branches: AdminBranch[];
  employees: AdminEmployee[];
  reports: AdminReport[];
  activity: AdminActivity[];
};

function client() { if (!supabase) throw new Error('supabase_not_configured'); return supabase; }

const dashboardCache = new Map<string, { value: DashboardData; loadedAt: number }>();
const dashboardRequests = new Map<string, Promise<DashboardData>>();

export async function loadDashboardData(options: { force?: boolean; maxAgeMs?: number } = {}): Promise<DashboardData> {
  const db = client();
  const [{ data: authData, error: authError }, { data: profileData, error: profileError }] = await Promise.all([
    db.auth.getUser(),
    db.rpc('mobile_my_profile'),
  ]);
  if (authError || !authData.user) throw authError ?? new Error('not_authenticated');
  if (profileError) throw profileError;
  const organizationId = (profileData as { employee?: { institutionId?: string } } | null)?.employee?.institutionId;
  if (!organizationId) throw new Error('employee_not_active');

  const cacheKey = `${authData.user.id}:${organizationId}`;
  const maxAgeMs = options.maxAgeMs ?? 30_000;
  const cached = dashboardCache.get(cacheKey);
  if (!options.force && cached && Date.now() - cached.loadedAt < maxAgeMs) return cached.value;

  let request = dashboardRequests.get(cacheKey);
  if (!request) {
    request = loadDashboardDataFresh();
    dashboardRequests.set(cacheKey, request);
  }
  try {
    const value = await request;
    dashboardCache.set(cacheKey, { value, loadedAt: Date.now() });
    return value;
  } finally {
    if (dashboardRequests.get(cacheKey) === request) dashboardRequests.delete(cacheKey);
  }
}

async function loadDashboardDataFresh(): Promise<DashboardData> {
  const db = client();
  const [tasksResult, branchesResult, employeesResult, reportsResult, roleReportsResult, activityResult, costsResult] = await Promise.all([
    db.from('tasks').select('id,title,description,branch_id,assigned_to,due_at,priority,status').is('deleted_at', null).order('due_at', { ascending: true }).limit(200),
    db.from('branches').select('id,code,name,is_active,branch_level').order('code', { ascending: true }).limit(100),
    db.from('organization_memberships').select('id,user_id,display_name,employee_no,is_active').order('display_name', { ascending: true }).limit(200),
    db.from('task_reports').select('id,task_id,status,submitted_at,review_note,values,report_form_snapshot_id').order('submitted_at', { ascending: false }).limit(100),
    db.from('employee_role_reports').select('id,employee_user_id,role_code,branch_id,report_date,report_title,status,submitted_at,review_note,values').order('submitted_at', { ascending: false }).limit(100),
    db.from('task_activity_log').select('id,task_id,action,created_at').order('created_at', { ascending: false }).limit(100),
    db.from('task_costs').select('task_id,budget_amount,estimated_amount,spent_amount,notes,proposed_at,approved_at').limit(200),
  ]);
  for (const result of [tasksResult, branchesResult, employeesResult, reportsResult, roleReportsResult, activityResult, costsResult]) if (result.error) throw result.error;
  const branches = (branchesResult.data ?? []).map((row) => ({ id: row.id, code: row.code, name: row.name, isActive: row.is_active, level: row.branch_level }));
  const branchNames = new Map(branches.map((branch) => [branch.id, branch.name]));
  const membershipIds = (employeesResult.data ?? []).map((row) => row.id);
  const assignments = membershipIds.length ? await db.from('role_assignments').select('membership_id,role_code,branch_id').in('membership_id', membershipIds).limit(500) : { data: [], error: null };
  if (assignments.error) throw assignments.error;
  const rolesByMembership = new Map<string, string[]>();
  const branchByMembership = new Map<string, string | null>();
  const assignmentsByMembership = new Map<string, Array<{ roleCode: string; branchId: string | null }>>();
  for (const row of assignments.data ?? []) {
    rolesByMembership.set(row.membership_id, [...(rolesByMembership.get(row.membership_id) ?? []), row.role_code]);
    assignmentsByMembership.set(row.membership_id, [...(assignmentsByMembership.get(row.membership_id) ?? []), { roleCode: row.role_code, branchId: row.branch_id }]);
    if (!branchByMembership.has(row.membership_id)) branchByMembership.set(row.membership_id, row.branch_id);
  }
  const employees = (employeesResult.data ?? []).map((row) => {
    const branchId = branchByMembership.get(row.id) ?? null;
    return {
      id: row.id,
      userId: row.user_id,
      name: row.display_name,
      employeeNo: row.employee_no,
      active: row.is_active,
      roles: rolesByMembership.get(row.id) ?? [],
      branchId,
      branchName: branchId ? branchNames.get(branchId) ?? null : null,
      assignments: assignmentsByMembership.get(row.id) ?? [],
    };
  });
  const costsByTaskId = new Map((costsResult.data ?? []).map((row) => [row.task_id, row]));
  const tasks = (tasksResult.data ?? []).map((row) => {
    const cost = costsByTaskId.get(row.id);
    return { id: row.id, title: row.title, description: row.description, branchId: row.branch_id, branchName: row.branch_id ? branchNames.get(row.branch_id) ?? null : null, assignedTo: row.assigned_to, dueAt: row.due_at, priority: row.priority, status: row.status, budgetAmount: Number(cost?.budget_amount ?? 0), estimatedAmount: Number(cost?.estimated_amount ?? 0), spentAmount: Number(cost?.spent_amount ?? 0), costNotes: cost?.notes ?? null, costProposedAt: cost?.proposed_at ?? null, costApprovedAt: cost?.approved_at ?? null };
  });
  const snapshotIds = (reportsResult.data ?? []).map((row) => row.report_form_snapshot_id).filter((id): id is string => Boolean(id));
  const snapshotsResult = snapshotIds.length ? await db.from('task_report_form_snapshots').select('id,title,schema').in('id', snapshotIds).limit(500) : { data: [], error: null };
  if (snapshotsResult.error) throw snapshotsResult.error;
  const snapshots = new Map((snapshotsResult.data ?? []).map((row) => [row.id, row]));
  const taskById = new Map(tasks.map((task) => [task.id, task]));
  const employeeByUserId = new Map(employees.filter((employee) => employee.userId).map((employee) => [employee.userId!, employee.name]));
  const roleReports = (roleReportsResult.data ?? []).map((row) => {
    const config = roleReportConfig(row.role_code);
    const branchName = row.branch_id ? branchNames.get(row.branch_id) ?? null : null;
    return { id: row.id, taskId: null, source: 'role' as const, roleCode: row.role_code, branchName, taskTitle: row.report_title, employeeName: employeeByUserId.get(row.employee_user_id) ?? 'موظف غير معروف', status: row.status, submittedAt: row.submitted_at, reviewNote: row.review_note, values: (row.values as Record<string, unknown> | null) ?? {}, fields: config.fields.map((field) => ({ key: field.key, label: field.label })) };
  });
  return {
    tasks,
    branches,
    employees,
    reports: [...(reportsResult.data ?? []).map((row) => {
      const task = taskById.get(row.task_id);
      const snapshot = row.report_form_snapshot_id ? snapshots.get(row.report_form_snapshot_id) : null;
      const schema = Array.isArray(snapshot?.schema) ? snapshot.schema as Array<Record<string, unknown>> : [];
      return { id: row.id, taskId: row.task_id, source: 'task' as const, taskTitle: task?.title ?? 'مهمة غير معروفة', employeeName: task?.assignedTo ? employeeByUserId.get(task.assignedTo) ?? 'موظف غير معروف' : 'موظف غير معروف', status: row.status, submittedAt: row.submitted_at, reviewNote: row.review_note, values: (row.values as Record<string, unknown> | null) ?? {}, fields: schema.map((field) => ({ key: String(field.key ?? ''), label: String(field.label ?? field.key ?? 'حقل') })) };
    }), ...roleReports],
    activity: (activityResult.data ?? []).map((row) => ({ id: row.id, taskId: row.task_id, action: row.action, createdAt: row.created_at })),
  };
}

export async function listTaskTemplates() {
  const { data, error } = await client().from('task_templates').select('id,code,title,description,role_code,branch_level,recurrence_type,is_active').eq('is_active', true).order('title').limit(100);
  if (error) throw error;
  return data ?? [];
}

export async function createAdministrativeTask(input: { title: string; description: string; dueAt: string; priority: string; branchId: string | null; roleCode: string; assignedEmployeeId: string; templateId: string | null; reportTemplateId?: string | null; reportVersionId?: string | null; reportRequired?: boolean; reportOverrides?: unknown[]; idempotencyKey?: string; budgetAmount?: number; estimatedAmount?: number; spentAmount?: number; costNotes?: string | null }) {
  const db = client();
  const { data: authData, error: authError } = await db.auth.getUser();
  if (authError || !authData.user) throw authError ?? new Error('not_authenticated');
  const { data: profileData, error: profileError } = await db.rpc('mobile_my_profile');
  if (profileError) throw profileError;
  const employeeProfile = (profileData as { employee?: { institutionId?: string; permissions?: string[] } } | null)?.employee;
  const organizationId = employeeProfile?.institutionId;
  const currentPermissions = new Set(employeeProfile?.permissions ?? []);
  if (!organizationId) throw new Error('employee_not_active');
  const reportTemplateId = input.reportTemplateId ?? null;
  const reportVersionId = input.reportVersionId ?? null;
  if ((reportTemplateId === null) !== (reportVersionId === null)) throw new Error('report_form_version_required');
  if (input.reportRequired && !reportTemplateId && !input.templateId) throw new Error('task_report_required_without_fields');
  let assignmentQuery = db.from('role_assignments').select('membership_id,organization_id,branch_id').eq('organization_id', organizationId).eq('membership_id', input.assignedEmployeeId).eq('role_code', input.roleCode).limit(20);
  if (input.branchId) assignmentQuery = assignmentQuery.eq('branch_id', input.branchId);
  const { data: assignments, error: assignmentError } = await assignmentQuery;
  if (assignmentError) throw assignmentError;
  if (!assignments?.length) throw new Error('employee_assignment_invalid');
  const membershipIds = assignments.map((row) => row.membership_id);
  const { data: memberships, error: membershipError } = await db.from('organization_memberships').select('id,user_id,is_active').eq('organization_id', organizationId).in('id', membershipIds).eq('is_active', true).limit(20);
  if (membershipError) throw membershipError;
  const assignee = memberships?.[0];
  if (!assignee?.user_id) throw new Error('employee_login_not_linked');
  const assignment = assignments.find((row) => row.membership_id === assignee?.id);
  if (!assignee || !assignment) throw new Error('employee_not_active');
  const { data: task, error } = input.templateId
    ? await db.rpc('assign_task_from_template', {
        p_organization_id: organizationId,
        p_template_id: input.templateId,
        p_assigned_to: assignee.user_id,
        p_branch_id: input.branchId,
        p_starts_at: new Date().toISOString(),
        p_due_at: input.dueAt,
        p_priority: input.priority,
        p_instructions: input.description.trim() || null,
        p_report_overrides: input.reportOverrides ?? [],
        p_idempotency_key: input.idempotencyKey ?? null,
      })
    : await db.rpc('create_task_with_report_form', {
        p_organization_id: organizationId,
        p_title: input.title.trim(),
        p_description: input.description.trim() || null,
        p_due_at: input.dueAt,
        p_priority: input.priority,
        p_branch_id: input.branchId,
        p_role_code: input.roleCode,
        p_template_id: null,
        p_assigned_to: assignee.user_id,
        p_report_template_id: reportTemplateId,
        p_report_version_id: reportVersionId,
        p_report_required: Boolean(input.reportRequired),
      });
  if (error) throw error;
  const taskId = typeof task === 'string' ? task : (task as { id?: string } | null)?.id;
  if (!taskId) throw new Error('task_create_response_invalid');
  const hasCostInput = (input.budgetAmount ?? 0) > 0 || (input.estimatedAmount ?? 0) > 0 || (input.spentAmount ?? 0) > 0 || Boolean(input.costNotes?.trim());
  if (hasCostInput && currentPermissions.has('task_costs.approve')) {
    const { error: costError } = await db.from('task_costs').upsert({ organization_id: organizationId, task_id: taskId, budget_amount: Math.max(0, input.budgetAmount ?? 0), estimated_amount: Math.max(0, input.estimatedAmount ?? 0), spent_amount: Math.max(0, input.spentAmount ?? 0), notes: input.costNotes?.trim() || null, approved_by: authData.user.id, approved_at: new Date().toISOString() }, { onConflict: 'task_id' });
    if (costError) throw costError;
  } else if (hasCostInput && currentPermissions.has('task_costs.propose')) {
    const { error: costError } = await db.rpc('propose_task_cost', { p_organization_id: organizationId, p_task_id: taskId, p_estimated_amount: Math.max(0, input.estimatedAmount ?? 0), p_notes: input.costNotes?.trim() || null });
    if (costError) throw costError;
  } else if (hasCostInput) {
    throw new Error('task_cost_permission_denied');
  }
  return { id: taskId, assigned_to: assignee.user_id };
}

export async function approveAdministrativeTaskCost(input: { taskId: string; budgetAmount: number; estimatedAmount: number; spentAmount: number; notes?: string | null }) {
  const db = client();
  const [{ data: authData, error: authError }, { data: profileData, error: profileError }] = await Promise.all([
    db.auth.getUser(),
    db.rpc('mobile_my_profile'),
  ]);
  if (authError || !authData.user) throw authError ?? new Error('not_authenticated');
  if (profileError) throw profileError;
  const employee = (profileData as { employee?: { institutionId?: string; permissions?: string[] } } | null)?.employee;
  const organizationId = employee?.institutionId;
  if (!organizationId) throw new Error('employee_not_active');
  if (!employee?.permissions?.includes('task_costs.approve')) throw new Error('task_cost_approval_permission_denied');

  const amounts = [input.budgetAmount, input.estimatedAmount, input.spentAmount];
  if (amounts.some((value) => !Number.isFinite(value) || value < 0)) throw new Error('invalid_task_cost_amount');

  const approvedAt = new Date().toISOString();
  const { error } = await db.from('task_costs').upsert({
    organization_id: organizationId,
    task_id: input.taskId,
    budget_amount: input.budgetAmount,
    estimated_amount: input.estimatedAmount,
    spent_amount: input.spentAmount,
    notes: input.notes?.trim() || null,
    approved_by: authData.user.id,
    approved_at: approvedAt,
  }, { onConflict: 'task_id' });
  if (error) throw error;
  return { approvedAt };
}

export const statusLabel = (status: string) => ({ new: 'جديدة', received: 'مستلمة', in_progress: 'قيد التنفيذ', on_hold: 'معلّقة', report_submitted: 'بانتظار المراجعة', needs_revision: 'تحتاج تصحيحًا', completed_approved: 'منجزة ومعتمدة', late: 'متأخرة' }[status] ?? status);
export const roleLabel = (role: string) => ({ owner: 'صاحب المؤسسة', admin_followup: 'المدير التنفيذي', accountant: 'المحاسب', warehouse_keeper: 'أمين المخازن', warehouse_worker: 'عمال التحميل' }[role] ?? role);
