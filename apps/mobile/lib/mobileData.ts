import { supabase } from './supabase';

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
  status: 'pending' | 'in_progress' | 'submitted' | 'approved' | 'rejected' | 'cancelled';
  proof_required: boolean;
  proof_instructions: string | null;
  report_schema: Array<{
    key: string;
    label: string;
    type: 'text' | 'number' | 'progress' | 'status' | 'notes' | 'textarea' | 'date' | 'select' | 'multiselect' | 'checkbox' | 'attachment';
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
    .select('id,title,description,assignee_employee_id,branch_id,position_code,starts_at,due_at,priority,status,proof_required,proof_instructions,report_schema')
    .order('due_at', { ascending: true });
  if (error) throw error;
  const rows = data ?? [];
  const branchIds = [...new Set(rows.map((task) => task.branch_id).filter((id): id is string => Boolean(id)))];
  if (!branchIds.length) return rows as MobileTask[];
  const { data: branches, error: branchError } = await client.from('branches').select('id,name,branch_level').in('id', branchIds);
  if (branchError) return rows as MobileTask[];
  const branchById = new Map((branches ?? []).map((branch) => [branch.id, branch]));
  return rows.map((task) => ({ ...task, branch_name: branchById.get(task.branch_id)?.name ?? null, branch_level: branchById.get(task.branch_id)?.branch_level ?? null })) as MobileTask[];
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

export function updateTaskStatus(taskId: string, status: 'in_progress' | 'submitted', note: string | null = null) {
  return callRpc('mobile_record_task_update', {
    p_task_id: taskId,
    p_status: status,
    p_note: note,
  });
}

export function submitTaskReport(taskId: string, values: Record<string, unknown>) {
  return callRpc('mobile_submit_task_report', {
    p_task_id: taskId,
    p_values: values,
  });
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
