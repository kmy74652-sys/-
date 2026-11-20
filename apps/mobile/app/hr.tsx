import { Component, ReactNode, useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Stack } from 'expo-router';
import AppShell from '../components/AppShell';
import { friendlyDataError, getMyEmployeeProfile, type MobileProfile } from '../lib/mobileData';
import { createHRContract, createHRSchedule, createPayrollPeriod, listHRData, recordHRAttendance, upsertPayrollEntry, type HRMember } from '../lib/hrData';

type Tab = 'contracts' | 'attendance' | 'payroll';
const today = new Date().toISOString().slice(0, 10);
const emptyForm = { memberId: '', contractNo: '', contractType: 'employment', startDate: today, endDate: '', salary: '', duties: '', scheduleName: 'الدوام الأساسي', startTime: '08:00', endTime: '17:00', breakMinutes: '60', workDate: today, attendanceStatus: 'present', checkIn: '08:00', checkOut: '17:00', note: '', periodStart: today.slice(0, 8) + '01', periodEnd: today, periodId: '', base: '', additions: '0', deductions: '0' };

export default function HRScreen() {
  return <HRErrorBoundary><HRScreenContent /></HRErrorBoundary>;
}

class HRErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state: { error: Error | null } = { error: null };
  static getDerivedStateFromError(error: Error) { return { error }; }
  render() {
    if (this.state.error) return <View style={{ flex: 1, backgroundColor: '#f5f7fd', alignItems: 'center', justifyContent: 'center', padding: 24, direction: 'rtl' }}><Text style={{ color: '#17324d', fontSize: 20, fontWeight: '900', textAlign: 'center' }}>تعذر فتح الموارد البشرية</Text><Text style={{ color: '#718394', fontSize: 14, lineHeight: 23, textAlign: 'center', marginTop: 10 }}>حدث خطأ غير متوقع أثناء تحميل الشاشة. أغلقها وافتحها مرة أخرى، وإذا استمر الخطأ راجع مسؤول النظام.</Text></View>;
    return this.props.children;
  }
}

function HRScreenContent() {
  const [profile, setProfile] = useState<MobileProfile | null>(null); const [tab, setTab] = useState<Tab>('contracts'); const [data, setData] = useState<Awaited<ReturnType<typeof listHRData>> | null>(null); const [form, setForm] = useState(emptyForm); const [loading, setLoading] = useState(true); const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [notice, setNotice] = useState('');
  const canManage = Boolean(profile?.permissions?.includes('employee_hr.manage'));
  const memberName = (id: string) => data?.members?.find((member) => member.id === id)?.displayName ?? 'موظف غير محدد';
  const load = useCallback(async () => { setLoading(true); setError(''); try { const identity = await getMyEmployeeProfile(); if (!identity?.employee) throw new Error('employee_not_active'); setProfile(identity.employee); setData(await listHRData(identity.employee)); } catch (cause) { setError(friendlyDataError(cause, 'تعذر تحميل بيانات الموارد البشرية.')); } finally { setLoading(false); } }, []);
  useEffect(() => { void load(); }, [load]);
  function update(key: keyof typeof emptyForm, value: string) { setForm((current) => ({ ...current, [key]: value })); }
  async function run(action: () => Promise<void>, success: string) { setBusy(true); setError(''); setNotice(''); try { await action(); setNotice(success); setForm((current) => ({ ...emptyForm, memberId: current.memberId })); await load(); } catch (cause) { setError(friendlyDataError(cause, 'تعذر حفظ العملية. تحقق من الصلاحيات والبيانات.')); } finally { setBusy(false); } }
  const selectedMember = form.memberId || data?.members[0]?.id || '';
  const submitContract = () => run(() => createHRContract({ organizationId: profile!.institutionId, membershipId: selectedMember, contractNo: form.contractNo, contractType: form.contractType, startDate: form.startDate, endDate: form.endDate || null, baseSalary: form.salary ? Number(form.salary) : null, currency: 'SAR', payFrequency: 'monthly', duties: form.duties.split('\n').map((item) => item.trim()).filter(Boolean) }), 'تم حفظ عقد الموظف.');
  const submitSchedule = () => run(() => createHRSchedule({ organizationId: profile!.institutionId, membershipId: selectedMember, name: form.scheduleName, timezone: 'Asia/Riyadh', workDays: [0, 1, 2, 3, 4], startTime: form.startTime, endTime: form.endTime, breakMinutes: Number(form.breakMinutes || 0), effectiveFrom: form.startDate, effectiveTo: form.endDate || null }), 'تم حفظ جدول الدوام.');
  const submitAttendance = () => run(() => recordHRAttendance({ organizationId: profile!.institutionId, membershipId: selectedMember, workDate: form.workDate, status: form.attendanceStatus, checkInAt: form.checkIn ? new Date(`${form.workDate}T${form.checkIn}:00`).toISOString() : null, checkOutAt: form.checkOut ? new Date(`${form.workDate}T${form.checkOut}:00`).toISOString() : null, note: form.note }), 'تم تسجيل الحضور.');
  const submitPeriod = () => run(() => createPayrollPeriod({ organizationId: profile!.institutionId, start: form.periodStart, end: form.periodEnd }), 'تم إنشاء فترة الرواتب.');
  const submitEntry = () => run(() => upsertPayrollEntry({ organizationId: profile!.institutionId, periodId: form.periodId, membershipId: selectedMember, base: Number(form.base || 0), additions: Number(form.additions || 0), deductions: Number(form.deductions || 0), currency: 'SAR', note: form.note }), 'تم حفظ قيد الراتب.');
  const renderForm = () => {
    if (!canManage || !data) return null;
    return <View style={styles.card}>
      <Text style={styles.cardTitle}>{tab === 'contracts' ? 'إضافة عقد موظف' : tab === 'attendance' ? 'تسجيل حضور أو انصراف' : 'إدارة فترة وقيد راتب'}</Text>
      <MemberPicker members={data.members} value={selectedMember} onChange={(value) => update('memberId', value)} />
      {tab === 'contracts' && <>
        <Field label="رقم العقد" value={form.contractNo} onChangeText={(value) => update('contractNo', value)} placeholder="مثال: عقد-2026-001" />
        <Field label="تاريخ البداية" value={form.startDate} onChangeText={(value) => update('startDate', value)} placeholder="YYYY-MM-DD" />
        <Field label="تاريخ النهاية" value={form.endDate} onChangeText={(value) => update('endDate', value)} placeholder="اختياري" />
        <Field label="الراتب الأساسي" value={form.salary} onChangeText={(value) => update('salary', value)} placeholder="0.00" keyboardType="decimal-pad" />
        <Field label="المهام والمسؤوليات" value={form.duties} onChangeText={(value) => update('duties', value)} placeholder="كل مسؤولية في سطر" multiline />
        <Action disabled={busy} label="حفظ العقد" onPress={submitContract} />
      </>}
      {tab === 'attendance' && <>
        <Field label="تاريخ الدوام" value={form.workDate} onChangeText={(value) => update('workDate', value)} placeholder="YYYY-MM-DD" />
        <Field label="الحالة" value={form.attendanceStatus} onChangeText={(value) => update('attendanceStatus', value)} placeholder="present / absent / late" />
        <Field label="وقت الدخول" value={form.checkIn} onChangeText={(value) => update('checkIn', value)} placeholder="08:00" />
        <Field label="وقت الخروج" value={form.checkOut} onChangeText={(value) => update('checkOut', value)} placeholder="17:00" />
        <Field label="ملاحظة" value={form.note} onChangeText={(value) => update('note', value)} placeholder="اختياري" multiline />
        <Action disabled={busy} label="حفظ سجل الحضور" onPress={submitAttendance} />
        <Text style={styles.formDivider}>جدول الدوام</Text>
        <Field label="اسم الجدول" value={form.scheduleName} onChangeText={(value) => update('scheduleName', value)} placeholder="الدوام الأساسي" />
        <Field label="بداية الدوام" value={form.startTime} onChangeText={(value) => update('startTime', value)} placeholder="08:00" />
        <Field label="نهاية الدوام" value={form.endTime} onChangeText={(value) => update('endTime', value)} placeholder="17:00" />
        <Field label="دقائق الاستراحة" value={form.breakMinutes} onChangeText={(value) => update('breakMinutes', value)} placeholder="60" keyboardType="number-pad" />
        <Action disabled={busy} label="حفظ جدول الدوام" onPress={submitSchedule} />
      </>}
      {tab === 'payroll' && <>
        <Text style={styles.formDivider}>فترة جديدة</Text>
        <Field label="من" value={form.periodStart} onChangeText={(value) => update('periodStart', value)} placeholder="YYYY-MM-DD" />
        <Field label="إلى" value={form.periodEnd} onChangeText={(value) => update('periodEnd', value)} placeholder="YYYY-MM-DD" />
        <Action disabled={busy} label="إنشاء فترة الرواتب" onPress={submitPeriod} />
        <Text style={styles.formDivider}>قيد راتب</Text>
        <Field label="معرّف الفترة" value={form.periodId} onChangeText={(value) => update('periodId', value)} placeholder="اضغط على فترة من القائمة" />
        <Field label="الراتب الأساسي" value={form.base} onChangeText={(value) => update('base', value)} placeholder="0.00" keyboardType="decimal-pad" />
        <Field label="الإضافات" value={form.additions} onChangeText={(value) => update('additions', value)} placeholder="0.00" keyboardType="decimal-pad" />
        <Field label="الاستقطاعات" value={form.deductions} onChangeText={(value) => update('deductions', value)} placeholder="0.00" keyboardType="decimal-pad" />
        <Action disabled={busy} label="حفظ قيد الراتب" onPress={submitEntry} />
      </>}
    </View>;
  };
  const renderList = () => {
    if (!data) return null;
    return <View style={styles.list}>
      {tab === 'contracts' && (data.contracts ?? []).map((item) => <View style={styles.item} key={item.id}><Text style={styles.itemTitle}>{item.contractNo} — {memberName(item.membershipId)}</Text><Text style={styles.meta}>من {item.startDate}{item.endDate ? ` إلى ${item.endDate}` : ' · مفتوح'} · {item.status}</Text><Text style={styles.meta}>{item.baseSalary ?? 'غير محدد'} {item.currency} · {(item.duties ?? []).length} مسؤوليات</Text></View>)}
      {tab === 'attendance' && <>{(data.schedules ?? []).map((item) => <View style={styles.item} key={item.id}><Text style={styles.itemTitle}>جدول {item.name} — {memberName(item.membershipId)}</Text><Text style={styles.meta}>{item.startTime} إلى {item.endTime} · استراحة {item.breakMinutes} دقيقة</Text></View>)}{(data.attendance ?? []).map((item) => <View style={styles.item} key={item.id}><Text style={styles.itemTitle}>{item.workDate} — {memberName(item.membershipId)}</Text><Text style={styles.meta}>{item.status} · دخول {item.checkInAt ? new Date(item.checkInAt).toLocaleTimeString('ar-SA') : '—'} · خروج {item.checkOutAt ? new Date(item.checkOutAt).toLocaleTimeString('ar-SA') : '—'}</Text></View>)}</>}
      {tab === 'payroll' && (data.periods ?? []).map((item) => <View style={styles.item} key={item.id}><Pressable onPress={() => update('periodId', item.id)}><Text style={styles.itemTitle}>{item.start} إلى {item.end} · {item.status}</Text><Text style={styles.meta}>اضغط لاختيار الفترة · {(item.entries ?? []).length} قيود · {item.id}</Text></Pressable>{(item.entries ?? []).map((entry) => <Text style={styles.meta} key={entry.membershipId}>{memberName(entry.membershipId)}: صافي {Number(entry.net ?? 0).toFixed(2)} {entry.currency}</Text>)}</View>)}
    </View>;
  };
  return <AppShell activeTab="settings" title="الموارد البشرية" subtitle="العقود والدوام والرواتب" refreshing={loading} onRefresh={() => void load()}>
    <Stack.Screen options={{ headerShown: false }} />
    <View style={styles.content}>
      {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
      {!!notice && <Text accessibilityLiveRegion="polite" style={styles.success}>{notice}</Text>}
      <View style={styles.tabs}>{([{ key: 'contracts', label: 'العقود' }, { key: 'attendance', label: 'الدوام والحضور' }, { key: 'payroll', label: 'الرواتب' }] as const).map((item) => <Pressable key={item.key} style={[styles.tab, tab === item.key && styles.tabActive]} onPress={() => setTab(item.key)}><Text style={[styles.tabText, tab === item.key && styles.tabTextActive]}>{item.label}</Text></Pressable>)}</View>
      {loading || !data ? <View style={styles.loading}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.muted}>جارٍ تحميل بيانات الموارد البشرية…</Text></View> : <>{renderForm()}{renderList()}</>}
    </View>
  </AppShell>;

}
function MemberPicker({ members, value, onChange }: { members: HRMember[]; value: string; onChange: (value: string) => void }) { return <View><Text style={styles.label}>الموظف</Text><View style={styles.choices}>{members.map((member) => <Pressable key={member.id} style={[styles.choice, value === member.id && styles.choiceActive]} onPress={() => onChange(member.id)}><Text style={styles.choiceText}>{member.displayName}</Text></Pressable>)}</View></View>; }
function Field({ label, value, onChangeText, placeholder, multiline = false, keyboardType = 'default' }: { label: string; value: string; onChangeText: (value: string) => void; placeholder: string; multiline?: boolean; keyboardType?: 'default' | 'decimal-pad' | 'number-pad' }) { return <View><Text style={styles.label}>{label}</Text><TextInput style={[styles.input, multiline && styles.multiline]} value={value} onChangeText={onChangeText} placeholder={placeholder} placeholderTextColor="#91a0ad" multiline={multiline} keyboardType={keyboardType} /> </View>; }
function Action({ label, onPress, disabled }: { label: string; onPress: () => void; disabled: boolean }) { return <Pressable disabled={disabled} style={[styles.action, disabled && styles.disabled]} onPress={onPress}><Text style={styles.actionText}>{disabled ? 'جارٍ الحفظ…' : label}</Text></Pressable>; }
const styles = StyleSheet.create({ content: { padding: 12, gap: 12, direction: 'rtl' }, tabs: { flexDirection: 'row-reverse', gap: 7 }, tab: { flex: 1, minHeight: 44, borderRadius: 12, borderWidth: 1, borderColor: '#d2deeb', backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' }, tabActive: { backgroundColor: '#e5b336', borderColor: '#e5b336' }, tabText: { color: '#17324d', fontWeight: '800', fontSize: 12 }, tabTextActive: { fontWeight: '900' }, card: { backgroundColor: '#fff', borderRadius: 16, padding: 14, gap: 9, borderWidth: 1, borderColor: '#dfe7ee' }, cardTitle: { color: '#17324d', fontSize: 18, fontWeight: '900', textAlign: 'right' }, label: { color: '#506477', fontSize: 12, fontWeight: '800', textAlign: 'right', marginTop: 2 }, input: { minHeight: 44, borderRadius: 10, borderWidth: 1, borderColor: '#d3dee8', backgroundColor: '#fbfcfe', paddingHorizontal: 11, textAlign: 'right', color: '#17324d' }, multiline: { minHeight: 88, textAlignVertical: 'top', paddingTop: 10 }, choices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 6 }, choice: { borderWidth: 1, borderColor: '#d3dee8', paddingVertical: 8, paddingHorizontal: 10, borderRadius: 10 }, choiceActive: { backgroundColor: '#dceee7', borderColor: '#287653' }, choiceText: { color: '#36536a', fontSize: 12, fontWeight: '700' }, action: { minHeight: 45, borderRadius: 11, alignItems: 'center', justifyContent: 'center', backgroundColor: '#17324d', marginTop: 4 }, disabled: { opacity: 0.55 }, actionText: { color: '#fff', fontWeight: '900' }, formDivider: { color: '#a6761f', fontWeight: '900', textAlign: 'right', borderTopWidth: 1, borderTopColor: '#e7edf2', paddingTop: 10, marginTop: 4 }, list: { gap: 9 }, item: { backgroundColor: '#fff', borderRadius: 14, padding: 13, borderWidth: 1, borderColor: '#dfe7ee', gap: 5 }, itemTitle: { color: '#17324d', fontSize: 15, fontWeight: '900', textAlign: 'right' }, meta: { color: '#718394', fontSize: 12, textAlign: 'right', lineHeight: 19 }, error: { color: '#a8443d', backgroundColor: '#fff0ee', padding: 12, borderRadius: 10, textAlign: 'right' }, success: { color: '#23633c', backgroundColor: '#e7f5ed', padding: 12, borderRadius: 10, textAlign: 'right' }, loading: { alignItems: 'center', padding: 30 }, muted: { color: '#718394', marginTop: 8, textAlign: 'center' } });
