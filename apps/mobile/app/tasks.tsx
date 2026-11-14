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
import {
  friendlyDataError,
  getMyEmployeeProfile,
  listMyNotifications,
  listMyTasks,
  reviewTask,
  submitTaskReport,
  updateTaskStatus,
} from '../lib/mobileData';

type ReportField = { key: string; label: string; type: 'text' | 'number' | 'progress' | 'status' | 'notes' | 'textarea' | 'date' | 'select' | 'multiselect' | 'checkbox' | 'attachment'; options?: string[]; required?: boolean };
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
  priority: 'low' | 'normal' | 'high' | 'urgent';
  status: 'pending' | 'in_progress' | 'submitted' | 'approved' | 'rejected' | 'cancelled';
  proof_required: boolean;
  proof_instructions: string | null;
  report_schema: ReportField[];
};
type Notification = { id: string; title: string; body: string; severity: string; read_at: string | null; created_at: string };

const statusLabels: Record<Task['status'], string> = {
  pending: 'معلقة', in_progress: 'قيد التنفيذ', submitted: 'بانتظار المراجعة',
  approved: 'معتمدة', rejected: 'تحتاج استكمالًا', cancelled: 'ملغاة',
};
const priorityLabels: Record<Task['priority'], string> = { low: 'منخفضة', normal: 'عادية', high: 'عالية', urgent: 'عاجلة' };
const positionLabels: Record<NonNullable<Task['position_code']>, string> = {
  owner: 'صاحب المؤسسة', admin_followup: 'المدير التنفيذي', accountant: 'المحاسب',
  warehouse_keeper: 'أمين المخازن', warehouse_worker: 'عمال التحميل',
};

export default function TasksScreen() {
  const router = useRouter();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [canReview, setCanReview] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [busyTask, setBusyTask] = useState('');
  const [reportTask, setReportTask] = useState('');
  const [drafts, setDrafts] = useState<Record<string, Record<string, string>>>({});
  const [reviewNote, setReviewNote] = useState('');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<Task['status'] | 'all'>('all');
  const [positionFilter, setPositionFilter] = useState<Task['position_code'] | 'all'>('all');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const load = useCallback(async () => {
    setError('');
    try {
      const identity = await getMyEmployeeProfile();
      if (!identity) throw new Error('not_authenticated');
      if (!identity.employee) throw new Error('employee_not_active');
      if (!identity.employee.permissions.includes('tasks.read')) throw new Error('permission_denied');
      const [taskRows, notificationRows] = await Promise.all([listMyTasks(), listMyNotifications()]);
      setCanReview(identity.employee.permissions.includes('tasks.review'));
      setTasks(taskRows);
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
      setReviewNote('');
      await load();
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر تنفيذ الإجراء عبر Supabase. تحقق من الاتصال والصلاحيات.'));
    } finally {
      setBusyTask('');
    }
  }

  function submitReport(task: Task) {
    const values: Record<string, unknown> = {};
    for (const field of task.report_schema ?? []) {
      const raw = drafts[task.id]?.[field.key]?.trim() ?? '';
      if (field.type === 'attachment') {
        if (field.required) {
          setError(`الحقل «${field.label}» يتطلب مرفقًا. رفع الملفات غير متاح في هذه النسخة؛ لا يمكن إرسال التقرير قبل دعم المرفقات.`);
          return;
        }
        continue;
      }
      if (field.required && !raw) {
        setError(`أكمل الحقل المطلوب: ${field.label}`);
        return;
      }
      if (field.type === 'multiselect' && raw) {
        const selected = JSON.parse(raw) as string[];
        if (field.required && !selected.length) { setError(`اختر خيارًا واحدًا على الأقل: ${field.label}`); return; }
        values[field.key] = selected;
      } else if (raw) {
        values[field.key] = ['number', 'progress'].includes(field.type)
          ? Number(raw)
          : field.type === 'checkbox' ? raw === 'true' : raw;
      }
    }
    void mutate(task, () => submitTaskReport(task.id, values), 'تم إرسال التقرير للمراجعة.');
  }

  const formatDate = (value: string) => {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? 'غير محدد' : new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium', timeStyle: 'short' }).format(date);
  };
  const filteredTasks = tasks.filter((task) =>
    (statusFilter === 'all' || task.status === statusFilter) &&
    (positionFilter === 'all' || task.position_code === positionFilter) &&
    (!search.trim() || `${task.title} ${task.description ?? ''}`.toLocaleLowerCase('ar').includes(search.trim().toLocaleLowerCase('ar'))),
  );

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
          <Pressable accessibilityRole="button" style={styles.backButton} onPress={() => router.back()}>
            <Text style={styles.backText}>رجوع</Text>
          </Pressable>
        </View>
        {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
        {!!notice && <Text accessibilityLiveRegion="polite" style={styles.notice}>{notice}</Text>}
        {loading && <View style={styles.loading}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.muted}>جارٍ تحميل المهام…</Text></View>}

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
            {(['all', 'pending', 'in_progress', 'submitted', 'rejected', 'approved'] as const).map((status) => {
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

            {reportTask === task.id && (task.report_schema ?? []).map((field) => (
              <View key={field.key} style={styles.field}>
                <Text style={styles.fieldLabel}>{field.label}{field.required ? ' *' : ''}</Text>
                {field.type === 'attachment' ? (
                  <Text style={styles.attachmentNotice}>هذا الحقل يحتاج رفع ملفًا. رفع المرفقات من الهاتف غير متاح حاليًا.</Text>
                ) : field.type === 'checkbox' ? (
                  <Pressable
                    accessibilityRole="checkbox"
                    accessibilityState={{ checked: drafts[task.id]?.[field.key] === 'true' }}
                    style={styles.secondaryButton}
                    onPress={() => setDrafts((current) => ({ ...current, [task.id]: { ...current[task.id], [field.key]: current[task.id]?.[field.key] === 'true' ? 'false' : 'true' } }))}
                  >
                    <Text style={styles.secondaryText}>{drafts[task.id]?.[field.key] === 'true' ? 'نعم ✓' : 'لا — اضغط للتغيير'}</Text>
                  </Pressable>
                ) : ['select', 'multiselect'].includes(field.type) && field.options?.length ? (
                  <View style={styles.choices}>
                    {field.options.map((option) => {
                      const raw = drafts[task.id]?.[field.key] ?? (field.type === 'multiselect' ? '[]' : '');
                      const selected = field.type === 'multiselect' ? (JSON.parse(raw || '[]') as string[]).includes(option) : raw === option;
                      return (
                        <Pressable key={option} style={[styles.choice, selected && styles.choiceSelected]} onPress={() => {
                          const next = field.type === 'multiselect'
                            ? JSON.stringify(selected ? (JSON.parse(raw || '[]') as string[]).filter((value) => value !== option) : [...(JSON.parse(raw || '[]') as string[]), option])
                            : option;
                          setDrafts((current) => ({ ...current, [task.id]: { ...current[task.id], [field.key]: next } }));
                        }}>
                          <Text style={selected ? styles.choiceSelectedText : styles.choiceText}>{option}</Text>
                        </Pressable>
                      );
                    })}
                  </View>
                ) : (
                  <TextInput
                    accessibilityLabel={field.label}
                    style={styles.input}
                    value={drafts[task.id]?.[field.key] ?? ''}
                    onChangeText={(value) => setDrafts((current) => ({ ...current, [task.id]: { ...current[task.id], [field.key]: value } }))}
                    keyboardType={['number', 'progress'].includes(field.type) ? 'numeric' : 'default'}
                    multiline={['notes', 'textarea'].includes(field.type)}
                    placeholder={field.type === 'progress' ? 'أدخل نسبة الإنجاز' : field.type === 'date' ? 'YYYY-MM-DD' : field.required ? 'مطلوب' : 'اختياري'}
                  />
                )}
              </View>
            ))}

            {!!task.report_schema?.length && ['in_progress', 'rejected'].includes(task.status) && reportTask !== task.id && (
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
              {task.status === 'in_progress' && !task.report_schema?.length && (
                <Pressable disabled={busyTask === task.id} style={styles.primaryButton} onPress={() => void mutate(task, () => updateTaskStatus(task.id, 'submitted'), 'أرسلت المهمة للمراجعة.')}>
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
              {canReview && task.status === 'submitted' && (
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
  eyebrow: { color: '#718394', textAlign: 'right', fontWeight: '700', marginBottom: 4 },
  title: { color: '#17324d', fontSize: 25, fontWeight: '800', textAlign: 'right' },
  backButton: { minHeight: 44, minWidth: 58, alignItems: 'center', justifyContent: 'center', borderRadius: 10, backgroundColor: '#e5edf0' },
  backText: { color: '#17324d', fontWeight: '700' },
  pending: { color: '#8c4f13', backgroundColor: '#fff1dc', borderRadius: 9, padding: 10, textAlign: 'right' },
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
  notifications: { marginTop: 10, padding: 16, backgroundColor: '#fff', borderWidth: 1, borderColor: '#e2e9eb', borderRadius: 16, gap: 10 },
  sectionTitle: { color: '#17324d', fontSize: 18, fontWeight: '800', textAlign: 'right' },
  notification: { borderTopWidth: 1, borderTopColor: '#edf1f3', paddingTop: 10, gap: 4 },
  notificationTitle: { color: '#17324d', fontWeight: '700', textAlign: 'right' },
});
