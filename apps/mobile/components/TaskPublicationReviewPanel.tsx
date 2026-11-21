import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { listPendingTaskPublicationRequests, reviewTaskPublicationRequest, type TaskPublicationRequest } from '../lib/taskPublication';

type Branch = { id: string; name: string };
type Props = { branches: Branch[]; onPublished?: () => void | Promise<void> };

const roleNames: Record<string, string> = {
  owner: 'صاحب المؤسسة', admin_followup: 'المدير التنفيذي', accountant: 'المحاسب',
  warehouse_keeper: 'أمين المخازن', warehouse_worker: 'عمال التحميل',
};

function readDesignerDescription(value: unknown) {
  if (typeof value !== 'string') return null;
  try {
    const parsed = JSON.parse(value);
    return parsed?.__alshaairy_task_designer_v1 ? parsed : null;
  } catch { return null; }
}

export default function TaskPublicationReviewPanel({ branches, onPublished }: Props) {
  const [items, setItems] = useState<TaskPublicationRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState('');
  const [note, setNote] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setLoading(true); setError('');
    try { setItems(await listPendingTaskPublicationRequests()); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحميل المهام بانتظار الاعتماد.'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function review(item: TaskPublicationRequest, approve: boolean) {
    const message = approve
      ? 'بعد الاعتماد ستُنشر المهمة تلقائياً لجميع الموظفين النشطين المطابقين للتصنيف والفرع، ولا يمكن تكرار النشر لهذا الطلب.'
      : 'سيُرفض طلب النشر ولن تصل المهمة إلى الموظفين.';
    Alert.alert(approve ? 'اعتماد ونشر المهمة' : 'رفض المهمة', message, [
      { text: 'إلغاء', style: 'cancel' },
      { text: approve ? 'اعتماد ونشر' : 'تأكيد الرفض', style: approve ? 'default' : 'destructive', onPress: () => void performReview(item, approve) },
    ]);
  }

  async function performReview(item: TaskPublicationRequest, approve: boolean) {
    setBusyId(item.id); setError('');
    try {
      const count = await reviewTaskPublicationRequest(item.id, approve, note);
      setNote('');
      await load();
      if (approve) {
        Alert.alert('تم الاعتماد والنشر', `وصلت المهمة إلى ${count} موظفاً مطابقاً.`);
        await onPublished?.();
      } else {
        Alert.alert('تم رفض الطلب', 'لم يتم إرسال المهمة إلى أي موظف.');
      }
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر تنفيذ قرار الاعتماد.');
    } finally { setBusyId(''); }
  }

  return <View style={styles.container}>
    <View style={styles.header}>
      <View style={{ flex: 1 }}>
        <Text style={styles.title}>مراجعة واعتماد المهام قبل النشر</Text>
        <Text style={styles.subtitle}>لا تظهر المهام في حسابات الموظفين إلا بعد اعتماد صاحب المؤسسة.</Text>
      </View>
      <Pressable onPress={() => void load()} style={styles.refresh}><Text style={styles.refreshText}>تحديث</Text></Pressable>
    </View>
    {!!error && <Text style={styles.error}>{error}</Text>}
    {loading ? <ActivityIndicator color="#17324d" /> : items.length === 0
      ? <Text style={styles.empty}>لا توجد مهام جديدة بانتظار الاعتماد.</Text>
      : <ScrollView nestedScrollEnabled style={{ maxHeight: 620 }} contentContainerStyle={{ gap: 12 }}>
        {items.map((item) => {
          const snapshot = item.template_snapshot ?? {};
          const designer = readDesignerDescription(snapshot.description);
          const rows = Array.isArray(designer?.rows) ? designer.rows : [];
          const steps = Array.isArray(snapshot.steps) ? snapshot.steps : [];
          const branchName = branches.find((branch) => branch.id === item.branch_id)?.name ?? (item.branch_id ? 'فرع غير معروف' : 'جميع الفروع');
          return <View key={item.id} style={styles.card}>
            <Text style={styles.taskTitle}>{snapshot.title ?? 'مهمة بدون عنوان'}</Text>
            <Text style={styles.meta}>التصنيف: {roleNames[item.role_code] ?? item.role_code} · الفرع: {branchName}</Text>
            <Text style={styles.meta}>عدد صفوف الجدول: {rows.length || steps.length} · الحقول: {Array.isArray(snapshot.report_fields) ? snapshot.report_fields.length : 0}</Text>
            <Text style={styles.meta}>موعد التسليم: {new Date(item.due_at).toLocaleString('ar')}</Text>
            {rows.length > 0 ? <View style={styles.table}>
              <View style={styles.tableHeader}><Text style={[styles.cell, styles.headerCell]}>الفترة</Text><Text style={[styles.cell, styles.headerCell]}>المهمة والمسؤولية</Text><Text style={[styles.cell, styles.headerCell]}>مؤشر الأداء</Text></View>
              {rows.map((row: any, index: number) => <View key={index} style={styles.tableRow}>
                <Text style={styles.cell}>{row.timeSlot ?? '—'}</Text>
                <Text style={styles.cell}>{row.responsibility ?? '—'}{Array.isArray(row.subItems) && row.subItems.length ? '\n' + row.subItems.map((v: string) => '• ' + v).join('\n') : ''}</Text>
                <Text style={styles.cell}>{row.kpiIndicator ?? '—'}</Text>
              </View>)}
            </View> : <View style={styles.table}>{steps.map((step: any, index: number) => <Text key={index} style={styles.meta}>{index + 1}. {step.title} — {step.instructions ?? ''}</Text>)}</View>}
            {!!designer?.continuous?.length && <Text style={styles.meta}>المهام المستمرة: {designer.continuous.join(' · ')}</Text>}
            {!!designer?.recommendations?.length && <Text style={styles.meta}>الضوابط: {designer.recommendations.join(' · ')}</Text>}
            <TextInput value={note} onChangeText={setNote} placeholder="ملاحظة اعتماد أو سبب الرفض (اختياري)" style={styles.note} multiline />
            <View style={styles.actions}>
              <Pressable disabled={Boolean(busyId)} style={styles.reject} onPress={() => void review(item, false)}><Text style={styles.rejectText}>{busyId === item.id ? 'جارٍ التنفيذ…' : 'رفض وإرجاع'}</Text></Pressable>
              <Pressable disabled={Boolean(busyId)} style={styles.approve} onPress={() => void review(item, true)}><Text style={styles.approveText}>{busyId === item.id ? 'جارٍ الاعتماد…' : 'اعتماد ونشر للموظفين'}</Text></Pressable>
            </View>
          </View>;
        })}
      </ScrollView>}
  </View>;
}

const styles = StyleSheet.create({
  container: { backgroundColor: '#f6f8fa', borderWidth: 1, borderColor: '#dce5e9', borderRadius: 14, padding: 12, gap: 10, marginBottom: 14 },
  header: { flexDirection: 'row-reverse', alignItems: 'center', gap: 8 },
  title: { color: '#17324d', fontSize: 17, fontWeight: '900', textAlign: 'right' },
  subtitle: { color: '#607487', textAlign: 'right', fontSize: 12, marginTop: 4 },
  refresh: { backgroundColor: '#e8eff4', paddingHorizontal: 12, paddingVertical: 8, borderRadius: 8 },
  refreshText: { color: '#17324d', fontWeight: '800' },
  error: { color: '#a32626', textAlign: 'right' },
  empty: { color: '#607487', textAlign: 'center', padding: 18 },
  card: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#dce5e9', borderRadius: 12, padding: 11, gap: 8 },
  taskTitle: { color: '#17324d', fontSize: 16, fontWeight: '900', textAlign: 'right' },
  meta: { color: '#52687a', textAlign: 'right', fontSize: 12, lineHeight: 19 },
  table: { borderWidth: 1, borderColor: '#d9e2e7', borderRadius: 8, overflow: 'hidden' },
  tableHeader: { flexDirection: 'row-reverse', backgroundColor: '#eaf0f4' },
  tableRow: { flexDirection: 'row-reverse', borderTopWidth: 1, borderTopColor: '#e3e9ed' },
  cell: { flex: 1, color: '#31495d', textAlign: 'right', fontSize: 11, lineHeight: 17, padding: 6, borderLeftWidth: 1, borderLeftColor: '#e3e9ed' },
  headerCell: { color: '#17324d', fontWeight: '900' },
  note: { minHeight: 42, borderWidth: 1, borderColor: '#d5dfe4', borderRadius: 8, padding: 9, textAlign: 'right', color: '#17324d' },
  actions: { flexDirection: 'row-reverse', gap: 8 },
  reject: { flex: 1, backgroundColor: '#fff1ef', borderRadius: 8, padding: 11, alignItems: 'center' },
  rejectText: { color: '#9e3830', fontWeight: '900' },
  approve: { flex: 1.4, backgroundColor: '#17324d', borderRadius: 8, padding: 11, alignItems: 'center' },
  approveText: { color: '#fff', fontWeight: '900' },
});
