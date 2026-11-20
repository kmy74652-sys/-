import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { friendlyDataError } from '../lib/mobileData';
import { listMyDynamicReports, submitMyDynamicReport, type DynamicEmployeeReport } from '../lib/dynamicReports';
import { reportDefaultDraft } from '../lib/reportSchema';

export default function EmployeeDynamicReportsPanel({ branchId }: { branchId: string | null }) {
  const [forms, setForms] = useState<DynamicEmployeeReport[]>([]);
  const [values, setValues] = useState<Record<string, Record<string, string>>>({});
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  async function load() {
    try {
      setLoading(true);
      setError('');
      const rows = await listMyDynamicReports();
      setForms(rows);
      setValues((current) => {
        const next = { ...current };
        for (const form of rows) {
          const existing = { ...next[form.template_id] };
          for (const field of form.fields) {
            if (existing[field.key] === undefined) {
              const persisted = form.values?.[field.key];
              existing[field.key] = persisted === undefined ? reportDefaultDraft(field) : typeof persisted === 'string' ? persisted : JSON.stringify(persisted);
            }
          }
          next[form.template_id] = existing;
        }
        return next;
      });
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر تحميل تقارير مصمم التقارير.'));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); }, [branchId]);

  async function submit(form: DynamicEmployeeReport) {
    setBusy(form.template_id);
    setError('');
    setNotice('');
    try {
      await submitMyDynamicReport({ templateId: form.template_id, versionId: form.version_id, reportDate: form.report_date, branchId, values: values[form.template_id] ?? {} });
      setNotice(`تم إرسال «${form.title}» للإدارة للمراجعة.`);
      await load();
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر إرسال التقرير الديناميكي.'));
    } finally {
      setBusy('');
    }
  }

  if (loading) return <View style={styles.loading}><ActivityIndicator color="#17324d" /><Text style={styles.muted}>جارٍ تحميل نماذج مصمم التقارير…</Text></View>;
  if (!forms.length) return <View style={styles.empty}><Text style={styles.emptyTitle}>لا توجد تقارير ديناميكية معتمدة</Text><Text style={styles.muted}>ستظهر هنا النماذج التي اعتمدتها الإدارة من مصمم التقارير والمخصصة لدورك.</Text></View>;

  return <View style={styles.section}>
    {forms.map((form) => {
      const locked = form.status === 'submitted' || form.status === 'approved';
      const statusLabel = form.status === 'approved' ? 'تم اعتماد التقرير' : form.status === 'submitted' ? 'بانتظار مراجعة الإدارة' : form.status === 'returned' ? 'أعيد للتعديل' : 'جاهز للتعبئة';
      return <View style={styles.card} key={`${form.template_id}:${form.version_id}`}>
        <View style={styles.heading}><Text style={styles.title}>{form.title}</Text><Text style={[styles.badge, form.status === 'returned' && styles.returnedBadge]}>{statusLabel}</Text></View>
        {!!form.description && <Text style={styles.description}>{form.description}</Text>}
        {!!form.review_note && form.status === 'returned' && <Text style={styles.warning}>ملاحظة الإدارة: {form.review_note}</Text>}
        <Text style={styles.date}>تقرير مستقل · {form.report_date}</Text>
        {form.fields.map((field) => <View style={styles.field} key={field.key}>
          <Text style={styles.label}>{field.label}{field.required ? ' *' : ''}</Text>
          {!!field.description && <Text style={styles.fieldHint}>{field.description}</Text>}
          <TextInput editable={!locked} value={values[form.template_id]?.[field.key] ?? ''} onChangeText={(value) => setValues((current) => ({ ...current, [form.template_id]: { ...current[form.template_id], [field.key]: value } }))} placeholder={field.type === 'datetime' ? 'يُسجل تلقائياً عند الإرسال' : 'اكتب الإجابة هنا'} multiline={field.type === 'long_text' || field.type === 'decision_notes'} style={[styles.input, (field.type === 'long_text' || field.type === 'decision_notes') && styles.longInput]} textAlign="right" />
        </View>)}
        <Pressable disabled={locked || busy === form.template_id} style={[styles.submit, locked && styles.disabled]} onPress={() => void submit(form)}><Text style={styles.submitText}>{busy === form.template_id ? 'جارٍ الإرسال…' : locked ? statusLabel : 'إرسال التقرير للإدارة'}</Text></Pressable>
      </View>;
    })}
    {!!notice && <Text style={styles.notice}>{notice}</Text>}
    {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
  </View>;
}

const styles = StyleSheet.create({
  section: { gap: 12 }, card: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#e2e9eb', padding: 14, gap: 10 }, heading: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8 }, title: { flex: 1, color: '#17324d', fontSize: 18, fontWeight: '900', textAlign: 'right' }, badge: { color: '#23633c', backgroundColor: '#e5f4e9', borderRadius: 14, paddingHorizontal: 10, paddingVertical: 6, fontSize: 12, fontWeight: '800' }, returnedBadge: { color: '#8c4f13', backgroundColor: '#fff1dc' }, description: { color: '#52687a', lineHeight: 21, textAlign: 'right' }, date: { color: '#718394', fontSize: 12, textAlign: 'right' }, field: { gap: 4 }, label: { color: '#263f52', fontWeight: '800', textAlign: 'right' }, fieldHint: { color: '#718394', fontSize: 12, textAlign: 'right' }, input: { minHeight: 46, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingHorizontal: 11, paddingVertical: 9, color: '#17324d', backgroundColor: '#fbfcfc' }, longInput: { minHeight: 90, textAlignVertical: 'top' }, submit: { minHeight: 48, borderRadius: 10, backgroundColor: '#17324d', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12 }, submitText: { color: '#fff', fontWeight: '900' }, disabled: { opacity: 0.55 }, warning: { color: '#8c4f13', backgroundColor: '#fff1dc', borderRadius: 9, padding: 10, textAlign: 'right', lineHeight: 20 }, notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 9, padding: 10, textAlign: 'right' }, error: { color: '#a8443d', backgroundColor: '#fff0ef', borderRadius: 9, padding: 10, textAlign: 'right' }, loading: { alignItems: 'center', gap: 8, padding: 20 }, empty: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#e2e9eb', padding: 16, gap: 7 }, emptyTitle: { color: '#17324d', fontSize: 17, fontWeight: '900', textAlign: 'right' }, muted: { color: '#718394', textAlign: 'center', lineHeight: 21 },
});
