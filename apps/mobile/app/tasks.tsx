import { useCallback, useEffect, useState } from 'react';
import {
  AppState,
  ActivityIndicator,
  Pressable,
  RefreshControl,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { supabase } from '../lib/supabase';
import {
  friendlyDataError,
  getMyEmployeeProfile,
  listMyNotifications,
  listMyTasks,
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
import { pickTaskAttachment, uploadTaskAttachment, type PickedAttachment } from '../lib/taskAttachments';
import { evaluateReportField, normalizeTableColumns, reportDefaultDraft, validateReportFieldValue, type ReportField, type ReportTableColumn } from '../lib/reportSchema';
import ReportFieldInput from '../components/ReportFieldInput';
import ReportReadOnly from '../components/ReportReadOnly';

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
  proof_required: boolean;
  proof_instructions: string | null;
  report_schema: ReportField[];
  task_instructions: string | null;
  report_flow: 'legacy' | 'multi_form';
  execution_steps: Array<{ id: string; title: string; instructions: string | null; sort_order: number; required: boolean; evidence_required: boolean; evidence_instructions: string | null; completed: boolean }>;
  report_forms: MobileTaskReportForm[];
};
type Notification = { id: string; title: string; body: string; severity: string; read_at: string | null; created_at: string };

const statusLabels: Record<Task['status'], string> = {
  pending: 'معلقة', in_progress: 'قيد التنفيذ', submitted: 'بانتظار المراجعة',
  approved: 'معتمدة', rejected: 'تحتاج استكمالًا', cancelled: 'ملغاة', late: 'متأخرة',
};
const priorityLabels: Record<Task['priority'], string> = { normal: 'عادية', important: 'مهمة', urgent: 'عاجلة', critical: 'حرجة' };
const positionLabels: Record<NonNullable<Task['position_code']>, string> = {
  owner: 'صاحب المؤسسة', admin_followup: 'المدير التنفيذي', accountant: 'المحاسب',
  warehouse_keeper: 'أمين المخازن', warehouse_worker: 'عمال التحميل',
};

export default function TasksScreen() {
  const router = useRouter();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [canReview, setCanReview] = useState(false);
  const [currentUserId, setCurrentUserId] = useState('');
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
  const [positionFilter, setPositionFilter] = useState<Task['position_code'] | 'all'>('all');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [attachments, setAttachments] = useState<Record<string, Record<string, Array<PickedAttachment & { path?: string }>>>>({});
  const [stepAttachments, setStepAttachments] = useState<Record<string, Record<string, { id: string; name: string }>>>({});
  const [timeline, setTimeline] = useState<Record<string, Awaited<ReturnType<typeof listTaskTimeline>>>>({});

  const load = useCallback(async () => {
    setError('');
    try {
      await syncOfflineQueue();
      const identity = await getMyEmployeeProfile();
      if (!identity) throw new Error('not_authenticated');
      if (!identity.employee) throw new Error('employee_not_active');
      setCurrentUserId(identity.userId);
      const permissions = new Set(identity.employee.permissions);
      if (!permissions.has('tasks.execute') && !permissions.has('tasks.manage')) throw new Error('permission_denied');
      const [taskRows, notificationRows] = await Promise.all([listMyTasks(), listMyNotifications()]);
      setCanReview(identity.employee.permissions.includes('tasks.review'));
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
      setNotifications(notificationRows);
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر تحميل البيانات مباشرة من Supabase. تحقق من الاتصال والصلاحيات.'));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') void load();
    });
    return () => subscription.remove();
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
      await load();
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
        if (field.type === 'calculated') continue;
        const raw = drafts[task.id]?.[field.key]?.trim() ?? '';
        if (['attachment', 'image', 'file'].includes(field.type)) {
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
        if (field.type === 'calculated') continue;
        const raw = drafts[key]?.[field.key]?.trim() ?? '';
        if (['attachment', 'image', 'file'].includes(field.type)) {
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
    const modeMatches = screenMode === 'mine'
      ? task.assignee_employee_id === currentUserId
      : screenMode === 'review'
        ? canReview && (task.status === 'submitted' || hasPendingFormReview)
        : canReview;
    return modeMatches &&
      (statusFilter === 'all' || task.status === statusFilter) &&
      (positionFilter === 'all' || task.position_code === positionFilter) &&
      (!search.trim() || `${task.title} ${task.description ?? ''}`.toLocaleLowerCase('ar').includes(search.trim().toLocaleLowerCase('ar')));
  });

  return (
    <SafeAreaView style={styles.safe}>
      <Stack.Screen options={{ title: 'المهام', headerShown: false }} />
      <ScrollView
        contentContainerStyle={styles.content}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); void load(); }} />}
      >
        <View style={styles.header}>
          <View style={styles.headerText}>
            <Text style={styles.eyebrow}>برنامج الشاعري</Text>
            <Text style={styles.title}>المهام والمتابعة</Text>
          </View>
          <View style={styles.headerActions}>
            <Pressable accessibilityRole="button" style={styles.backButton} onPress={() => router.back()}>
              <Text style={styles.backText}>رجوع</Text>
            </Pressable>
            <Pressable accessibilityRole="button" accessibilityLabel="تسجيل الخروج وتبديل الحساب" style={styles.signOutButton} onPress={() => void signOut()}>
              <Text style={styles.signOutText}>تبديل الحساب</Text>
            </Pressable>
          </View>
        </View>
        {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
        {!!notice && <Text accessibilityLiveRegion="polite" style={styles.notice}>{notice}</Text>}
        {loading && <View style={styles.loading}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.muted}>جارٍ تحميل المهام…</Text></View>}
        {!loading && canReview && <View style={styles.modeTabs}>
          {([
            ['mine', 'مهامي'],
            ['review', 'مراجعة التقارير'],
            ['all', 'متابعة جميع المهام'],
          ] as const).map(([mode, label]) => <Pressable key={mode} accessibilityRole="button" accessibilityState={{ selected: screenMode === mode }} style={[styles.modeTab, screenMode === mode && styles.modeTabSelected]} onPress={() => { setScreenMode(mode); setStatusFilter('all'); setPositionFilter('all'); }}><Text style={[styles.modeTabText, screenMode === mode && styles.modeTabTextSelected]}>{label}</Text></Pressable>)}
        </View>}

        {!loading && tasks.length > 0 && <>
          <TextInput style={styles.input} value={search} onChangeText={setSearch} placeholder="ابحث عن مهمة…" accessibilityLabel="البحث في المهام" />
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filters}>
            {([['all', 'كل المناصب'], ['owner', 'صاحب المؤسسة'], ['admin_followup', 'المدير التنفيذي'], ['accountant', 'المحاسب'], ['warehouse_keeper', 'أمين المخازن'], ['warehouse_worker', 'عمال التحميل']] as const).map(([code, label]) => {
              const selected = positionFilter === code;
              return <Pressable key={code} accessibilityRole="button" accessibilityState={{ selected }} style={[styles.filterChip, selected && styles.filterChipSelected]} onPress={() => setPositionFilter(code)}>
                <Text style={selected ? styles.filterChipTextSelected : styles.filterChipText}>{label}</Text>
              </Pressable>;
            })}
          </ScrollView>
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
          <View style={styles.taskCard} key={task.id}>
            <View style={styles.taskHeading}>
              <Text style={styles.taskTitle}>{task.title}</Text>
              <Text style={[styles.badge, task.status === 'approved' ? styles.goodBadge : task.status === 'rejected' ? styles.warnBadge : styles.neutralBadge]}>{statusLabels[task.status]}</Text>
            </View>
            {!!task.description && <Text style={styles.body}>{task.description}</Text>}
            <Text style={styles.meta}>المنصب: {task.position_code ? positionLabels[task.position_code] : 'بحاجة إلى تصنيف'}{task.branch_name ? ` · الفرع: ${task.branch_name}${task.branch_level ? ` (المستوى ${task.branch_level})` : ''}` : task.branch_id ? ' · فرع محدد' : ''}</Text>
            <Text style={styles.meta}>الأولوية: {priorityLabels[task.priority]} · الموعد: {formatDate(task.due_at)}</Text>
            {task.proof_required && <Text style={styles.proof}>{task.proof_instructions || 'يتطلب إرفاق دليل إنجاز.'}</Text>}
            {!!task.task_instructions && <View style={styles.timeline}><Text style={styles.fieldLabel}>تعليمات التنفيذ</Text><Text style={styles.body}>{task.task_instructions}</Text></View>}
            {!!task.execution_steps.length && <View style={styles.timeline}><Text style={styles.fieldLabel}>خطوات التنفيذ</Text>{task.execution_steps.map((step,index)=><View key={step.id} style={styles.stepCard}>
              <Text style={styles.fieldLabel}>{index+1}. {step.title}{step.required?' · إلزامية':' · اختيارية'}{step.completed?' · مكتملة':''}</Text>
              {!!step.instructions && <Text style={styles.body}>{step.instructions}</Text>}
              {step.evidence_required && <Text style={styles.proof}>{step.evidence_instructions || 'أرفق إثباتًا قبل إكمال هذه الخطوة.'}</Text>}
              {!step.completed && step.evidence_required && <><Pressable style={styles.secondaryButton} onPress={()=>void chooseStepEvidence(task,step.id)}><Text style={styles.secondaryText}>{stepAttachments[task.id]?.[step.id]?.name ?? 'اختيار إثبات للخطوة'}</Text></Pressable>{!!stepAttachments[task.id]?.[step.id] && <Text style={styles.meta}>المرفق جاهز: {stepAttachments[task.id][step.id].name}</Text>}</>}
              {!step.completed && <Pressable disabled={busyTask===task.id || (step.evidence_required&&!stepAttachments[task.id]?.[step.id])} style={[styles.primaryButton,{opacity:step.evidence_required&&!stepAttachments[task.id]?.[step.id]?0.5:1}]} onPress={()=>void mutate(task,()=>completeTaskExecutionStep(step.id,stepAttachments[task.id]?.[step.id]?[stepAttachments[task.id][step.id].id]:[]),'تم تسجيل إكمال الخطوة.') }><Text style={styles.primaryText}>إكمال الخطوة</Text></Pressable>}
            </View>)}</View>}
            <Pressable style={styles.secondaryButton} onPress={() => void showTimeline(task)}><Text style={styles.secondaryText}>عرض السجل الزمني</Text></Pressable>
            {!!timeline[task.id]?.length && <View style={styles.timeline}>{timeline[task.id].map((entry) => <Text key={entry.id} style={styles.meta}>{formatDate(entry.created_at)} · {entry.status} · {entry.actor_name}{entry.note ? ` — ${entry.note}` : ''}</Text>)}</View>}

            {reportTask === task.id && (task.report_schema ?? []).map((field) => <ReportFieldInput
              key={field.key} field={field} raw={drafts[task.id]?.[field.key] ?? ''}
              attachments={attachments[task.id]?.[field.key] ?? []} calculated={calculatedValue(task.id, field)} calculationError={calculationError(task.id, field)}
              rows={field.type === 'table' ? tableRows(task.id, field) : []}
              onDraftChange={(value) => setDrafts((current) => ({ ...current, [task.id]: { ...current[task.id], [field.key]: value } }))}
              onTableChange={(rows) => updateTable(task.id, field, rows)}
              onChooseAttachment={() => void chooseAttachment(task, field.key)}
            />)}

            {!!task.report_forms.length && <View style={styles.timeline}><Text style={styles.fieldLabel}>نماذج التقارير المرتبطة</Text>{task.report_forms.map((form)=>{
              const key=formDraftKey(task,form); const opened=activeReportForm?.taskId===task.id&&activeReportForm.snapshotId===form.snapshot_id;
              const statusLabel=form.status==='submitted'?'بانتظار مراجعة هذا النموذج':form.status==='approved'?'تم اعتماد هذا النموذج':form.status==='returned'?'أُعيد هذا النموذج للتعديل':form.required?'مطلوب الإرسال':'اختياري';
              const canEdit=['in_progress','rejected','submitted'].includes(task.status)&&form.status!=='submitted'&&form.status!=='approved';
              return <View key={form.snapshot_id} style={styles.reportCard}>
                <View style={styles.taskHeading}><Text style={styles.taskTitle}>{form.title}</Text><Text style={[styles.badge,form.status==='approved'?styles.goodBadge:form.status==='returned'?styles.warnBadge:styles.neutralBadge]}>{statusLabel}</Text></View>
                <Text style={styles.meta}>{form.required?'إلزامي لإكمال المهمة':'اختياري'} · {form.schema.length} حقول</Text>
                {!!form.review_note&&form.status==='returned'&&<Text style={styles.proof}>ملاحظة المراجع: {form.review_note}</Text>}
                {form.status==='submitted'&&<ReportReadOnly fields={form.schema} values={form.values}/>}
                {canReview&&form.status==='submitted'&&form.report_id&&<><TextInput style={styles.input} value={reviewNote} onChangeText={setReviewNote} placeholder="ملاحظة المراجعة" accessibilityLabel={`ملاحظة مراجعة ${form.title}`}/><Pressable disabled={busyTask===task.id} style={styles.primaryButton} onPress={()=>void mutate(task,()=>reviewTaskFormReport(form.report_id!,'approved',reviewNote||null),`تم اعتماد «${form.title}» فقط.`)}><Text style={styles.primaryText}>اعتماد هذا التقرير</Text></Pressable><Pressable disabled={busyTask===task.id||!reviewNote.trim()} style={styles.secondaryButton} onPress={()=>void mutate(task,()=>reviewTaskFormReport(form.report_id!,'returned',reviewNote),`أعيد «${form.title}» للتعديل.`)}><Text style={styles.secondaryText}>إرجاع هذا التقرير مع سبب</Text></Pressable></>}
                {canEdit&&!opened&&<Pressable style={styles.secondaryButton} onPress={()=>{setError('');setActiveReportForm({taskId:task.id,snapshotId:form.snapshot_id});}}><Text style={styles.secondaryText}>{form.status==='returned'?'تعديل وإعادة إرسال':'فتح هذا التقرير'}</Text></Pressable>}
                {canEdit&&opened&&<>{form.schema.map((field)=><ReportFieldInput key={field.key} field={field} raw={drafts[key]?.[field.key]??''} attachments={attachments[key]?.[field.key]??[]} calculated={evaluateReportField(field,form.schema,valuesForReportForm(task,form)).value} calculationError={evaluateReportField(field,form.schema,valuesForReportForm(task,form)).error} rows={field.type==='table'?tableRows(key,field):[]} onDraftChange={(value)=>setDrafts((current)=>({...current,[key]:{...current[key],[field.key]:value}}))} onTableChange={(rows)=>updateTable(key,field,rows)} onChooseAttachment={()=>void chooseFormAttachment(task,form,field.key)}/>)}<Pressable style={styles.secondaryButton} onPress={()=>void saveSeparateDraft(task,form)}><Text style={styles.secondaryText}>حفظ المسودة</Text></Pressable><Pressable disabled={busyTask===task.id} style={styles.primaryButton} onPress={()=>submitSeparateReport(task,form)}><Text style={styles.primaryText}>{busyTask===task.id?'جارٍ الإرسال…':'إرسال هذا التقرير فقط'}</Text></Pressable><Pressable style={styles.secondaryButton} onPress={()=>setActiveReportForm(null)}><Text style={styles.secondaryText}>إغلاق النموذج</Text></Pressable></>}
              </View>;
            })}</View>}

            {task.report_flow !== 'multi_form' && !!task.report_schema?.length && ['in_progress', 'rejected'].includes(task.status) && reportTask !== task.id && (
              <Pressable accessibilityRole="button" style={styles.secondaryButton} onPress={() => { setError(''); setReportTask(task.id); }}>
                <Text style={styles.secondaryText}>كتابة التقرير</Text>
              </Pressable>
            )}

            <View style={styles.actions}>
              {['pending', 'rejected'].includes(task.status) && (
                <Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => void mutate(task, () => updateTaskStatus(task.id, 'in_progress'), 'تم تسجيل بدء تنفيذ المهمة.')}>
                  <Text style={styles.primaryText}>بدء التنفيذ</Text>
                </Pressable>
              )}
              {task.status === 'in_progress' && !task.report_schema?.length && !task.report_forms.length && (
                <Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => void mutate(task, () => submitTaskReport(task.id, {}), 'أرسلت المهمة للمراجعة.')}>
                  <Text style={styles.primaryText}>إرسال للمراجعة</Text>
                </Pressable>
              )}
              {reportTask === task.id && (
                <>
                  <Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => submitReport(task)}>
                    <Text style={styles.primaryText}>{busyTask === task.id ? 'جارٍ الإرسال…' : 'إرسال التقرير'}</Text>
                  </Pressable>
                  <Pressable style={styles.secondaryButton} onPress={() => setReportTask('')}><Text style={styles.secondaryText}>إلغاء</Text></Pressable>
                </>
              )}
              {canReview && task.report_flow !== 'multi_form' && task.status === 'submitted' && (
                <>
                  <TextInput style={styles.input} value={reviewNote} onChangeText={setReviewNote} placeholder="ملاحظة المراجعة (والسبب عند الإرجاع)" accessibilityLabel="ملاحظة المراجعة" />
                  <Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => void mutate(task, () => reviewTask(task.id, 'approved', reviewNote || null), 'تم اعتماد المهمة.')}><Text style={styles.primaryText}>اعتماد</Text></Pressable>
                  <Pressable disabled={busyTask === task.id || !reviewNote.trim()} style={styles.secondaryButton} onPress={() => void mutate(task, () => reviewTask(task.id, 'rejected', reviewNote), 'أعيدت المهمة مع ملاحظات.')}><Text style={styles.secondaryText}>إرجاع مع سبب</Text></Pressable>
                </>
              )}
            </View>
          </View>
        ))}
        {!loading && !error && filteredTasks.length === 0 && <Text style={styles.empty}>{tasks.length ? 'لا توجد مهام تطابق البحث أو الفلتر.' : 'لا توجد مهام ظاهرة لهذا الحساب.'}</Text>}

        <View style={styles.notifications}>
          <Text style={styles.sectionTitle}>التنبيهات</Text>
          {!notifications.length && <Text style={styles.muted}>لا توجد تنبيهات جديدة.</Text>}
          {notifications.slice(0, 5).map((item) => (
            <View style={styles.notification} key={item.id}>
              <Text style={styles.notificationTitle}>{item.title}</Text>
              <Text style={styles.body}>{item.body}</Text>
              <Text style={styles.meta}>{formatDate(item.created_at)}{item.read_at ? ' · مقروء' : ' · جديد'}</Text>
            </View>
          ))}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f4f7f8' },
  content: { padding: 16, paddingBottom: 36, gap: 12 },
  header: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 },
  headerText: { flex: 1 },
  headerActions: { flexDirection: 'row-reverse', alignItems: 'center', gap: 7 },
  signOutButton: { minHeight: 44, borderRadius: 10, borderWidth: 1, borderColor: '#b55248', backgroundColor: '#fff', paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center' },
  signOutText: { color: '#a8443d', fontSize: 12, fontWeight: '800' },
  eyebrow: { color: '#718394', textAlign: 'right', fontWeight: '700', marginBottom: 4 },
  title: { color: '#17324d', fontSize: 25, fontWeight: '800', textAlign: 'right' },
  backButton: { minHeight: 44, minWidth: 58, alignItems: 'center', justifyContent: 'center', borderRadius: 10, backgroundColor: '#e5edf0' },
  backText: { color: '#17324d', fontWeight: '700' },
  pending: { color: '#8c4f13', backgroundColor: '#fff1dc', borderRadius: 9, padding: 10, textAlign: 'right' },
  modeTabs: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7, paddingVertical: 3 },
  modeTab: { flex: 1, minWidth: 92, minHeight: 42, borderRadius: 12, borderWidth: 1, borderColor: '#ccd9df', backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 9, paddingVertical: 8 },
  modeTabSelected: { backgroundColor: '#17324d', borderColor: '#17324d' },
  modeTabText: { color: '#39556a', fontSize: 12, fontWeight: '700', textAlign: 'center' },
  modeTabTextSelected: { color: '#fff' },
  filters: { flexDirection: 'row-reverse', gap: 8, paddingVertical: 4 },
  filterChip: { borderRadius: 18, borderWidth: 1, borderColor: '#ccd9df', paddingHorizontal: 12, paddingVertical: 8 },
  filterChipSelected: { backgroundColor: '#17324d', borderColor: '#17324d' },
  filterChipText: { color: '#39556a', fontSize: 13 },
  filterChipTextSelected: { color: '#fff', fontSize: 13, fontWeight: '700' },
  loading: { padding: 26, alignItems: 'center', gap: 12 },
  taskCard: { backgroundColor: '#fff', borderRadius: 16, padding: 16, borderWidth: 1, borderColor: '#e2e9eb', gap: 10 },
  taskHeading: { flexDirection: 'row-reverse', alignItems: 'flex-start', justifyContent: 'space-between', gap: 8 },
  taskTitle: { flex: 1, color: '#17324d', fontSize: 18, fontWeight: '800', textAlign: 'right', lineHeight: 27 },
  badge: { overflow: 'hidden', borderRadius: 20, paddingHorizontal: 10, paddingVertical: 5, fontSize: 12, fontWeight: '700' },
  goodBadge: { color: '#23633c', backgroundColor: '#e5f4e9' },
  warnBadge: { color: '#8c4f13', backgroundColor: '#fff1dc' },
  neutralBadge: { color: '#39556a', backgroundColor: '#e9f0f4' },
  body: { color: '#4c6171', textAlign: 'right', lineHeight: 23 },
  meta: { color: '#718394', fontSize: 13, textAlign: 'right', lineHeight: 20 },
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
  error: { color: '#a8443d', backgroundColor: '#fff0ef', borderRadius: 10, padding: 12, textAlign: 'right', lineHeight: 22 },
  notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 10, padding: 12, textAlign: 'right', lineHeight: 22 },
  empty: { color: '#718394', textAlign: 'center', paddingVertical: 22 },
  muted: { color: '#718394', textAlign: 'center' },
  timeline: { borderTopWidth: 1, borderTopColor: '#edf1f3', paddingTop: 8, gap: 4 },
  stepCard: { backgroundColor: '#f8fafb', borderWidth: 1, borderColor: '#e2eaed', borderRadius: 11, padding: 11, gap: 8 },
  reportCard: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#e2eaed', borderRadius: 12, padding: 12, gap: 8 },
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
