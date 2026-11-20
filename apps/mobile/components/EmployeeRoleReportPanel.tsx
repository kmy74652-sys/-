import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { friendlyDataError } from '../lib/mobileData';
import { listMyRoleReports, roleReportConfig, submitEmployeeRoleReport, type RoleReport } from '../lib/employeeRoleReports';

export default function EmployeeRoleReportPanel({ roleCode, branchId, employeeName }: { roleCode: string; branchId: string | null; employeeName: string }) {
  const config = useMemo(() => roleReportConfig(roleCode), [roleCode]);
  const [values, setValues] = useState<Record<string, string>>({});
  const [reports, setReports] = useState<RoleReport[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const today = new Date().toISOString().slice(0, 10);
  const todayReport = reports.find((item) => item.report_date === today);
  const locked = todayReport?.status === 'submitted' || todayReport?.status === 'approved';

  async function load() {
    try { setLoading(true); setError(''); const rows = await listMyRoleReports(roleCode); setReports(rows); const current = rows.find((item) => item.report_date === today && item.status === 'returned'); if (current) setValues(current.values ?? {}); }
    catch (cause) { setError(friendlyDataError(cause, 'تعذر تحميل تقرير الدور.')); }
    finally { setLoading(false); }
  }
  useEffect(() => { void load(); }, [roleCode]);
  async function submit() {
    if (locked) return;
    setBusy(true); setError(''); setNotice('');
    try { await submitEmployeeRoleReport({ roleCode, branchId, reportDate: today, reportTitle: config.title, values }); setNotice('تم إرسال التقرير للإدارة للمراجعة.'); await load(); }
    catch (cause) { setError(friendlyDataError(cause, 'تعذر إرسال التقرير.')); }
    finally { setBusy(false); }
  }
  return <View style={styles.card}>
    <Text style={styles.title}>{config.title}</Text>
    <Text style={styles.subtitle}>تقرير الدور اليومي · {employeeName}</Text>
    {todayReport?.status === 'returned' && <Text style={styles.warning}>أُعيد التقرير للتعديل{todayReport.review_note ? `: ${todayReport.review_note}` : ''}</Text>}
    {loading ? <View style={styles.loading}><ActivityIndicator color="#17324d" /><Text style={styles.muted}>جارٍ تحميل التقرير…</Text></View> : <>{config.fields.map((field) => <TextInput key={field.key} editable={!locked} value={values[field.key] ?? ''} onChangeText={(value) => setValues((current) => ({ ...current, [field.key]: value }))} multiline={Boolean(field.long)} style={[styles.input, field.long && styles.long]} placeholder={field.label} textAlign="right" />)}<Pressable disabled={busy || locked} style={[styles.submit, (busy || locked) && styles.disabled]} onPress={() => void submit()}><Text style={styles.submitText}>{locked ? todayReport?.status === 'approved' ? 'تم اعتماد تقرير اليوم' : 'تم إرسال تقرير اليوم' : busy ? 'جارٍ الإرسال…' : 'إرسال التقرير للإدارة'}</Text></Pressable></>}
    {!!notice && <Text style={styles.notice}>{notice}</Text>}
    {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
  </View>;
}
const styles = StyleSheet.create({ card: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#e2e9eb', padding: 14, gap: 10 }, title: { color: '#17324d', fontSize: 17, fontWeight: '900', textAlign: 'right' }, subtitle: { color: '#718394', fontSize: 12, textAlign: 'right' }, input: { minHeight: 46, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingHorizontal: 11, paddingVertical: 9, color: '#17324d', backgroundColor: '#fbfcfc' }, long: { minHeight: 82, textAlignVertical: 'top' }, submit: { minHeight: 48, borderRadius: 10, backgroundColor: '#17324d', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12 }, submitText: { color: '#fff', fontWeight: '900' }, disabled: { opacity: 0.55 }, warning: { color: '#8c4f13', backgroundColor: '#fff1dc', borderRadius: 9, padding: 10, textAlign: 'right', lineHeight: 20 }, notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 9, padding: 10, textAlign: 'right' }, error: { color: '#a8443d', backgroundColor: '#fff0ef', borderRadius: 9, padding: 10, textAlign: 'right' }, loading: { alignItems: 'center', gap: 8, padding: 20 }, muted: { color: '#718394' } });
