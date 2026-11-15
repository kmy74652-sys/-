import { supabase } from './supabase';
import { flushQueue, queueOperation, type QueueItem } from './offlineQueue';

export type MobileProfile = {
  id: string;
  institutionId: string;
  employeeNo: string;
  fullName: string;
  email: string | null;
  phone: string | null;
  status: string;
  lastLoginAt: string | null;
  roles: Array<{ code: string; nameAr: string }>;
  permissions: string[];
  branches: Array<{ id: string; code: string; name: string; isDefault: boolean }>;
};

export type MobileIdentity = { userId: string; employee: MobileProfile | null };
type ReportField = { key: string; label: string; description?: string | null; type: 'text' | 'number' | 'progress' | 'status' | 'notes' | 'textarea' | 'date' | 'select' | 'multiselect' | 'checkbox' | 'attachment' | 'short_text' | 'long_text' | 'integer' | 'quantity' | 'money' | 'datetime' | 'boolean' | 'table' | 'image' | 'file' | 'signature' | 'calculated' | 'decision_notes'; options?: string[]; required?: boolean; repeatable?: boolean; validation?: Record<string, unknown>; config?: Record<string, unknown> };

export type MobileTask = {
  id: string;
  title: string;
  description: string | null;
  assignee_employee_id: string;
  branch_id: string | null;
  branch_name?: string | null;
  branch_level?: number | null;
  position_code: 'owner' | 'admin_followup' | 'accountant' | 'warehouse_keeper' | 'warehouse_worker' | null;
  starts_at: string;
  due_at: string;
  priority: 'low' | 'normal' | 'high' | 'urgent';
  status: 'pending' | 'in_progress' | 'submitted' | 'approved' | 'rejected' | 'cancelled' | 'late';
  proof_required: boolean;
  proof_instructions: string | null;
  report_schema: Array<{
    key: string;
    label: string;
    type: ReportField['type'];
    options?: string[];
    required?: boolean;
  }>;
};

export type MobileNotification = {
  id: string;
  title: string;
  body: string;
  severity: string;
  read_at: string | null;
  created_at: string;
};
export type TaskTimelineEntry = { id: string; status: string; note: string | null; actor_name: string; created_at: string };

function getClient() {
  if (!supabase) throw new Error('supabase_not_configured');
  return supabase;
}

export async function getMyEmployeeProfile(): Promise<MobileIdentity | null> {
  const client = getClient();
  const { data: authData, error: authError } = await client.auth.getUser();
  if (authError) throw authError;
  if (!authData.user) return null;

  const { data, error } = await client.rpc('mobile_my_profile');
  if (error) throw error;
  const result = data as { employee?: MobileProfile } | null;
  return { userId: authData.user.id, employee: result?.employee ?? null };
}

export async function listMyTasks(): Promise<MobileTask[]> {
  const client = getClient();
  const { data, error } = await client
    .from('tasks')
    .select('id,title,description,assigned_to,branch_id,due_at,priority,status,assigned_at,created_at')
    .order('due_at', { ascending: true });
  if (error) throw error;
  const rows = data ?? [];
  const branchIds = [...new Set(rows.map((task) => task.branch_id).filter((id): id is string => Boolean(id)))];
  const assignedIds = [...new Set(rows.map((task) => task.assigned_to).filter((id): id is string => Boolean(id)))];
  const taskIds = rows.map((task) => task.id);
  const [branchesResult, membershipsResult, fieldsResult] = await Promise.all([
    branchIds.length ? client.from('branches').select('id,name,branch_level').in('id', branchIds) : Promise.resolve({ data: [], error: null }),
    assignedIds.length ? client.from('organization_memberships').select('id,user_id').in('user_id', assignedIds) : Promise.resolve({ data: [], error: null }),
    taskIds.length ? client.from('task_report_fields').select('task_id,label,field_key,field_type,is_required,options,sort_order').in('task_id', taskIds).order('sort_order', { ascending: true }) : Promise.resolve({ data: [], error: null }),
  ]);
  if (branchesResult.error) throw branchesResult.error;
  if (membershipsResult.error) throw membershipsResult.error;
  if (fieldsResult.error) throw fieldsResult.error;
  const snapshotsResult = taskIds.length
    ? await client.from('task_report_form_snapshots').select('task_id,schema').in('task_id', taskIds).limit(200)
    : { data: [], error: null };
  if (snapshotsResult.error) throw snapshotsResult.error;
  const branches = branchesResult.data ?? [];
  const branchById = new Map((branches ?? []).map((branch) => [branch.id, branch]));
  const membershipByUser = new Map((membershipsResult.data ?? []).map((membership) => [membership.user_id, membership.id]));
  const roleAssignments = membershipByUser.size ? await client.from('role_assignments').select('membership_id,role_code').in('membership_id', [...membershipByUser.values()]).limit(100) : { data: [], error: null };
  if (roleAssignments.error) throw roleAssignments.error;
  const roleByMembership = new Map((roleAssignments.data ?? []).map((assignment) => [assignment.membership_id, assignment.role_code]));
  const fieldsByTask = new Map<string, ReportField[]>();
  for (const field of fieldsResult.data ?? []) {
    const type = field.field_type === 'long_text' ? 'textarea' : field.field_type === 'multi_select' ? 'multiselect' : field.field_type;
    const normalized = { key: field.field_key ?? `field_${field.label}`, label: field.label, type, options: Array.isArray(field.options) ? field.options : [], required: field.is_required } as ReportField;
    fieldsByTask.set(field.task_id, [...(fieldsByTask.get(field.task_id) ?? []), normalized]);
  }
  for (const snapshot of snapshotsResult.data ?? []) {
    const snapshotFields = Array.isArray(snapshot.schema) ? snapshot.schema as Array<Record<string, unknown>> : [];
    fieldsByTask.set(snapshot.task_id, snapshotFields.map((field) => ({
      key: String(field.key ?? ''), label: String(field.label ?? ''), description: (field.description as string | null) ?? null,
      type: String(field.type ?? 'short_text') as ReportField['type'], options: Array.isArray(field.options) ? field.options.map(String) : [],
      required: Boolean(field.required), repeatable: Boolean(field.repeatable), validation: (field.validation as Record<string, unknown>) ?? {}, config: (field.config as Record<string, unknown>) ?? {},
    })));
  }
  return rows.map((task) => {
    const role = task.assigned_to ? roleByMembership.get(membershipByUser.get(task.assigned_to) ?? '') : null;
    const status = task.status === 'new' || task.status === 'received' ? 'pending' : task.status === 'report_submitted' ? 'submitted' : task.status === 'completed_approved' ? 'approved' : task.status === 'needs_revision' ? 'rejected' : task.status === 'on_hold' ? 'in_progress' : task.status;
    return { ...task, assignee_employee_id: task.assigned_to, position_code: role ?? null, starts_at: task.assigned_at ?? task.created_at ?? task.due_at, status, proof_required: false, proof_instructions: null, report_schema: fieldsByTask.get(task.id) ?? [], branch_name: branchById.get(task.branch_id)?.name ?? null, branch_level: branchById.get(task.branch_id)?.branch_level ?? null };
  }) as MobileTask[];
}

export async function listMyNotifications(): Promise<MobileNotification[]> {
  const client = getClient();
  const { data, error } = await client
    .from('notifications')
    .select('id,title,body,severity,read_at,created_at')
    .order('created_at', { ascending: false })
    .limit(50);
  if (error) throw error;
  return (data ?? []) as MobileNotification[];
}

async function callRpc(name: string, args: Record<string, unknown>) {
  const { error } = await getClient().rpc(name, args);
  if (error) throw error;
}

function isOffline(error: unknown) { const message = String((error as { message?: string })?.message ?? error).toLowerCase(); return message.includes('network') || message.includes('fetch') || message.includes('offline') || message.includes('timeout'); }
function idempotencyKey(taskId: string, operation: string) { return `${operation}:${taskId}:${Date.now()}`; }
async function executeQueueItem(item: QueueItem) {
  if (item.kind === 'status') await callRpc('mobile_record_task_update', { p_task_id: item.payload.taskId, p_status: item.payload.status, p_note: item.payload.note ?? null, p_idempotency_key: item.payload.idempotencyKey });
  if (item.kind === 'report') await callRpc('mobile_submit_task_report', { p_task_id: item.payload.taskId, p_values: item.payload.values, p_idempotency_key: item.payload.idempotencyKey });
}
export function syncOfflineQueue() { return flushQueue(executeQueueItem); }

export async function updateTaskStatus(taskId: string, status: 'in_progress' | 'submitted', note: string | null = null) {
  const payload = { taskId, status, note, idempotencyKey: idempotencyKey(taskId, `status:${status}`) };
  try { await callRpc('mobile_record_task_update', { p_task_id: taskId, p_status: status, p_note: note, p_idempotency_key: payload.idempotencyKey }); }
  catch (error) { if (!isOffline(error)) throw error; await queueOperation('status', payload); }
}

export async function submitTaskReport(taskId: string, values: Record<string, unknown>) {
  const payload = { taskId, values, idempotencyKey: idempotencyKey(taskId, 'report') };
  try { await callRpc('mobile_submit_task_report', { p_task_id: taskId, p_values: values, p_idempotency_key: payload.idempotencyKey }); }
  catch (error) { if (!isOffline(error)) throw error; await queueOperation('report', payload); }
}

export async function listTaskTimeline(taskId: string): Promise<TaskTimelineEntry[]> {
  const { data, error } = await getClient().rpc('mobile_task_timeline', { p_task_id: taskId });
  if (error) throw error;
  return ((data ?? []) as Array<{ event_id: string; action_type: string; new_status: string | null; notes: string | null; actor_name: string; created_at: string }>).map((entry) => ({
    id: entry.event_id,
    status: entry.new_status || entry.action_type,
    note: entry.notes,
    actor_name: entry.actor_name,
    created_at: entry.created_at,
  }));
}

export function reviewTask(taskId: string, decision: 'approved' | 'rejected', note: string | null) {
  return callRpc('mobile_review_task', {
    p_task_id: taskId,
    p_decision: decision,
    p_note: note,
  });
}

export function friendlyDataError(error: unknown, fallback: string): string {
  const detail = error as { code?: string; message?: string; status?: number } | null;
  const message = detail?.message ?? '';
  const code = detail?.code ?? '';
  if ((code === '42703' || code === 'PGRST204') && message.includes('position_code')) {
    return 'يجب تطبيق migration 018 لتفعيل تصنيفات المناصب قبل تحديث بيانات المهام.';
  }
  if (code === 'PGRST202' || code === '42883' || message.includes('mobile_my_profile')) {
    return 'تحديث قاعدة بيانات Supabase المطلوب لم يطبّق بعد. أعد نشر migrations ثم حاول مجددًا.';
  }
  const known: Record<string, string> = {
    employee_not_active: 'هذا الحساب غير مرتبط بملف موظف نشط. اطلب من مسؤول النظام ربطه.',
    permission_denied: 'لا يملك هذا الحساب الصلاحية المطلوبة.',
    task_not_found: 'المهمة غير متاحة لهذا الحساب أو لم تعد موجودة.',
    task_must_be_in_progress: 'ابدأ تنفيذ المهمة قبل إرسالها للمراجعة.',
    task_report_required: 'أكمل تقرير المهمة قبل إرسالها للمراجعة.',
    task_proof_required: 'هذه المهمة تتطلب إرفاق دليل إنجاز أولًا.',
    task_must_be_submitted: 'لا يمكن مراجعة المهمة قبل إرسالها.',
    task_reviewer_not_independent: 'لا يمكن لمنشئ المهمة أو منفذها اعتمادها.',
    required_report_field_missing: 'أكمل جميع حقول التقرير المطلوبة.',
    invalid_task_report_payload: 'بيانات التقرير غير صالحة.',
    not_authenticated: 'انتهت الجلسة. سجّل الدخول مجددًا.',
  };
  for (const [key, value] of Object.entries(known)) {
    if (message.includes(key)) return value;
  }
  if (detail?.status === 401) return 'انتهت الجلسة. سجّل الدخول مجددًا.';
  if (detail?.status === 403) return 'لا يملك هذا الحساب الصلاحية المطلوبة.';
  return fallback;
}
