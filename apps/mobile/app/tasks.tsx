import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AppState,
  ActivityIndicator,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { supabase } from '../lib/supabase';
import { normalizeTaskStatus, taskMatchesFilter, type TaskFilter } from '../lib/homeModel';
import {
  friendlyDataError,
  getMyEmployeeProfile,
  listMyNotifications,
  listMyTasks,
  markTaskOpened,
  listTaskTimeline,
  syncOfflineQueue,
  reviewTask,
  reviewTaskFormReport,
  completeTaskExecutionStep,
  submitTaskReport,
  saveTaskReportDraft,
  updateTaskStatus,
  type MobileTaskReportForm,
} from '../lib/mobileData';
import { notifyInAppTaskReceived } from '../lib/pushNotifications';
import { pickTaskAttachment, uploadTaskAttachment, type PickedAttachment } from '../lib/taskAttachments';
import { evaluateReportField, isReportFieldVisible, normalizeTableColumns, reportDefaultDraft, validateReportFieldValue, type ReportField, type ReportTableColumn } from '../lib/reportSchema';
import ReportFieldInput from '../components/ReportFieldInput';
import ReportReadOnly from '../components/ReportReadOnly';
import EmployeeRoleReportPanel from '../components/EmployeeRoleReportPanel';
import EmployeeDynamicReportsPanel from '../components/EmployeeDynamicReportsPanel';
import ReportSubmissionEmployeePanel from '../components/ReportSubmissionEmployeePanel';
import AppShell from '../components/AppShell';
import CompactExpandableCard from '../components/CompactExpandableCard';
import { readSessionCache, writeSessionCache } from '../lib/mobileSessionCache';

type Task = {
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
  delivery_status: 'sent' | 'received' | 'opened';
  proof_required: boolean;
  proof_instructions: string | null;
  report_schema: ReportField[];
  task_instructions: string | null;
  report_flow: 'legacy' | 'multi_form';
  legacy_report_values: Record<string, unknown> | null;
  execution_steps: Array<{ id: string; title: string; instructions: string | null; sort_order: number; required: boolean; evidence_required: boolean; evidence_instructions: string | null; completed: boolean }>;
  report_forms: MobileTaskReportForm[];
};
type Notification = { id: string; title: string; body: string; severity: string; read_at: string | null; created_at: string };

type TasksSearchParams = {
  status?: string | string[];
  branchId?: string | string[];
  mode?: string | string[];
  view?: string | string[];
};

function firstSearchParam(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function isDynamicTestTitle(value: string) {
  const title = value.trim().toLocaleLowerCase('ar');
  return title.includes('اختبار مهمة ديناميكية') || title.includes('اختبار تقرير ديناميكي');
}

function parseTaskFilter(value: string | undefined): TaskFilter {
  return value === 'pending' || value === 'in_progress' || value === 'submitted' || value === 'rejected' || value === 'approved' || value === 'late' ? value : 'all';
}

function parseBranchId(value: string | undefined) {
  const normalized = value?.trim();
  return normalized || '';
}

function parseTaskMode(value: string | undefined): 'all' | 'mine' | undefined {
  return value === 'all' || value === 'mine' ? value : undefined;
}

const statusLabels: Record<Task['status'], string> = {
  pending: 'معلقة', in_progress: 'قيد التنفيذ', submitted: 'بانتظار المراجعة',
  approved: 'معتمدة', rejected: 'تحتاج استكمالًا', cancelled: 'ملغاة', late: 'متأخرة',
};
const priorityLabels: Record<Task['priority'], string> = { normal: 'عادية', important: 'مهمة', urgent: 'عاجلة', critical: 'حرجة' };
const positionLabels: Record<NonNullable<Task['position_code']>, string> = {
  owner: 'صاحب المؤسسة', admin_followup: 'المدير التنفيذي', accountant: 'المحاسب',
  warehouse_keeper: 'أمين المخازن', warehouse_worker: 'عمال التحميل',
};
const deliveryLabels: Record<Task['delivery_status'], string> = { sent: 'أُرسلت للموظف', received: 'تم الاستلام', opened: 'تم فتح المهمة' };

export default function TasksScreen() {
  // Employee flow: read task, execute steps, complete the requested report.
  const router = useRouter();
  const routeParams = useLocalSearchParams<TasksSearchParams>();
  const requestedStatus = parseTaskFilter(firstSearchParam(routeParams.status));
  const requestedBranchId = parseBranchId(firstSearchParam(routeParams.branchId));
  const requestedMode = parseTaskMode(firstSearchParam(routeParams.mode));
  const reportsOnly = firstSearchParam(routeParams.view) === 'reports';
  const [tasks, setTasks] = useState<Task[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [canReview, setCanReview] = useState(false);
  const [canManage, setCanManage] = useState(false);
  const [canManageReports, setCanManageReports] = useState(false);
  const [currentUserId, setCurrentUserId] = useState('');
  const [employeeRoleCode, setEmployeeRoleCode] = useState('accountant');
  const [employeeName, setEmployeeName] = useState('');
  const [employeeBranchId, setEmployeeBranchId] = useState<string | null>(null);
  const [screenMode, setScreenMode] = useState<'mine' | 'all' | 'review'>('mine');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [busyTask, setBusyTask] = useState('');
  const [reportTask, setReportTask] = useState('');
  const [activeReportForm, setActiveReportForm] = useState<{ taskId: string; snapshotId: string } | null>(null);
  const [drafts, setDrafts] = useState<Record<string, Record<string, string>>>({});
  const [reviewNote, setReviewNote] = useState('');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<Task['status'] | 'all'>('all');
  const [reportStatusFilter, setReportStatusFilter] = useState<'all' | 'ready' | 'uploaded' | 'approved'>('all');
  const [branchFilter, setBranchFilter] = useState('');
  const [positionFilter, setPositionFilter] = useState<Task['position_code'] | 'all'>('all');
  const [previewTaskId, setPreviewTaskId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [inAppNotification, setInAppNotification] = useState<{ taskId: string; title: string } | null>(null);
  const [attachments, setAttachments] = useState<Record<string, Record<string, Array<PickedAttachment & { path?: string }>>>>({});
  const [stepAttachments, setStepAttachments] = useState<Record<string, Record<string, { id: string; name: string }>>>({});
  const [timeline, setTimeline] = useState<Record<string, Awaited<ReturnType<typeof listTaskTimeline>>>>({});
  const lastLoadAt = useRef(0);
  const loadInFlight = useRef(false);
  const notifiedTaskIds = useRef(new Set<string>());
  const openedTaskIds = useRef(new Set<string>());

  const applyTaskRows = useCallback((taskRows: Task[]) => {
    setTasks(taskRows);
    setDrafts((current) => {
      const next = { ...current };
      for (const task of taskRows) {
        const taskDraft = { ...(next[task.id] ?? {}) };
        for (const field of task.report_schema ?? []) {
          if (taskDraft[field.key] === undefined) taskDraft[field.key] = reportDefaultDraft(field);
        }
        for (const form of task.report_forms ?? []) {
          const formKey = formDraftKey(task, form);
          const formDraft = { ...(next[formKey] ?? {}) };
          for (const field of form.schema) {
            const persisted = form.draft_values?.[field.key];
            if (persisted !== undefined && formDraft[field.key] === undefined) formDraft[field.key] = typeof persisted === 'string' ? persisted : JSON.stringify(persisted);
            if (formDraft[field.key] === undefined) formDraft[field.key] = reportDefaultDraft(field);
          }
          next[formKey] = formDraft;
        }
        next[task.id] = taskDraft;
      }
      return next;
    });
  }, []);

  const load = useCallback(async ({ force = false }: { force?: boolean } = {}) => {
    if (loadInFlight.current) return;
    if (!force && Date.now() - lastLoadAt.current < 15_000) return;
    loadInFlight.current = true;
    setError('');
    try {
      await syncOfflineQueue();
      const identity = await getMyEmployeeProfile();
      if (!identity) throw new Error('not_authenticated');
      if (!identity.employee) throw new Error('employee_not_active');
      setCurrentUserId(identity.userId);
      setEmployeeName(identity.employee.fullName);
      setEmployeeRoleCode(identity.employee.roles[0]?.code ?? 'accountant');
      setEmployeeBranchId(identity.employee.branches.find((branch) => branch.isDefault)?.id ?? identity.employee.branches[0]?.id ?? null);
      const permissions = new Set(identity.employee.permissions);
      if (!permissions.has('tasks.execute') && !permissions.has('tasks.manage')) throw new Error('permission_denied');
      const canReviewNow = permissions.has('tasks.review');
      const canManageNow = permissions.has('tasks.manage');
      const cacheKey = `${identity.userId}:${identity.employee.institutionId}`;
      const cachedTasks = readSessionCache<Task[]>('employee-tasks', cacheKey);
      const cachedNotifications = readSessionCache<Notification[]>('employee-notifications', cacheKey);
      setCanReview(canReviewNow);
      setCanManage(canManageNow);
      setCanManageReports(permissions.has('report_forms.manage'));
      if (cachedTasks) {
        applyTaskRows(cachedTasks);
        setLoading(false);
        setNotice('تُعرض آخر بيانات ناجحة، جارٍ التحديث في الخلفية…');
      }
      if (cachedNotifications) setNotifications(cachedNotifications);
      const [taskResult, notificationResult] = await Promise.allSettled([listMyTasks(identity.employee.institutionId, canManageNow || canReviewNow ? undefined : identity.userId), listMyNotifications()]);
      if (taskResult.status === 'rejected') throw taskResult.reason;
      const taskRows = taskResult.value;
      const notificationRows = notificationResult.status === 'fulfilled' ? notificationResult.value : cachedNotifications ?? [];
      applyTaskRows(taskRows);
      writeSessionCache('employee-tasks', cacheKey, taskRows);
      setNotifications(notificationRows);
      if (notificationResult.status === 'fulfilled') writeSessionCache('employee-notifications', cacheKey, notificationRows);
      if (notificationResult.status === 'rejected' && !cachedNotifications) setNotice('تم تحميل المهام، وتعذر تحديث التنبيهات مؤقتًا.');
      if (cachedTasks) setNotice('تم تحديث البيانات المعروضة في الخلفية.');
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر تحميل البيانات مباشرة من Supabase. تحقق من الاتصال والصلاحيات.'));
    } finally {
      lastLoadAt.current = Date.now();
      loadInFlight.current = false;
      setLoading(false);
      setRefreshing(false);
    }
  }, [applyTaskRows]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    if (!currentUserId) return;
    setScreenMode(requestedMode === 'all' && (canManage || canReview) ? 'all' : 'mine');
    setStatusFilter(requestedStatus);
    setBranchFilter(requestedBranchId);
  }, [canManage, canReview, currentUserId, requestedBranchId, requestedMode, requestedStatus]);
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') void load();
    });
    return () => subscription.remove();
  }, [load]);
  useEffect(() => {
    if (!supabase || !currentUserId) return;
    const client = supabase;
    let refreshTimer: ReturnType<typeof setTimeout> | null = null;
    const scheduleRefresh = (payload?: { eventType?: string; new?: Record<string, unknown> }) => {
      if (payload?.eventType === 'INSERT') {
        const taskId = typeof payload.new?.id === 'string' ? payload.new.id : '';
        if (taskId && !notifiedTaskIds.current.has(taskId)) {
          notifiedTaskIds.current.add(taskId);
          const title = typeof payload.new?.title === 'string' ? payload.new.title : 'مهمة جديدة';
          setInAppNotification({ taskId, title });
          void notifyInAppTaskReceived(title);
        }
      }
      if (refreshTimer) clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => {
        refreshTimer = null;
        void load({ force: true });
      }, 450);
    };
    const channel = client
      .channel(`employee-task-feed:${currentUserId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks', filter: `assigned_to=eq.${currentUserId}` }, scheduleRefresh)
      .subscribe();
    return () => {
      if (refreshTimer) clearTimeout(refreshTimer);
      void client.removeChannel(channel);
    };
  }, [currentUserId, load]);
  useEffect(() => {
    if (!inAppNotification) return;
    const timer = setTimeout(() => setInAppNotification(null), 10_000);
    return () => clearTimeout(timer);
  }, [inAppNotification]);
  useEffect(() => {
    if (!currentUserId || reportsOnly) return;
    for (const task of tasks.filter((item) => item.assignee_employee_id === currentUserId && item.delivery_status !== 'opened')) {
      if (openedTaskIds.current.has(task.id)) continue;
      openedTaskIds.current.add(task.id);
      void markTaskOpened(task.id).then(() => {
        setTasks((current) => current.map((item) => item.id === task.id ? { ...item, delivery_status: 'opened' } : item));
      }).catch(() => { openedTaskIds.current.delete(task.id); });
    }
  }, [currentUserId, reportsOnly, tasks]);
  useEffect(() => {
    const timer = setInterval(() => void load(), 60_000);
    return () => clearInterval(timer);
  }, [load]);

  async function mutate(task: Task, operation: () => Promise<void>, successMessage: string) {
    setBusyTask(task.id);
    setError('');
    setNotice('');
    try {
      await operation();
      setNotice(successMessage);
      setReportTask('');
      setActiveReportForm(null);
      setReviewNote('');
      await load({ force: true });
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر تنفيذ الإجراء عبر Supabase. تحقق من الاتصال والصلاحيات.'));
    } finally {
      setBusyTask('');
    }
  }

  function draftValuesForTask(task: Task, strict = false): Record<string, unknown> {
    const values: Record<string, unknown> = {};
    try {
      for (const field of task.report_schema ?? []) {
        if (!isReportFieldVisible(field, values)) continue;
        if (field.type === 'calculated') continue;
        const raw = drafts[task.id]?.[field.key]?.trim() ?? '';
        if (field.type === 'datetime' && field.config?.auto_now === true) { values[field.key] = new Date().toISOString(); continue; }
        if (['attachment', 'image', 'multi_image', 'file'].includes(field.type)) {
          if (attachments[task.id]?.[field.key]?.length) values[field.key] = attachments[task.id][field.key];
        } else if (field.type === 'table' || field.type === 'multiselect' || field.type === 'signature') {
          if (!raw) continue;
          values[field.key] = JSON.parse(raw) as unknown;
        } else if (field.type === 'boolean' || field.type === 'checkbox') {
          if (raw === 'true' || raw === 'false') values[field.key] = raw === 'true';
          else if (raw) values[field.key] = raw;
        } else if (['number', 'progress', 'integer', 'quantity', 'money'].includes(field.type)) {
          if (raw) values[field.key] = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw) ? Number(raw) : raw;
        } else if (raw) values[field.key] = raw;
      }
    } catch (cause) {
      if (strict) throw new Error(`تحقق من تنسيق الحقل المركب: ${(cause as Error).message}`);
    }
    for (const field of task.report_schema ?? []) {
      if (field.type !== 'calculated') continue;
      const calculated = evaluateReportField(field, task.report_schema, values);
      if (calculated.value !== null) values[field.key] = calculated.value;
      else if (strict) throw new Error(`تعذر حساب «${field.label}»: ${calculated.error ?? 'تحقق من الحقول المرتبطة.'}`);
    }
    return values;
  }
  function submitReport(task: Task) {
    let values: Record<string, unknown>;
    try { values = draftValuesForTask(task, true); }
    catch (cause) { setError((cause as Error).message); return; }
    for (const field of task.report_schema ?? []) {
      const issue = validateReportFieldValue(field, values[field.key]);
      if (issue) { setError(issue); return; }
    }
    void mutate(task, () => submitTaskReport(task.id, values), 'تم إرسال التقرير للمراجعة.');
  }

  function formDraftKey(task: Task, form: MobileTaskReportForm) { return `${task.id}:${form.snapshot_id}`; }
  function valuesForReportForm(task: Task, form: MobileTaskReportForm, strict = false): Record<string, unknown> {
    const key = formDraftKey(task, form);
    const values: Record<string, unknown> = {};
    try {
      for (const field of form.schema) {
        if (!isReportFieldVisible(field, values)) continue;
        if (field.type === 'calculated') continue;
        const raw = drafts[key]?.[field.key]?.trim() ?? '';
        if (field.type === 'datetime' && field.config?.auto_now === true) { values[field.key] = new Date().toISOString(); continue; }
        if (['attachment', 'image', 'multi_image', 'file'].includes(field.type)) {
          if (attachments[key]?.[field.key]?.length) values[field.key] = attachments[key][field.key];
        } else if (field.type === 'table' || field.type === 'multiselect' || field.type === 'signature') {
          if (raw) values[field.key] = JSON.parse(raw) as unknown;
        } else if (field.type === 'boolean' || field.type === 'checkbox') {
          if (raw === 'true' || raw === 'false') values[field.key] = raw === 'true';
          else if (raw) values[field.key] = raw;
        } else if (['number', 'progress', 'integer', 'quantity', 'money'].includes(field.type)) {
          if (raw) values[field.key] = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw) ? Number(raw) : raw;
        } else if (raw) values[field.key] = raw;
      }
    } catch (cause) { if (strict) throw new Error(`تحقق من تنسيق الحقل المركب: ${(cause as Error).message}`); }
    for (const field of form.schema) if (field.type === 'calculated') {
      const calculated = evaluateReportField(field, form.schema, values);
      if (calculated.value !== null) values[field.key] = calculated.value;
      else if (strict) throw new Error(`تعذر حساب «${field.label}»: ${calculated.error ?? 'تحقق من الحقول المرتبطة.'}`);
    }
    return values;
  }
  async function saveSeparateDraft(task: Task, form: MobileTaskReportForm) {
    try {
      const values = valuesForReportForm(task, form);
      await saveTaskReportDraft(task.id, form.snapshot_id, values);
      setNotice(`تم حفظ مسودة «${form.title}» على الجهاز والخادم.`);
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر حفظ مسودة التقرير.')); }
  }

  function submitSeparateReport(task: Task, form: MobileTaskReportForm) {
    let values: Record<string, unknown>;
    try { values = valuesForReportForm(task, form, true); }
    catch (cause) { setError((cause as Error).message); return; }
    for (const field of form.schema) { const issue = validateReportFieldValue(field, values[field.key]); if (issue) { setError(issue); return; } }
    void mutate(task, () => submitTaskReport(task.id, values, form.snapshot_id), `تم إرسال «${form.title}» للمراجعة بصورة مستقلة.`);
  }

  function tableColumns(field: ReportField): ReportTableColumn[] {
    const columns = normalizeTableColumns(field);
    return columns.length ? columns : [{ key: 'value', label: 'القيمة', type: 'short_text', required: false }];
  }
  function tableRows(taskId: string, field: ReportField): Array<Record<string, unknown>> {
    const raw = drafts[taskId]?.[field.key] ?? '[]';
    try { const parsed = JSON.parse(raw); return Array.isArray(parsed) ? parsed as Array<Record<string, unknown>> : []; }
    catch { return []; }
  }
  function updateTable(taskId: string, field: ReportField, rows: Array<Record<string, unknown>>) {
    setDrafts((current) => ({ ...current, [taskId]: { ...current[taskId], [field.key]: JSON.stringify(rows) } }));
  }
  function calculatedValue(taskId: string, field: ReportField) {
    const task = tasks.find((candidate) => candidate.id === taskId);
    return task ? evaluateReportField(field, task.report_schema, draftValuesForTask(task)).value : null;
  }
  function calculationError(taskId: string, field: ReportField) {
    const task = tasks.find((candidate) => candidate.id === taskId);
    return task ? evaluateReportField(field, task.report_schema, draftValuesForTask(task)).error : null;
  }

  async function chooseAttachment(task: Task, fieldKey: string) {
    try {
      const file = await pickTaskAttachment();
      if (!file) return;
      const uploaded = await uploadTaskAttachment(task.id, file);
      setAttachments((current) => ({
        ...current,
        [task.id]: {
          ...current[task.id],
          [fieldKey]: [...(current[task.id]?.[fieldKey] ?? []), { ...file, ...uploaded }],
        },
      }));
      setNotice('تم رفع المرفق وتجهيزه للتقرير.');
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر رفع المرفق. تأكد من الاتصال وحجم الملف.')); }
  }
  async function chooseFormAttachment(task: Task, form: MobileTaskReportForm, fieldKey: string) {
    const draftKey = formDraftKey(task, form);
    try {
      const file = await pickTaskAttachment();
      if (!file) return;
      const uploaded = await uploadTaskAttachment(task.id, file);
      setAttachments((current) => ({ ...current, [draftKey]: { ...current[draftKey], [fieldKey]: [...(current[draftKey]?.[fieldKey] ?? []), { ...file, ...uploaded }] } }));
      setNotice('تم رفع المرفق وتجهيزه لنموذج التقرير المحدد.');
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر رفع المرفق. تأكد من الاتصال وحجم الملف.')); }
  }
  async function chooseStepEvidence(task: Task, stepId: string) {
    try {
      const file = await pickTaskAttachment();
      if (!file) return;
      const uploaded = await uploadTaskAttachment(task.id, file, stepId);
      setStepAttachments((current) => ({ ...current, [task.id]: { ...current[task.id], [stepId]: { id: uploaded.id, name: uploaded.name } } }));
      setNotice('تم رفع الإثبات وربطه بخطوة التنفيذ. أكمل الخطوة لتسجيله.');
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر رفع إثبات الخطوة.')); }
  }
  async function showTimeline(task: Task) {
    try { const rows = await listTaskTimeline(task.id); setTimeline((current) => ({ ...current, [task.id]: rows })); }
    catch (cause) { setError(friendlyDataError(cause, 'تعذر تحميل سجل المهمة.')); }
  }

  async function signOut() {
    try {
      if (!supabase) throw new Error('supabase_unavailable');
      const { error: signOutError } = await supabase.auth.signOut();
      if (signOutError) throw signOutError;
      router.replace('/');
    } catch {
      setError('تعذر تسجيل الخروج. تحقق من الاتصال ثم حاول مرة أخرى.');
    }
  }

  const formatDate = (value: string) => {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? 'غير محدد' : new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium', timeStyle: 'short' }).format(date);
  };
  const filteredTasks = tasks.filter((task) => {
    const hasPendingFormReview = task.report_forms.some((form) => form.status === 'submitted');
    const hasReport = task.report_forms.length > 0 || task.report_schema.length > 0;
    const hasReadyReport = task.report_forms.some((form) => !['submitted', 'approved'].includes(form.status ?? '')) || (!task.report_forms.length && !['submitted', 'approved'].includes(task.status));
    const hasUploadedReport = task.report_forms.some((form) => form.status === 'submitted') || (!task.report_forms.length && task.status === 'submitted');
    const hasApprovedReport = task.report_forms.some((form) => form.status === 'approved') || (!task.report_forms.length && task.status === 'approved');
    const reportStatusMatches = reportStatusFilter === 'all' || (reportStatusFilter === 'ready' && hasReadyReport) || (reportStatusFilter === 'uploaded' && hasUploadedReport) || (reportStatusFilter === 'approved' && hasApprovedReport);
    const modeMatches = reportsOnly
      ? task.assignee_employee_id === currentUserId
      : screenMode === 'mine'
        ? task.assignee_employee_id === currentUserId
        : screenMode === 'review'
          ? canReview && (task.status === 'submitted' || hasPendingFormReview)
          : canManage || canReview;
    return modeMatches &&
      !isDynamicTestTitle(task.title) &&
      (reportsOnly || taskMatchesFilter(task, statusFilter)) &&
      (reportsOnly || screenMode === 'mine' || !branchFilter || task.branch_id === branchFilter) &&
      (reportsOnly || positionFilter === 'all' || task.position_code === positionFilter) &&
      (!reportsOnly || hasReport) &&
      (!reportsOnly || !isDynamicTestTitle(task.title)) &&
      (!reportsOnly || reportStatusMatches) &&
      (!search.trim() || `${task.title} ${task.description ?? ''}`.toLocaleLowerCase('ar').includes(search.trim().toLocaleLowerCase('ar')));
  });
  const employeeSummary = {
    pending: filteredTasks.filter((task) => ['pending', 'rejected'].includes(normalizeTaskStatus(task.status))).length,
    active: filteredTasks.filter((task) => taskMatchesFilter(task, 'in_progress')).length,
    submitted: filteredTasks.filter((task) => taskMatchesFilter(task, 'submitted')).length,
  };

  return (
    <AppShell activeTab="tasks" title={reportsOnly ? 'إعداد التقارير' : 'المهام والمتابعة'} scroll={false}>
      <Stack.Screen options={{ title: 'المهام', headerShown: false }} />
      <ScrollView
        contentContainerStyle={styles.content}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); void load({ force: true }); }} />}
      >
        {!!error && <View style={styles.errorBox}><Text accessibilityRole="alert" style={styles.error}>{error}</Text><Pressable style={styles.retryButton} onPress={() => { setRefreshing(true); void load({ force: true }); }}><Text style={styles.retryText}>إعادة المحاولة</Text></Pressable></View>}
        {!!notice && <Text accessibilityLiveRegion="polite" style={styles.notice}>{notice}</Text>}
        {!!inAppNotification && <View accessibilityLiveRegion="polite" style={styles.newTaskNotice}>
          <View style={styles.newTaskNoticeCopy}><Text style={styles.newTaskNoticeTitle}>مهمة جديدة</Text><Text style={styles.newTaskNoticeText}>{inAppNotification.title}</Text><Text style={styles.newTaskNoticeHint}>تم إسنادها إليك ويمكنك البدء بها الآن.</Text></View>
          <View style={styles.newTaskNoticeActions}><Pressable style={styles.newTaskOpenButton} onPress={() => { setInAppNotification(null); setStatusFilter('all'); }}><Text style={styles.newTaskOpenText}>فتح المهمة</Text></Pressable><Pressable accessibilityLabel="إخفاء تنبيه المهمة الجديدة" style={styles.newTaskDismissButton} onPress={() => setInAppNotification(null)}><Text style={styles.newTaskDismissText}>إخفاء</Text></Pressable></View>
        </View>}
        {!loading && !reportsOnly && <View style={styles.employeeIntro}><Text style={styles.employeeIntroTitle}>مساحة تنفيذك اليومية</Text><Text style={styles.employeeIntroText}>اقرأ التكليف، ابدأ التنفيذ، ثم عبّئ التقرير المطلوب وأرسله للمسؤول للمراجعة.</Text></View>}
        {!loading && <View style={styles.workTabs}><Pressable accessibilityRole="tab" accessibilityState={{ selected: !reportsOnly }} style={[styles.workTab, !reportsOnly && styles.workTabSelected]} onPress={() => router.replace({ pathname: '/tasks', params: { mode: 'mine' } })}><Text style={[styles.workTabText, !reportsOnly && styles.workTabTextSelected]}>المهام</Text></Pressable><Pressable accessibilityRole="tab" accessibilityState={{ selected: reportsOnly }} style={[styles.workTab, reportsOnly && styles.workTabSelected]} onPress={() => router.replace({ pathname: '/tasks', params: { view: 'reports', mode: 'mine' } })}><Text style={[styles.workTabText, reportsOnly && styles.workTabTextSelected]}>إعداد التقارير</Text></Pressable></View>}
        {!loading && reportsOnly && <><View style={styles.reportUploadHeader}><Text style={styles.reportUploadTitle}>تقارير المهام</Text><Text style={styles.reportUploadSubtitle}>التقارير التي صممتها الإدارة وربطتها بالمهام. افتح الحقول، عبئها، ثم أرسل التقرير للمراجعة.</Text></View><View style={styles.reportStatusTabs}>{([['all', 'الكل'], ['ready', 'جاهز للرفع'], ['uploaded', 'تم الرفع'], ['approved', 'معتمد']] as const).map(([value, label]) => <Pressable key={value} accessibilityRole="button" accessibilityState={{ selected: reportStatusFilter === value }} style={[styles.reportStatusTab, reportStatusFilter === value && styles.reportStatusTabSelected]} onPress={() => setReportStatusFilter(value)}><Text style={reportStatusFilter === value ? styles.reportStatusTabTextSelected : styles.reportStatusTabText}>{label}</Text></Pressable>)}</View></>}
        {!loading && !reportsOnly && <View style={styles.summaryRow}><View style={styles.summaryCard}><Text style={styles.summaryValue}>{employeeSummary.pending}</Text><Text style={styles.summaryLabel}>جديدة</Text></View><View style={styles.summaryCard}><Text style={styles.summaryValue}>{employeeSummary.active}</Text><Text style={styles.summaryLabel}>قيد التنفيذ</Text></View><View style={styles.summaryCard}><Text style={styles.summaryValue}>{employeeSummary.submitted}</Text><Text style={styles.summaryLabel}>بانتظار المراجعة</Text></View></View>}
        {!loading && reportsOnly && <View style={styles.independentReportSection}><View style={styles.reportUploadHeader}><Text style={styles.reportUploadTitle}>تقارير مصمم التقارير</Text><Text style={styles.reportUploadSubtitle}>النماذج التي اعتمدتها الإدارة من مصمم التقارير. تعبئتها مستقلة عن المهام وتُرسل مرة واحدة للمراجعة.</Text></View><ReportSubmissionEmployeePanel branchId={employeeBranchId} canManageReports={canManageReports && canManage} /><View style={styles.reportUploadHeader}><Text style={styles.reportUploadTitle}>التقارير اليومية من الإدارة</Text><Text style={styles.reportUploadSubtitle}>تقرير مستقل عن المهام، يصل حسب الدور والفرع ويُرسل مرة واحدة للمراجعة.</Text></View><EmployeeRoleReportPanel roleCode={employeeRoleCode} branchId={employeeBranchId} employeeName={employeeName} /></View>}
        {loading && <View style={styles.loading}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.muted}>جارٍ تحميل المهام…</Text></View>}
        {!loading && !reportsOnly && (canReview || canManage) && <View style={styles.modeTabs}>
          {([
            ['mine', 'مهامي'],
            ['review', 'مراجعة التقارير'],
            ['all', 'متابعة جميع المهام'],
          ] as const).filter(([mode]) => mode === 'mine' || (mode === 'review' ? canReview : canManage || canReview)).map(([mode, label]) => <Pressable key={mode} accessibilityRole="button" accessibilityState={{ selected: screenMode === mode }} style={[styles.modeTab, screenMode === mode && styles.modeTabSelected]} onPress={() => { setScreenMode(mode); setStatusFilter('all'); setPositionFilter('all'); }}><Text style={[styles.modeTabText, screenMode === mode && styles.modeTabTextSelected]}>{label}</Text></Pressable>)}
        </View>}

        {!loading && !reportsOnly && screenMode !== 'mine' && !!branchFilter && <View style={styles.activeFilter}><Text style={styles.meta}>الفرع المحدد: {tasks.find((task) => task.branch_id === branchFilter)?.branch_name ?? 'الفرع المحدد'}</Text><Pressable accessibilityRole="button" onPress={() => setBranchFilter('')} style={styles.clearFilterButton}><Text style={styles.clearFilterText}>مسح الفرع</Text></Pressable></View>}
        {!loading && !reportsOnly && tasks.length > 0 && <>
          <TextInput style={styles.input} value={search} onChangeText={setSearch} placeholder="ابحث عن مهمة…" accessibilityLabel="البحث في المهام" />
          {canReview && screenMode !== 'mine' && <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filters}>
            {([['all', 'كل المناصب'], ['owner', 'صاحب المؤسسة'], ['admin_followup', 'المدير التنفيذي'], ['accountant', 'المحاسب'], ['warehouse_keeper', 'أمين المخازن'], ['warehouse_worker', 'عمال التحميل']] as const).map(([code, label]) => {
              const selected = positionFilter === code;
              return <Pressable key={code} accessibilityRole="button" accessibilityState={{ selected }} style={[styles.filterChip, selected && styles.filterChipSelected]} onPress={() => setPositionFilter(code)}>
                <Text style={selected ? styles.filterChipTextSelected : styles.filterChipText}>{label}</Text>
              </Pressable>;
            })}
          </ScrollView>}
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filters}>
            {(['all', 'pending', 'in_progress', 'submitted', 'rejected', 'approved', 'late'] as const).map((status) => {
              const selected = statusFilter === status;
              return <Pressable key={status} accessibilityRole="button" accessibilityState={{ selected }} style={[styles.filterChip, selected && styles.filterChipSelected]} onPress={() => setStatusFilter(status)}>
                <Text style={selected ? styles.filterChipTextSelected : styles.filterChipText}>{status === 'all' ? 'الكل' : statusLabels[status]}</Text>
              </Pressable>;
            })}
          </ScrollView>
        </>}

        {!loading && filteredTasks.map((task) => (
          <CompactExpandableCard key={task.id} title={task.title} subtitle={`${task.branch_name || 'كل الفروع'} · ${priorityLabels[task.priority]}`} status={reportsOnly ? 'إعداد التقارير' : statusLabels[task.status]}>
            {reportsOnly && <View style={styles.reportWorkspace}>
              {!!task.report_forms.length && task.report_forms.map((form) => {
                const key = formDraftKey(task, form);
                const locked = form.status === 'submitted' || form.status === 'approved';
                const formValues = valuesForReportForm(task, form);
                const formStatus = form.status === 'approved' ? 'تم اعتماد التقرير' : form.status === 'submitted' ? 'تم إرسال التقرير — بانتظار مراجعة الإدارة' : form.status === 'returned' ? 'أعيد للتعديل من الإدارة' : 'جاهز للتعبئة';
                return <View key={form.snapshot_id} style={styles.directReportForm}>
                  <View style={styles.taskHeading}><Text style={styles.reportFormTitle}>{form.title}</Text><Text style={[styles.badge, form.status === 'approved' ? styles.goodBadge : form.status === 'returned' ? styles.warnBadge : styles.neutralBadge]}>{formStatus}</Text></View>
                  {form.status === 'returned' && !!form.review_note && <Text style={styles.proof}>ملاحظة الإدارة: {form.review_note}</Text>}
                  {locked ? <ReportReadOnly fields={form.schema} values={form.values} /> : form.schema.filter((field) => isReportFieldVisible(field, formValues)).map((field) => <ReportFieldInput key={field.key} field={field} raw={drafts[key]?.[field.key] ?? ''} attachments={attachments[key]?.[field.key] ?? []} calculated={evaluateReportField(field, form.schema, formValues).value} calculationError={evaluateReportField(field, form.schema, formValues).error} rows={field.type === 'table' ? tableRows(key, field) : []} onDraftChange={(value) => setDrafts((current) => ({ ...current, [key]: { ...current[key], [field.key]: value } }))} onTableChange={(rows) => updateTable(key, field, rows)} onChooseAttachment={() => void chooseFormAttachment(task, form, field.key)} />)}
                  {!locked && <><Pressable style={styles.secondaryButton} onPress={() => void saveSeparateDraft(task, form)}><Text style={styles.secondaryText}>حفظ المسودة</Text></Pressable><Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => submitSeparateReport(task, form)}><Text style={styles.primaryText}>{busyTask === task.id ? 'جارٍ الإرسال…' : 'إرسال التقرير مرة واحدة'}</Text></Pressable></>}
                </View>;
              })}
              {!task.report_forms.length && !!task.report_schema.length && <View style={styles.directReportForm}>
                {task.status === 'submitted' || task.status === 'approved' ? <ReportReadOnly fields={task.report_schema} values={task.legacy_report_values ?? {}} /> : <>{task.report_schema.filter((field) => isReportFieldVisible(field, draftValuesForTask(task))).map((field) => <ReportFieldInput key={field.key} field={field} raw={drafts[task.id]?.[field.key] ?? ''} attachments={attachments[task.id]?.[field.key] ?? []} calculated={calculatedValue(task.id, field)} calculationError={calculationError(task.id, field)} rows={field.type === 'table' ? tableRows(task.id, field) : []} onDraftChange={(value) => setDrafts((current) => ({ ...current, [task.id]: { ...current[task.id], [field.key]: value } }))} onTableChange={(rows) => updateTable(task.id, field, rows)} onChooseAttachment={() => void chooseAttachment(task, field.key)} />)}<Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => submitReport(task)}><Text style={styles.primaryText}>{busyTask === task.id ? 'جارٍ الإرسال…' : 'إرسال التقرير مرة واحدة'}</Text></Pressable></>}
              </View>}
            </View>}
            {!reportsOnly && <>
            <Pressable accessibilityRole="button" accessibilityState={{ expanded: previewTaskId === task.id }} style={styles.previewButton} onPress={() => setPreviewTaskId((current) => current === task.id ? null : task.id)}><Text style={styles.previewButtonText}>{previewTaskId === task.id ? 'إخفاء المعاينة المنظمة' : 'معاينة المهمة في حقول منظمة'}</Text><Text style={styles.previewButtonHint}>عرض سريع وواضح قبل بدء التنفيذ</Text></Pressable>
            {previewTaskId === task.id && <TaskStructuredPreview task={task} formatDate={formatDate} />}
            <Text style={styles.cardSectionLabel}>1 · اقرأ التكليف</Text>
            {!!task.description && <Text style={styles.body}>{task.description}</Text>}
            <Text style={styles.meta}>المنصب: {task.position_code ? positionLabels[task.position_code] : 'بحاجة إلى تصنيف'}{task.branch_name ? ` · الفرع: ${task.branch_name}${task.branch_level ? ` (المستوى ${task.branch_level})` : ''}` : task.branch_id ? ' · فرع محدد' : ''}</Text>
            <Text style={styles.meta}>الأولوية: {priorityLabels[task.priority]} · الموعد: {formatDate(task.due_at)}</Text>
            <Text style={styles.deliveryStatus}>حالة الوصول: {deliveryLabels[task.delivery_status]}</Text>
            {task.proof_required && <Text style={styles.proof}>{task.proof_instructions || 'يتطلب إرفاق دليل إنجاز.'}</Text>}
            {(!!task.task_instructions || !!task.execution_steps.length) && <Text style={styles.cardSectionLabel}>2 · نفّذ المهمة</Text>}
            {!!task.task_instructions && <View style={styles.timeline}><Text style={styles.fieldLabel}>تعليمات التنفيذ</Text><Text style={styles.body}>{task.task_instructions}</Text></View>}
            {!!task.execution_steps.length && <View style={styles.timeline}><Text style={styles.fieldLabel}>خطوات التنفيذ</Text>{task.execution_steps.map((step,index)=><View key={step.id} style={styles.stepCard}>
              <Text style={styles.fieldLabel}>{index+1}. {step.title}{step.required?' · إلزامية':' · اختيارية'}{step.completed?' · مكتملة':''}</Text>
              {!!step.instructions && <Text style={styles.body}>{step.instructions}</Text>}
              {step.evidence_required && <Text style={styles.proof}>{step.evidence_instructions || 'أرفق إثباتًا قبل إكمال هذه الخطوة.'}</Text>}
              {!step.completed && step.evidence_required && <><Pressable style={styles.secondaryButton} onPress={()=>void chooseStepEvidence(task,step.id)}><Text style={styles.secondaryText}>{stepAttachments[task.id]?.[step.id]?.name ?? 'اختيار إثبات للخطوة'}</Text></Pressable>{!!stepAttachments[task.id]?.[step.id] && <Text style={styles.meta}>المرفق جاهز: {stepAttachments[task.id][step.id].name}</Text>}</>}
              {!step.completed && <Pressable disabled={busyTask===task.id || (step.evidence_required&&!stepAttachments[task.id]?.[step.id])} style={[styles.primaryButton,{opacity:step.evidence_required&&!stepAttachments[task.id]?.[step.id]?0.5:1}]} onPress={()=>void mutate(task,()=>completeTaskExecutionStep(step.id,stepAttachments[task.id]?.[step.id]?[stepAttachments[task.id][step.id].id]:[]),'تم تسجيل إكمال الخطوة.') }><Text style={styles.primaryText}>إكمال الخطوة</Text></Pressable>}
            </View>)}</View>}
            {!!task.report_forms.length || !!task.report_schema.length ? <View style={styles.reportSeparationNotice}><Text style={styles.reportSeparationTitle}>التقرير في تبويب إعداد التقارير</Text><Text style={styles.reportSeparationText}>تنفيذ المهمة وإكمال خطواتها هنا فقط. افتح تبويب «إعداد التقارير» لتعبئة التقرير وإرساله.</Text></View> : null}
            <Pressable style={styles.secondaryButton} onPress={() => void showTimeline(task)}><Text style={styles.secondaryText}>عرض السجل الزمني</Text></Pressable>
            {!!timeline[task.id]?.length && <View style={styles.timeline}>{timeline[task.id].map((entry) => <Text key={entry.id} style={styles.meta}>{formatDate(entry.created_at)} · {entry.status} · {entry.actor_name}{entry.note ? ` — ${entry.note}` : ''}</Text>)}</View>}
            </>}


            {!reportsOnly && <View style={styles.actions}><Text style={styles.cardSectionLabel}>الإجراء التالي</Text>
              {['pending', 'rejected'].includes(task.status) && (
                <Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => void mutate(task, () => updateTaskStatus(task.id, 'in_progress'), 'تم تسجيل بدء تنفيذ المهمة.')}>
                  <Text style={styles.primaryText}>بدء التنفيذ</Text>
                </Pressable>
              )}
              {!!task.report_forms.length || !!task.report_schema.length ? <Pressable style={styles.secondaryButton} onPress={() => router.replace({ pathname: '/tasks', params: { view: 'reports', mode: 'mine' } })}><Text style={styles.secondaryText}>فتح تبويب التقارير</Text></Pressable> : null}
              {task.status === 'in_progress' && !task.report_schema?.length && !task.report_forms.length && (
                <Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => void mutate(task, () => submitTaskReport(task.id, {}), 'أرسلت المهمة للمراجعة.')}>
                  <Text style={styles.primaryText}>إرسال للمراجعة</Text>
                </Pressable>
              )}
              {canReview && task.report_flow !== 'multi_form' && task.status === 'submitted' && (
                <>
                  <TextInput style={styles.input} value={reviewNote} onChangeText={setReviewNote} placeholder="ملاحظة المراجعة (والسبب عند الإرجاع)" accessibilityLabel="ملاحظة المراجعة" />
                  <Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => void mutate(task, () => reviewTask(task.id, 'approved', reviewNote || null), 'تم اعتماد المهمة.')}><Text style={styles.primaryText}>اعتماد</Text></Pressable>
                  <Pressable disabled={busyTask === task.id || !reviewNote.trim()} style={styles.secondaryButton} onPress={() => void mutate(task, () => reviewTask(task.id, 'rejected', reviewNote), 'أعيدت المهمة مع ملاحظات.')}><Text style={styles.secondaryText}>إرجاع مع سبب</Text></Pressable>
                </>
              )}
            </View>}
          </CompactExpandableCard>
        ))}
        {!loading && reportsOnly && filteredTasks.length === 0 && <View style={styles.emptyReportBox}><Text style={styles.empty}>لا توجد تقارير مرتبطة بالمهام حاليًا.</Text></View>}
        {!loading && !reportsOnly && !error && filteredTasks.length === 0 && <Text style={styles.empty}>{tasks.length ? 'لا توجد مهام تطابق البحث أو الفلتر.' : 'لا توجد مهام ظاهرة لهذا الحساب.'}</Text>}

        {!reportsOnly && <View style={styles.notifications}>
          <Text style={styles.sectionTitle}>التنبيهات</Text>
          {!notifications.length && <Text style={styles.muted}>لا توجد تنبيهات جديدة.</Text>}
          {notifications.slice(0, 5).map((item) => (
            <View style={styles.notification} key={item.id}>
              <Text style={styles.notificationTitle}>{item.title}</Text>
              <Text style={styles.body}>{item.body}</Text>
              <Text style={styles.meta}>{formatDate(item.created_at)}{item.read_at ? ' · مقروء' : ' · جديد'}</Text>
            </View>
          ))}
        </View>}
      </ScrollView>
    </AppShell>
  );
}

function TaskStructuredPreview({ task, formatDate }: { task: Task; formatDate: (value: string) => string }) {
  const reportNames = task.report_forms.map((form) => form.title).filter(Boolean);
  return <View style={styles.taskPreview}>
    <Text style={styles.taskPreviewTitle}>ملخص المهمة</Text>
    <View style={styles.previewFields}>
      <PreviewField label="اسم المهمة" value={task.title} />
      <PreviewField label="الحالة" value={statusLabels[task.status]} />
      <PreviewField label="الأولوية" value={priorityLabels[task.priority]} />
      <PreviewField label="حالة الوصول" value={deliveryLabels[task.delivery_status]} />
      <PreviewField label="المنصب" value={task.position_code ? positionLabels[task.position_code] : 'غير محدد'} />
      <PreviewField label="الفرع" value={task.branch_name || 'كل الفروع'} />
      <PreviewField label="بداية التنفيذ" value={formatDate(task.starts_at)} />
      <PreviewField label="الموعد النهائي" value={formatDate(task.due_at)} />
      <PreviewField label="عدد خطوات التنفيذ" value={`${task.execution_steps.length} خطوات`} />
      <PreviewField label="التقرير المرتبط" value={reportNames.length ? reportNames.join('، ') : task.report_schema.length ? `${task.report_schema.length} حقول تقرير` : 'لا يوجد تقرير مرتبط'} />
    </View>
    {!!task.description && <PreviewTextField label="وصف المهمة" value={task.description} />}
    {!!task.task_instructions && <PreviewTextField label="تعليمات التنفيذ" value={task.task_instructions} />}
    {task.proof_required && <PreviewTextField label="متطلبات الإثبات" value={task.proof_instructions || 'إرفاق دليل إنجاز مطلوب'} tone="warning" />}
    {!!task.execution_steps.length && <View style={styles.previewSteps}><Text style={styles.previewFieldLabel}>خطوات التنفيذ</Text>{task.execution_steps.map((step, index) => <View key={step.id} style={styles.previewStepRow}><Text style={styles.previewStepNumber}>{index + 1}</Text><View style={styles.previewStepCopy}><Text style={styles.previewStepTitle}>{step.title}</Text><Text style={styles.previewStepMeta}>{step.required ? 'إلزامية' : 'اختيارية'}{step.completed ? ' · مكتملة' : ''}{step.evidence_required ? ' · تحتاج إثباتاً' : ''}</Text></View></View>)}</View>}
  </View>;
}

function PreviewField({ label, value }: { label: string; value: string }) { return <View style={styles.previewField}><Text style={styles.previewFieldLabel}>{label}</Text><Text style={styles.previewFieldValue}>{value}</Text></View>; }
function PreviewTextField({ label, value, tone }: { label: string; value: string; tone?: 'warning' }) { return <View style={[styles.previewTextField, tone === 'warning' && styles.previewWarning]}><Text style={styles.previewFieldLabel}>{label}</Text><Text style={styles.previewTextValue}>{value}</Text></View>; }

const styles = StyleSheet.create({
  content: { padding: 12, paddingBottom: 32, gap: 12 },
  headerActions: { flexDirection: 'row-reverse', alignItems: 'center', marginBottom: 2 },
  signOutButton: { minHeight: 44, borderRadius: 10, borderWidth: 1, borderColor: '#b55248', backgroundColor: '#fff', paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center' },
  signOutText: { color: '#a8443d', fontSize: 12, fontWeight: '800' },
  pending: { color: '#8c4f13', backgroundColor: '#fff1dc', borderRadius: 9, padding: 10, textAlign: 'right' },
  modeTabs: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7, paddingVertical: 3 },
  modeTab: { flex: 1, minWidth: 92, minHeight: 42, borderRadius: 12, borderWidth: 1, borderColor: '#ccd9df', backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 9, paddingVertical: 8 },
  modeTabSelected: { backgroundColor: '#17324d', borderColor: '#17324d' },
  modeTabText: { color: '#39556a', fontSize: 12, fontWeight: '700', textAlign: 'center' },
  modeTabTextSelected: { color: '#fff' },
  workTabs: { flexDirection: 'row-reverse', gap: 8, paddingVertical: 2 },
  workTab: { flex: 1, minHeight: 45, borderRadius: 12, borderWidth: 1, borderColor: '#d6e0e4', backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' },
  workTabSelected: { backgroundColor: '#e5b336', borderColor: '#e5b336' },
  workTabText: { color: '#39556a', fontWeight: '800', fontSize: 13 },
  workTabTextSelected: { color: '#17324d', fontWeight: '900' },
  reportUploadHeader: { backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e2e9eb', padding: 14, gap: 5 },
  reportSeparationNotice: { backgroundColor: '#eef6f2', borderColor: '#cce4d6', borderWidth: 1, borderRadius: 12, padding: 12, gap: 4, marginTop: 8 },
  reportSeparationTitle: { color: '#245d43', fontSize: 14, fontWeight: '900', textAlign: 'right' },
  reportSeparationText: { color: '#47715d', fontSize: 12, lineHeight: 19, textAlign: 'right' },
  reportUploadTitle: { color: '#17324d', fontSize: 17, fontWeight: '900', textAlign: 'right' },
  reportUploadSubtitle: { color: '#718394', fontSize: 12, lineHeight: 20, textAlign: 'right' },
  reportStatusTabs: { flexDirection: 'row-reverse', gap: 7, paddingVertical: 2 },
  reportStatusTab: { flex: 1, minHeight: 40, borderRadius: 10, borderWidth: 1, borderColor: '#ccd9df', backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 5 },
  reportStatusTabSelected: { backgroundColor: '#17324d', borderColor: '#17324d' },
  reportStatusTabText: { color: '#39556a', fontSize: 11, fontWeight: '700' },
  reportStatusTabTextSelected: { color: '#fff', fontSize: 11, fontWeight: '900' },
  filters: { flexDirection: 'row-reverse', gap: 8, paddingVertical: 4 },
  filterChip: { borderRadius: 18, borderWidth: 1, borderColor: '#ccd9df', paddingHorizontal: 12, paddingVertical: 8 },
  filterChipSelected: { backgroundColor: '#17324d', borderColor: '#17324d' },
  filterChipText: { color: '#39556a', fontSize: 13 },
  filterChipTextSelected: { color: '#fff', fontSize: 13, fontWeight: '700' },
  activeFilter: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8, backgroundColor: '#fff', borderRadius: 10, borderWidth: 1, borderColor: '#d6e0e4', padding: 10 },
  clearFilterButton: { minHeight: 36, borderRadius: 8, backgroundColor: '#e9f0f4', paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center' },
  clearFilterText: { color: '#17324d', fontSize: 12, fontWeight: '800' },
  loading: { padding: 26, alignItems: 'center', gap: 12 },
  independentReportSection: { gap: 10 },
  emptyReportBox: { backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e2e9eb', padding: 14 },
  taskCard: { backgroundColor: '#fff', borderRadius: 16, padding: 16, borderWidth: 1, borderColor: '#e2e9eb', gap: 10 },
  taskHeading: { flexDirection: 'row-reverse', alignItems: 'flex-start', justifyContent: 'space-between', gap: 8 },
  taskTitle: { flex: 1, color: '#17324d', fontSize: 18, fontWeight: '800', textAlign: 'right', lineHeight: 27 },
  previewButton: { backgroundColor: '#eef5f7', borderWidth: 1, borderColor: '#c8dce2', borderRadius: 11, padding: 11, gap: 3, alignItems: 'flex-end' },
  previewButtonText: { color: '#17324d', fontWeight: '900', textAlign: 'right' },
  previewButtonHint: { color: '#718394', fontSize: 11, textAlign: 'right' },
  taskPreview: { backgroundColor: '#f8fafb', borderWidth: 1, borderColor: '#dce8eb', borderRadius: 12, padding: 11, gap: 9 },
  taskPreviewTitle: { color: '#17324d', fontSize: 16, fontWeight: '900', textAlign: 'right' },
  previewFields: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7 },
  previewField: { width: '48%', minHeight: 58, backgroundColor: '#fff', borderWidth: 1, borderColor: '#e2eaed', borderRadius: 9, padding: 8, gap: 4 },
  previewFieldLabel: { color: '#718394', fontSize: 11, fontWeight: '800', textAlign: 'right' },
  previewFieldValue: { color: '#17324d', fontSize: 13, fontWeight: '900', textAlign: 'right', lineHeight: 19 },
  previewTextField: { backgroundColor: '#fff', borderRadius: 9, borderWidth: 1, borderColor: '#e2eaed', padding: 9, gap: 4 },
  previewTextValue: { color: '#39556a', textAlign: 'right', lineHeight: 20 },
  previewWarning: { backgroundColor: '#fff7e8', borderColor: '#ecd49e' },
  previewSteps: { gap: 6 },
  previewStepRow: { flexDirection: 'row-reverse', alignItems: 'center', gap: 8, backgroundColor: '#fff', borderRadius: 8, padding: 8 },
  previewStepNumber: { width: 25, height: 25, borderRadius: 13, backgroundColor: '#e5b336', color: '#17324d', textAlign: 'center', textAlignVertical: 'center', fontWeight: '900', paddingTop: 3 },
  previewStepCopy: { flex: 1, gap: 2 },
  previewStepTitle: { color: '#29475a', fontWeight: '900', textAlign: 'right' },
  previewStepMeta: { color: '#718394', fontSize: 11, textAlign: 'right' },
  cardSectionLabel: { color: '#17324d', fontSize: 15, fontWeight: '900', textAlign: 'right', marginTop: 3 },
  badge: { overflow: 'hidden', borderRadius: 20, paddingHorizontal: 10, paddingVertical: 5, fontSize: 12, fontWeight: '700' },
  goodBadge: { color: '#23633c', backgroundColor: '#e5f4e9' },
  warnBadge: { color: '#8c4f13', backgroundColor: '#fff1dc' },
  neutralBadge: { color: '#39556a', backgroundColor: '#e9f0f4' },
  body: { color: '#4c6171', textAlign: 'right', lineHeight: 23 },
  meta: { color: '#718394', fontSize: 13, textAlign: 'right', lineHeight: 20 },
  deliveryStatus: { color: '#2d6d55', fontSize: 12, fontWeight: '800', textAlign: 'right', backgroundColor: '#eef8f1', borderRadius: 8, paddingHorizontal: 9, paddingVertical: 6 },
  proof: { color: '#8c4f13', backgroundColor: '#fff7e8', borderRadius: 9, padding: 10, textAlign: 'right', lineHeight: 21 },
  field: { gap: 5 },
  choices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 8 },
  choice: { borderRadius: 18, borderWidth: 1, borderColor: '#ccd9df', paddingHorizontal: 12, paddingVertical: 8 },
  choiceSelected: { backgroundColor: '#17324d', borderColor: '#17324d' },
  choiceText: { color: '#39556a' },
  choiceSelectedText: { color: '#fff', fontWeight: '700' },
  attachmentNotice: { color: '#8c4f13', backgroundColor: '#fff7e8', borderRadius: 9, padding: 10, textAlign: 'right', lineHeight: 21 },
  fieldLabel: { color: '#263f52', textAlign: 'right', fontWeight: '700' },
  input: { minHeight: 46, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, textAlign: 'right', color: '#17324d', backgroundColor: '#fbfcfc' },
  actions: { gap: 8, marginTop: 4 },
  primaryButton: { minHeight: 46, borderRadius: 10, padding: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: '#17324d' },
  primaryText: { color: '#fff', fontWeight: '800' },
  secondaryButton: { minHeight: 44, borderRadius: 10, padding: 11, alignItems: 'center', justifyContent: 'center', backgroundColor: '#e9f0f4' },
  secondaryText: { color: '#17324d', fontWeight: '800' },
  errorBox: { backgroundColor: '#fff0ef', borderRadius: 10, padding: 10, gap: 8 }, error: { color: '#a8443d', padding: 2, textAlign: 'right', lineHeight: 22 }, retryButton: { minHeight: 38, borderRadius: 8, backgroundColor: '#fff', borderWidth: 1, borderColor: '#b55248', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12 }, retryText: { color: '#a8443d', fontWeight: '800' },
  notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 10, padding: 12, textAlign: 'right', lineHeight: 22 },
  newTaskNotice: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 10, backgroundColor: '#fff4d7', borderWidth: 2, borderColor: '#dba62a', borderRadius: 15, padding: 13 },
  newTaskNoticeCopy: { flex: 1, gap: 2 },
  newTaskNoticeTitle: { color: '#17324d', fontSize: 17, fontWeight: '900', textAlign: 'right' },
  newTaskNoticeText: { color: '#263f52', fontWeight: '800', textAlign: 'right' },
  newTaskNoticeHint: { color: '#718394', fontSize: 12, textAlign: 'right' },
  newTaskNoticeActions: { gap: 6, minWidth: 78 },
  newTaskOpenButton: { backgroundColor: '#17324d', borderRadius: 9, paddingHorizontal: 10, paddingVertical: 9, alignItems: 'center' },
  newTaskOpenText: { color: '#fff', fontSize: 12, fontWeight: '800' },
  newTaskDismissButton: { paddingVertical: 5, alignItems: 'center' },
  newTaskDismissText: { color: '#8c4f13', fontSize: 12, fontWeight: '700' },
  employeeIntro: { backgroundColor: '#17324d', borderRadius: 16, padding: 16, gap: 6 },
  employeeIntroTitle: { color: '#fff', fontSize: 18, fontWeight: '900', textAlign: 'right' },
  employeeIntroText: { color: '#dceaf0', lineHeight: 22, textAlign: 'right' },
  summaryRow: { flexDirection: 'row-reverse', gap: 8 },
  summaryCard: { flex: 1, minHeight: 74, backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e2e9eb', padding: 10, alignItems: 'center', justifyContent: 'center', gap: 2 },
  summaryValue: { color: '#17324d', fontSize: 22, fontWeight: '900' },
  summaryLabel: { color: '#718394', fontSize: 12, fontWeight: '700', textAlign: 'center' },
  empty: { color: '#718394', textAlign: 'center', paddingVertical: 22 },
  muted: { color: '#718394', textAlign: 'center' },
  timeline: { borderTopWidth: 1, borderTopColor: '#edf1f3', paddingTop: 8, gap: 4 },
  stepCard: { backgroundColor: '#f8fafb', borderWidth: 1, borderColor: '#e2eaed', borderRadius: 11, padding: 11, gap: 8 },
  reportCard: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#e2eaed', borderRadius: 12, padding: 12, gap: 8 },
  reportWorkspace: { gap: 12, marginTop: 2 },
  directReportForm: { gap: 10, borderTopWidth: 1, borderTopColor: '#edf1f3', paddingTop: 12 },
  reportFormTitle: { flex: 1, color: '#17324d', fontSize: 17, fontWeight: '900', textAlign: 'right', lineHeight: 25 },
  lockedReportText: { color: '#52687a', backgroundColor: '#eef5f7', borderRadius: 10, padding: 11, textAlign: 'right', lineHeight: 21 },
  reportQuickButton: { backgroundColor: '#fff4d7', borderWidth: 2, borderColor: '#dba62a', borderRadius: 14, padding: 14, gap: 4, alignItems: 'flex-end' },
  reportQuickTitle: { color: '#17324d', fontSize: 16, fontWeight: '900', textAlign: 'right' },
  reportQuickText: { color: '#52687a', fontSize: 13, textAlign: 'right', lineHeight: 20 },
  reportQuickAction: { color: '#9a6814', fontSize: 14, fontWeight: '900', textAlign: 'right', marginTop: 4 },
  notifications: { marginTop: 10, padding: 16, backgroundColor: '#fff', borderWidth: 1, borderColor: '#e2e9eb', borderRadius: 16, gap: 10 },
  sectionTitle: { color: '#17324d', fontSize: 18, fontWeight: '800', textAlign: 'right' },
  notification: { borderTopWidth: 1, borderTopColor: '#edf1f3', paddingTop: 10, gap: 4 },
  notificationTitle: { color: '#17324d', fontWeight: '700', textAlign: 'right' },
  tableEditor: { gap: 8, borderWidth: 1, borderColor: '#dce6e9', borderRadius: 10, padding: 8 },
  tableRow: { gap: 6, borderBottomWidth: 1, borderBottomColor: '#edf1f3', paddingBottom: 8 },
  tableCell: { minHeight: 42, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 8, paddingHorizontal: 10, textAlign: 'right', backgroundColor: '#fbfcfc' },
  calculated: { backgroundColor: '#eef5f7', borderRadius: 10, padding: 12, gap: 4 },
  calculatedValue: { color: '#17324d', fontSize: 20, fontWeight: '900', textAlign: 'right' },
});
