import { supabase } from './supabase';
import { flushQueue, queueOperation, type QueueItem } from './offlineQueue';
import type { ReportField } from './reportSchema';

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
  priority: 'normal' | 'important' | 'urgent' | 'critical';
  status: 'pending' | 'in_progress' | 'submitted' | 'approved' | 'rejected' | 'cancelled' | 'late';
  proof_required: boolean;
  proof_instructions: string | null;
  report_schema: ReportField[];
  task_instructions: string | null;
  report_flow: 'legacy' | 'multi_form';
  execution_steps: MobileTaskStep[];
  report_forms: MobileTaskReportForm[];
};
export type MobileTaskStep = { id: string; title: string; instructions: string | null; sort_order: number; required: boolean; evidence_required: boolean; evidence_instructions: string | null; completed: boolean };
export type MobileTaskReportForm = { snapshot_id: string; title: string; sort_order: number; required: boolean; schema: ReportField[]; report_id: string | null; status: 'submitted' | 'approved' | 'returned' | null; values: Record<string, unknown> | null; draft_values: Record<string, unknown> | null; review_note: string | null; submitted_at: string | null };

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
    .select('id,title,description,assigned_to,branch_id,position_code,due_at,priority,status,assigned_at,created_at,starts_at,report_form_snapshot_id,report_flow,task_instructions,proof_required,proof_instructions')
    .order('due_at', { ascending: true });
  if (error) throw error;
  const rows = data ?? [];
  const branchIds = [...new Set(rows.map((task) => task.branch_id).filter((id): id is string => Boolean(id)))];
  const assignedIds = [...new Set(rows.map((task) => task.assigned_to).filter((id): id is string => Boolean(id)))];
  const taskIds = rows.map((task) => task.id);
  const [branchesResult, membershipsResult, fieldsResult, stepsResult, snapshotsResult, reportsResult, draftsResult] = await Promise.all([
    branchIds.length ? client.from('branches').select('id,name,branch_level').in('id', branchIds) : Promise.resolve({ data: [], error: null }),
    assignedIds.length ? client.from('organization_memberships').select('id,user_id').in('user_id', assignedIds) : Promise.resolve({ data: [], error: null }),
    taskIds.length ? client.from('task_report_fields').select('task_id,label,field_key,field_type,is_required,options,sort_order').in('task_id', taskIds).order('sort_order', { ascending: true }) : Promise.resolve({ data: [], error: null }),
    taskIds.length ? client.from('task_execution_steps').select('id,task_id,title,instructions,sort_order,is_required,evidence_required,evidence_instructions,completed_at').in('task_id', taskIds).order('sort_order', { ascending: true }).limit(2000) : Promise.resolve({ data: [], error: null }),
    taskIds.length ? client.from('task_report_form_snapshots').select('id,task_id,title,sort_order,is_required,schema').in('task_id', taskIds).order('sort_order', { ascending: true }).limit(2000) : Promise.resolve({ data: [], error: null }),
    taskIds.length ? client.from('task_reports').select('id,task_id,report_form_snapshot_id,values,status,review_note,submitted_at').in('task_id', taskIds).order('submitted_at', { ascending: false }).limit(2000) : Promise.resolve({ data: [], error: null }),
    taskIds.length ? client.from('task_report_drafts').select('task_id,snapshot_id,values,updated_at').in('task_id', taskIds).order('updated_at', { ascending: false }).limit(2000) : Promise.resolve({ data: [], error: null }),
  ]);
  if (branchesResult.error) throw branchesResult.error;
  if (membershipsResult.error) throw membershipsResult.error;
  if (fieldsResult.error) throw fieldsResult.error;
  if (stepsResult.error) throw stepsResult.error;
  if (snapshotsResult.error) throw snapshotsResult.error;
  if (reportsResult.error) throw reportsResult.error;
  if (draftsResult.error) throw draftsResult.error;
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
  const snapshotsByTask = new Map<string, NonNullable<typeof snapshotsResult.data>>();
  for (const snapshot of snapshotsResult.data ?? []) snapshotsByTask.set(snapshot.task_id, [...(snapshotsByTask.get(snapshot.task_id) ?? []), snapshot]);
  for (const task of rows) {
    if (task.report_flow === 'multi_form' || !task.report_form_snapshot_id) continue;
    const snapshot = (snapshotsByTask.get(task.id) ?? []).find((item) => item.id === task.report_form_snapshot_id);
    const snapshotFields = Array.isArray(snapshot?.schema) ? snapshot.schema as Array<Record<string, unknown>> : [];
    if (snapshot) fieldsByTask.set(task.id, snapshotFields.map((field) => ({
      key: String(field.key ?? ''), label: String(field.label ?? ''), description: (field.description as string | null) ?? null,
      type: String(field.type ?? 'short_text') as ReportField['type'], options: Array.isArray(field.options) ? field.options.map(String) : [],
      required: Boolean(field.required), repeatable: Boolean(field.repeatable), validation: (field.validation as Record<string, unknown>) ?? {}, config: (field.config as Record<string, unknown>) ?? {},
    })));
  }
  return rows.map((task) => {
    const role = task.assigned_to ? roleByMembership.get(membershipByUser.get(task.assigned_to) ?? '') : null;
    const status = task.status === 'new' || task.status === 'received' ? 'pending' : task.status === 'report_submitted' ? 'submitted' : task.status === 'completed_approved' ? 'approved' : task.status === 'needs_revision' ? 'rejected' : task.status === 'on_hold' ? 'in_progress' : task.status;
    const executionSteps = (stepsResult.data ?? []).filter((step) => step.task_id === task.id).map((step) => ({ id: step.id, title: step.title, instructions: step.instructions, sort_order: step.sort_order, required: step.is_required, evidence_required: step.evidence_required, evidence_instructions: step.evidence_instructions, completed: Boolean(step.completed_at) }));
    const reportForms: MobileTaskReportForm[] = task.report_flow === 'multi_form' ? (snapshotsByTask.get(task.id) ?? []).map((snapshot) => {
      const latest = (reportsResult.data ?? []).find((report) => report.report_form_snapshot_id === snapshot.id);
      const latestDraft = (draftsResult.data ?? []).find((draft) => draft.snapshot_id === snapshot.id);
      const rawSchema = Array.isArray(snapshot.schema) ? snapshot.schema as Array<Record<string, unknown>> : [];
      return { snapshot_id: snapshot.id, title: snapshot.title ?? 'نموذج تقرير', sort_order: snapshot.sort_order ?? 0, required: Boolean(snapshot.is_required), schema: rawSchema.map((field) => ({ key: String(field.key ?? ''), label: String(field.label ?? ''), description: (field.description as string | null) ?? null, type: String(field.type ?? 'short_text') as ReportField['type'], options: Array.isArray(field.options) ? field.options.map(String) : [], required: Boolean(field.required), repeatable: Boolean(field.repeatable), validation: (field.validation as Record<string, unknown>) ?? {}, config: (field.config as Record<string, unknown>) ?? {} })), report_id: latest?.id ?? null, draft_values: (latestDraft?.values as Record<string, unknown> | null) ?? null, status: latest?.status === 'returned' ? 'returned' : latest?.status === 'approved' ? 'approved' : latest?.status === 'submitted' ? 'submitted' : null, values: (latest?.values as Record<string, unknown> | null) ?? null, review_note: latest?.review_note ?? null, submitted_at: latest?.submitted_at ?? null };
    }) : [];
    return { ...task, assignee_employee_id: task.assigned_to, position_code: (task.position_code as MobileTask['position_code'] | null) ?? role ?? null, starts_at: task.starts_at ?? task.assigned_at ?? task.created_at ?? task.due_at, status, proof_required: Boolean(task.proof_required), proof_instructions: task.proof_instructions, task_instructions: task.task_instructions, report_flow: task.report_flow === 'multi_form' ? 'multi_form' : 'legacy', execution_steps: executionSteps, report_forms: reportForms, report_schema: fieldsByTask.get(task.id) ?? [], branch_name: branchById.get(task.branch_id)?.name ?? null, branch_level: branchById.get(task.branch_id)?.branch_level ?? null };
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
  if (item.kind === 'report' && item.payload.snapshotId) await callRpc('mobile_submit_task_report_form', { p_task_id: item.payload.taskId, p_snapshot_id: item.payload.snapshotId, p_values: item.payload.values, p_idempotency_key: item.payload.idempotencyKey });
  else if (item.kind === 'report') await callRpc('mobile_submit_task_report', { p_task_id: item.payload.taskId, p_values: item.payload.values, p_idempotency_key: item.payload.idempotencyKey });
}
export function syncOfflineQueue() { return flushQueue(executeQueueItem); }

export async function updateTaskStatus(taskId: string, status: 'in_progress' | 'submitted', note: string | null = null) {
  const payload = { taskId, status, note, idempotencyKey: idempotencyKey(taskId, `status:${status}`) };
  try { await callRpc('mobile_record_task_update', { p_task_id: taskId, p_status: status, p_note: note, p_idempotency_key: payload.idempotencyKey }); }
  catch (error) { if (!isOffline(error)) throw error; await queueOperation('status', payload); }
}

export async function submitTaskReport(taskId: string, values: Record<string, unknown>, snapshotId?: string) {
  const payload = { taskId, snapshotId, values, idempotencyKey: idempotencyKey(taskId, snapshotId ? `report:${snapshotId}` : 'report') };
  try {
    if (snapshotId) await callRpc('mobile_submit_task_report_form', { p_task_id: taskId, p_snapshot_id: snapshotId, p_values: values, p_idempotency_key: payload.idempotencyKey });
    else await callRpc('mobile_submit_task_report', { p_task_id: taskId, p_values: values, p_idempotency_key: payload.idempotencyKey });
  }
  catch (error) { if (!isOffline(error)) throw error; await queueOperation('report', payload); }
}

export function saveTaskReportDraft(taskId: string, snapshotId: string, values: Record<string, unknown>) {
  return callRpc('save_task_report_draft', { p_task_id: taskId, p_snapshot_id: snapshotId, p_values: values });
}

export function completeTaskExecutionStep(stepId: string, evidenceAttachmentIds: string[] = []) {
  return callRpc('mobile_complete_task_step', { p_step_id: stepId, p_evidence_attachment_ids: evidenceAttachmentIds });
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

export function reviewTaskFormReport(reportId: string, decision: 'approved' | 'returned', note: string | null) {
  return callRpc('mobile_review_task_form_report', { p_report_id: reportId, p_decision: decision, p_note: note });
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
    task_report_required_without_fields: 'اختر نموذجًا يحتوي حقول تقرير أو اجعل التقرير اختياريًا.',
    task_title_or_due_date_invalid: 'تحقق من عنوان المهمة والموعد النهائي.',
    task_template_role_mismatch: 'قالب المهمة لا يطابق التصنيف الوظيفي المحدد.',
    no_employee_for_role: 'لا يوجد موظف نشط بهذا التصنيف في الفرع المحدد.',
    report_template_role_mismatch: 'نموذج التقرير لا يطابق تصنيف المهمة. اختر نموذجًا مطابقًا.',
    report_form_version_requires_approval: 'لا يمكن ربط المهمة إلا بإصدار معتمد من نموذج التقرير.',
    report_form_snapshot_immutable: 'للمهمة لقطة نموذج محفوظة؛ لا يمكن استبدالها بعد إنشائها.',
    report_form_fields_required: 'أضف حقلًا واحدًا على الأقل قبل اعتماد النموذج.',
    report_field_label_required: 'اسم الحقل مطلوب ولا يمكن أن يكون فارغًا.',
    report_field_options_required: 'أضف خيارًا واحدًا على الأقل لهذا الحقل.',
    report_field_below_min: 'القيمة أقل من الحد الأدنى المحدد للحقل.',
    report_field_above_max: 'القيمة أعلى من الحد الأقصى المحدد للحقل.',
    report_field_min_length: 'النص أقصر من الحد الأدنى المسموح.',
    report_field_max_length: 'النص أطول من الحد الأقصى المسموح.',
    report_field_integer_required: 'أدخل رقمًا صحيحًا دون كسور.',
    report_field_negative_not_allowed: 'القيم السالبة غير مسموحة في هذا الحقل.',
    report_field_zero_not_allowed: 'يجب أن تكون القيمة أكبر من صفر.',
    report_field_decimal_places: 'عدد المنازل العشرية يتجاوز الحد المسموح.',
    report_table_min_rows: 'أضف الحد الأدنى من الصفوف المطلوبة إلى الجدول.',
    report_table_max_rows: 'عدد صفوف الجدول يتجاوز الحد الأقصى.',
    required_report_table_cell: 'أكمل الخلايا المطلوبة في الجدول.',
    invalid_report_field_option: 'اختر قيمة من الخيارات المحددة لهذا الحقل.',
    invalid_calculated_report_value: 'قيمة الحقل المحسوب لا تطابق الصيغة. راجع الحقول المرتبطة.',
    report_calculated_division_by_zero: 'تعذر الحساب لأن المقسوم عليه يساوي صفرًا.',
    report_signature_consent_required: 'وافق على نص الإقرار قبل إرسال التوقيع.',
    report_signature_required: 'ارسم التوقيع قبل إرسال التقرير.',
    report_signature_immutable: 'حُفظ التوقيع مع التقرير ولا يمكن تعديله بعد الإرسال.',
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
