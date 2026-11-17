import { useEffect, useState } from 'react';
import { useRouter, type ErrorBoundaryProps } from 'expo-router';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { friendlyDataError, getMyEmployeeProfile } from '../lib/mobileData';
import { supabase } from '../lib/supabase';

type EmployeeAccess = {
  id: string;
  employeeNo: string | null;
  fullName: string | null;
  status: string;
  hasAuthAccount: boolean;
  codeSetAt: string | null;
  roleCode: string | null;
  branchId: string | null;
  branchName: string | null;
};
type Branch = { id: string; name: string };
type AuditEntry = { id: string; action: string; created_at: string; metadata?: Record<string, unknown> };
const roleOptions = [
  ['owner', 'صاحب المؤسسة'],
  ['admin_followup', 'المدير التنفيذي'],
  ['accountant', 'المحاسب'],
  ['warehouse_keeper', 'أمين المخازن'],
  ['warehouse_worker', 'عامل تحميل'],
] as const;

type EmployeeListResult = { employees?: EmployeeAccess[]; branches?: Array<Branch & { code: string; is_active: boolean }> };

function functionStatus(error: unknown) {
  return (error as { context?: { status?: number } } | null)?.context?.status;
}

function functionErrorText(error: unknown) {
  const status = functionStatus(error);
  if (status === 401) return 'انتهت الجلسة. سجّل الدخول مجددًا.';
  if (status === 403) return 'هذه الإعدادات متاحة لصاحب المؤسسة أو المدير التنفيذي المخوّل.';
  if (status === 404 || status === 503) return 'خدمة الرموز أو تحديث قاعدة البيانات غير جاهز في Supabase بعد.';
  if (status === 429) return 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.';
  return 'تعذر إكمال الطلب. تحقق من الاتصال وحاول مجددًا.';
}

function normalizeEmployeeList(data: unknown): EmployeeAccess[] {
  const employees = (data as EmployeeListResult | null)?.employees;
  if (!Array.isArray(employees)) return [];
  return employees.filter((employee) => employee && typeof employee.id === 'string').map((employee) => ({
    id: employee.id,
    employeeNo: typeof employee.employeeNo === 'string' ? employee.employeeNo : null,
    fullName: typeof employee.fullName === 'string' ? employee.fullName : null,
    status: typeof employee.status === 'string' ? employee.status : 'inactive',
    hasAuthAccount: employee.hasAuthAccount === true,
    codeSetAt: typeof employee.codeSetAt === 'string' ? employee.codeSetAt : null,
    roleCode: typeof employee.roleCode === 'string' ? employee.roleCode : null,
    branchId: typeof employee.branchId === 'string' ? employee.branchId : null,
    branchName: typeof employee.branchName === 'string' ? employee.branchName : null,
  }));
}

export default function EmployeeAccessSettings() {
  const router = useRouter();
  const [employees, setEmployees] = useState<EmployeeAccess[]>([]);
  const [codes, setCodes] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busyEmployeeId, setBusyEmployeeId] = useState<string | null>(null);
  const [isOwner, setIsOwner] = useState(false);
  const [canAssignOwner, setCanAssignOwner] = useState(false);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [createForm, setCreateForm] = useState({ employeeNo: '', fullName: '', code: '', roleCode: 'warehouse_worker', branchId: '' });
  const [editForms, setEditForms] = useState<Record<string, { employeeNo: string; fullName: string; roleCode: string; branchId: string; status: 'active' | 'suspended' }>>({});
  const [audit, setAudit] = useState<Record<string, AuditEntry[]>>({});
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  useEffect(() => {
    void loadSettings();
  }, []);

  async function loadSettings() {
    setLoading(true);
    setError('');
    try {
      if (!supabase) throw new Error('supabase_not_configured');
      const identity = await getMyEmployeeProfile();
      if (!identity?.employee) {
        setIsOwner(false);
        setError('يجب تسجيل الدخول بحساب صاحب المؤسسة أو المدير التنفيذي المخوّل لفتح هذه الإعدادات.');
        return;
      }
      const employeeRoles = Array.isArray(identity.employee.roles) ? identity.employee.roles : [];
      const employeePermissions = Array.isArray(identity.employee.permissions) ? identity.employee.permissions : [];
      setCanAssignOwner(employeeRoles.some((role) => role?.code === 'owner'));
      const owner = employeeRoles.some((role) => role?.code === 'owner' || role?.code === 'admin_followup')
        && employeePermissions.includes('employees.manage');
      setIsOwner(owner);
      if (!owner) {
        setError('هذه الإعدادات متاحة لصاحب المؤسسة أو المدير التنفيذي المخوّل.');
        return;
      }
      const { data, error: listError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'list' },
      });
      if (listError) {
        setError(functionErrorText(listError));
        return;
      }
      const normalized = normalizeEmployeeList(data);
      setEmployees(normalized);
      const nextBranches = ((data as EmployeeListResult | null)?.branches ?? [])
        .filter((branch) => branch.is_active)
        .map((branch) => ({ id: branch.id, name: branch.name }));
      setBranches(nextBranches);
      if (!createForm.branchId && nextBranches[0]) setCreateForm((current) => ({ ...current, branchId: nextBranches[0].id }));
      setEditForms((current) => Object.fromEntries(normalized.map((employee) => [employee.id, {
        employeeNo: employee.employeeNo ?? '',
        fullName: employee.fullName ?? '',
        roleCode: employee.roleCode ?? 'warehouse_worker',
        branchId: employee.branchId ?? nextBranches[0]?.id ?? '',
        status: employee.status === 'active' ? 'active' : 'suspended',
      }] )));
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر تحميل قائمة الموظفين. تحقق من الاتصال ثم أعد المحاولة.'));
    } finally {
      setLoading(false);
    }
  }

  async function createEmployee() {
    if (!supabase) return;
    if (!/^\d{1,32}$/.test(createForm.employeeNo) || createForm.fullName.trim().length < 2 || !/^\S{8,64}$/.test(createForm.code) || !createForm.branchId) {
      setError('أدخل رقمًا وظيفيًا واسمًا وكلمة مرور أولية من 8 إلى 64 محرفًا واختر الفرع.');
      return;
    }
    setBusyEmployeeId('create'); setError(''); setMessage('');
    try {
      const { data, error: createError } = await supabase.functions.invoke('employee-code-auth', { body: { action: 'create_employee', employeeNo: createForm.employeeNo, fullName: createForm.fullName, code: createForm.code, roleCode: createForm.roleCode, branchId: createForm.branchId } });
      if (createError) { setError(functionErrorText(createError)); return; }
      setCreateForm({ employeeNo: '', fullName: '', code: '', roleCode: 'warehouse_worker', branchId: branches[0]?.id ?? '' });
      setMessage(`تم إنشاء الحساب للموظف ${data?.employee?.fullName ?? ''}. لن تظهر كلمة المرور مرة أخرى.`);
      await loadSettings();
    } catch { setError('تعذر إنشاء حساب الموظف.'); } finally { setBusyEmployeeId(null); }
  }

  async function updateEmployee(employee: EmployeeAccess) {
    if (!supabase) return;
    const draft = editForms[employee.id];
    if (!draft) return;
    setBusyEmployeeId(employee.id); setError(''); setMessage('');
    try {
      const { error: updateError } = await supabase.functions.invoke('employee-code-auth', { body: { action: 'update_employee', employeeId: employee.id, ...draft } });
      if (updateError) { setError(functionErrorText(updateError)); return; }
      setMessage(`تم تحديث بيانات ${draft.fullName}.`);
      await loadSettings();
    } catch { setError('تعذر تحديث بيانات الموظف.'); } finally { setBusyEmployeeId(null); }
  }

  async function saveCode(employee: EmployeeAccess) {
    const code = codes[employee.id] ?? '';
    if (!/^\S{8,64}$/.test(code)) {
      setError('اكتب رمزًا من 8 إلى 64 محرفًا دون مسافات.');
      setMessage('');
      return;
    }
    if (!supabase) return;
    setBusyEmployeeId(employee.id);
    setError('');
    setMessage('');
    try {
      const { error: saveError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'set_code', employeeId: employee.id, code },
      });
      if (saveError) {
        setError(functionErrorText(saveError));
        return;
      }
      setCodes((current) => ({ ...current, [employee.id]: '' }));
      setMessage(`تم تحديث رمز دخول ${employee.fullName}. لن يظهر الرمز المحفوظ على الشاشة.`);
      const { data, error: refreshError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'list' },
      });
      if (!refreshError) setEmployees(normalizeEmployeeList(data));
    } catch {
      setError('تعذر حفظ الرمز. تحقق من الاتصال ثم حاول مجددًا.');
    } finally {
      setBusyEmployeeId(null);
    }
  }

  async function loadAudit(employee: EmployeeAccess) {
    if (!supabase) return;
    const { data, error: auditError } = await supabase.functions.invoke('employee-code-auth', { body: { action: 'audit', employeeId: employee.id } });
    if (auditError) { setError(functionErrorText(auditError)); return; }
    setAudit((current) => ({ ...current, [employee.id]: Array.isArray(data?.audit) ? data.audit : [] }));
  }

  function confirmRevoke(employee: EmployeeAccess) {
    Alert.alert(
      'إلغاء رمز الدخول',
      `سيُمنع ${employee.fullName} من تسجيل دخول جديد بهذا الرمز. الجلسات المفتوحة حاليًا لن تُنهى فورًا. هل تريد المتابعة؟`,
      [
        { text: 'إلغاء', style: 'cancel' },
        { text: 'إلغاء الرمز', style: 'destructive', onPress: () => void revokeCode(employee) },
      ],
    );
  }

  async function revokeCode(employee: EmployeeAccess) {
    if (!supabase) return;
    setBusyEmployeeId(employee.id);
    setError('');
    setMessage('');
    try {
      const { error: revokeError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'revoke_code', employeeId: employee.id },
      });
      if (revokeError) {
        setError(functionErrorText(revokeError));
        return;
      }
      setMessage(`تم إلغاء رمز الدخول لـ ${employee.fullName}.`);
      const { data, error: refreshError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'list' },
      });
      if (!refreshError) setEmployees(normalizeEmployeeList(data));
    } catch {
      setError('تعذر إلغاء الرمز. تحقق من الاتصال ثم حاول مجددًا.');
    } finally {
      setBusyEmployeeId(null);
    }
  }

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Pressable accessibilityRole="button" onPress={() => router.back()} style={styles.back}>
          <Text style={styles.backText}>العودة</Text>
        </Pressable>
        <Text style={styles.eyebrow}>إدارة آمنة للدخول</Text>
        <Text style={styles.title}>رموز دخول الموظفين</Text>
        <Text style={styles.copy}>
          عيّن لكل موظف رمزًا خاصًا لا يقل عن 8 محارف. يُحفظ الرمز كبيانات اعتماد محمية لدى Supabase ولا يمكن استرجاعه بعد الحفظ؛ لتغييره أدخل رمزًا جديدًا.
        </Text>
        <Text style={styles.note}>
          إلغاء الرمز يمنع تسجيلات الدخول الجديدة، لكنه لا ينهي الجلسات المفتوحة حاليًا. لا تشارك الرمز في محادثة عامة.
        </Text>
        {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
        {!!message && <Text accessibilityLiveRegion="polite" style={styles.success}>{message}</Text>}

        {!loading && isOwner && (
          <View style={styles.employeeCard}>
            <Text style={styles.employeeName}>إنشاء حساب موظف</Text>
            <TextInput style={styles.input} placeholder="اسم الموظف" value={createForm.fullName} onChangeText={(value) => setCreateForm((current) => ({ ...current, fullName: value }))} />
            <TextInput style={styles.input} placeholder="رقم الموظف الفريد" keyboardType="number-pad" value={createForm.employeeNo} onChangeText={(value) => setCreateForm((current) => ({ ...current, employeeNo: value }))} />
            <TextInput style={styles.input} placeholder="كلمة المرور الأولية" secureTextEntry value={createForm.code} onChangeText={(value) => setCreateForm((current) => ({ ...current, code: value }))} />
            <Text style={styles.employeeMeta}>التصنيف الوظيفي</Text>
            <View style={styles.roleChoices}>{roleOptions.filter(([code]) => code !== 'owner' || canAssignOwner).map(([code, label]) => <Pressable key={code} accessibilityRole="button" style={[styles.roleChoice, createForm.roleCode === code && styles.roleChoiceActive]} onPress={() => setCreateForm((current) => ({ ...current, roleCode: code }))}><Text style={styles.roleChoiceText}>{label}</Text></Pressable>)}</View>
            <Text style={styles.employeeMeta}>الفرع</Text>
            <View style={styles.roleChoices}>{branches.map((branch) => <Pressable key={branch.id} accessibilityRole="button" style={[styles.roleChoice, createForm.branchId === branch.id && styles.roleChoiceActive]} onPress={() => setCreateForm((current) => ({ ...current, branchId: branch.id }))}><Text style={styles.roleChoiceText}>{branch.name}</Text></Pressable>)}</View>
            <Pressable accessibilityRole="button" disabled={busyEmployeeId !== null} style={styles.primaryButton} onPress={() => void createEmployee()}><Text style={styles.buttonText}>{busyEmployeeId === 'create' ? 'جارٍ الإنشاء…' : 'إنشاء الحساب'}</Text></Pressable>
          </View>
        )}

        {loading ? (
          <View style={styles.loading}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.copy}>جارٍ تحميل الموظفين…</Text></View>
        ) : isOwner && employees.length === 0 ? (
          <Text style={styles.copy}>لا توجد ملفات موظفين مرتبطة بهذه المؤسسة.</Text>
        ) : isOwner ? employees.map((employee) => {
          const active = employee.status === 'active';
          const busy = busyEmployeeId === employee.id;
          return (
            <View style={styles.employeeCard} key={employee.id}>
              <Text style={styles.employeeName}>{employee.fullName || 'موظف'}</Text>
              <Text style={styles.employeeMeta}>رقم الموظف: {employee.employeeNo || 'غير محدد'}</Text>
              <Text style={styles.employeeMeta}>
                {employee.codeSetAt ? 'تم تعيين رمز دخول' : 'لم يُعيّن رمز دخول بعد'}
                {!active ? ' · الحساب غير نشط' : ''}
              </Text>
              {!employee.hasAuthAccount && (
                <Text style={styles.warning}>لا يوجد حساب مصادقة مرتبط بملف هذا الموظف؛ لا يمكن تعيين كلمة مرور له حتى يربطه مسؤول النظام.</Text>
              )}
              {isOwner && editForms[employee.id] && (
                <>
                  <TextInput style={styles.input} placeholder="الاسم" value={editForms[employee.id].fullName} onChangeText={(value) => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], fullName: value } }))} />
                  <TextInput style={styles.input} placeholder="الرقم الوظيفي" value={editForms[employee.id].employeeNo} onChangeText={(value) => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], employeeNo: value } }))} />
                  <Text style={styles.employeeMeta}>التصنيف الوظيفي</Text>
                  <View style={styles.roleChoices}>{roleOptions.map(([code, label]) => <Pressable key={code} accessibilityRole="button" style={[styles.roleChoice, editForms[employee.id].roleCode === code && styles.roleChoiceActive]} onPress={() => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], roleCode: code } }))}><Text style={styles.roleChoiceText}>{label}</Text></Pressable>)}</View>
                  <Text style={styles.employeeMeta}>الفرع الحالي: {employee.branchName ?? 'غير محدد'}</Text>
                  <View style={styles.roleChoices}>{branches.map((branch) => <Pressable key={branch.id} accessibilityRole="button" style={[styles.roleChoice, editForms[employee.id].branchId === branch.id && styles.roleChoiceActive]} onPress={() => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], branchId: branch.id } }))}><Text style={styles.roleChoiceText}>{branch.name}</Text></Pressable>)}</View>
                  <Pressable accessibilityRole="button" style={styles.refresh} onPress={() => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], status: current[employee.id].status === 'active' ? 'suspended' : 'active' } }))}><Text style={styles.refreshText}>{editForms[employee.id].status === 'active' ? 'تجهيز لإيقاف الحساب مع حفظ السجلات' : 'تجهيز لإعادة تفعيل الحساب'}</Text></Pressable>
                  <Pressable accessibilityRole="button" disabled={busyEmployeeId !== null} style={styles.primaryButton} onPress={() => void updateEmployee(employee)}><Text style={styles.buttonText}>{busyEmployeeId === employee.id ? 'جارٍ الحفظ…' : 'حفظ بيانات الحساب'}</Text></Pressable>
                  <Pressable accessibilityRole="button" style={styles.refresh} onPress={() => void loadAudit(employee)}><Text style={styles.refreshText}>عرض سجل التعديلات</Text></Pressable>
                  {(audit[employee.id] ?? []).map((entry) => <Text style={styles.employeeMeta} key={entry.id}>{entry.action} · {new Date(entry.created_at).toLocaleString('ar-SA')}</Text>)}
                </>
              )}
              {active && employee.hasAuthAccount && (
                <>
                  <TextInput
                    style={styles.input}
                    placeholder={employee.codeSetAt ? 'أدخل رمزًا جديدًا للتغيير' : 'أنشئ رمز دخول لهذا الموظف'}
                    secureTextEntry
                    autoCapitalize="none"
                    autoCorrect={false}
                    autoComplete="off"
                    maxLength={64}
                    value={codes[employee.id] ?? ''}
                    onChangeText={(value) => setCodes((current) => ({ ...current, [employee.id]: value }))}
                    editable={!busy}
                    accessibilityLabel={`رمز دخول الموظف ${employee.fullName}`}
                  />
                  <Pressable
                    accessibilityRole="button"
                    accessibilityState={{ disabled: busy }}
                    style={({ pressed }) => [styles.primaryButton, pressed && !busy && styles.pressed]}
                    disabled={busy}
                    onPress={() => void saveCode(employee)}
                  >
                    {busy ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>{employee.codeSetAt ? 'تغيير الرمز' : 'تعيين الرمز'}</Text>}
                  </Pressable>
                  {employee.codeSetAt && (
                    <Pressable
                      accessibilityRole="button"
                      accessibilityState={{ disabled: busy }}
                      style={({ pressed }) => [styles.dangerButton, pressed && !busy && styles.pressed]}
                      disabled={busy}
                      onPress={() => confirmRevoke(employee)}
                    >
                      <Text style={styles.dangerText}>إلغاء الرمز</Text>
                    </Pressable>
                  )}
                </>
              )}
            </View>
          );
        }) : null}

        {!loading && isOwner && (
          <Pressable accessibilityRole="button" disabled={busyEmployeeId !== null} style={styles.refresh} onPress={() => void loadSettings()}>
            <Text style={styles.refreshText}>تحديث قائمة الموظفين</Text>
          </Pressable>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

export function ErrorBoundary({ error, retry }: ErrorBoundaryProps) {
  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.content}>
        <Text style={styles.title}>تعذر فتح إعدادات الموظفين</Text>
        <Text accessibilityRole="alert" style={styles.error}>
          أوقفنا هذا الجزء بأمان بدل إغلاق التطبيق. رمز الخطأ: {error?.name || 'غير معروف'}.
        </Text>
        <Pressable accessibilityRole="button" style={styles.refresh} onPress={() => { void retry(); }}>
          <Text style={styles.refreshText}>إعادة فتح الصفحة</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f4f7f8' },
  content: { padding: 18, paddingTop: 20, paddingBottom: 36 },
  back: { alignSelf: 'flex-end', paddingVertical: 8, paddingHorizontal: 4, marginBottom: 12 },
  backText: { color: '#39556a', fontSize: 15, fontWeight: '700' },
  eyebrow: { color: '#718394', fontSize: 13, fontWeight: '700', marginBottom: 6, textAlign: 'right' },
  title: { color: '#17324d', fontSize: 26, fontWeight: '800', textAlign: 'right', marginBottom: 10, lineHeight: 38 },
  copy: { color: '#718394', fontSize: 14, lineHeight: 22, textAlign: 'right', marginBottom: 12 },
  note: { color: '#73521f', backgroundColor: '#fff5df', borderColor: '#f0dfb8', borderWidth: 1, borderRadius: 12, padding: 12, textAlign: 'right', lineHeight: 21, marginBottom: 14 },
  error: { color: '#a8443d', textAlign: 'right', lineHeight: 22, marginBottom: 10 },
  success: { color: '#23633c', textAlign: 'right', lineHeight: 22, marginBottom: 10 },
  loading: { alignItems: 'center', paddingVertical: 28 },
  employeeCard: { backgroundColor: '#fff', borderRadius: 16, padding: 16, marginTop: 12, borderWidth: 1, borderColor: '#e2e9eb' },
  employeeName: { color: '#17324d', fontSize: 17, fontWeight: '800', textAlign: 'right', lineHeight: 25 },
  employeeMeta: { color: '#718394', fontSize: 13, textAlign: 'right', marginTop: 5, lineHeight: 20 },
  warning: { color: '#8b3a2e', textAlign: 'right', lineHeight: 21, marginTop: 10 },
  input: { minHeight: 48, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 11, paddingHorizontal: 12, marginTop: 14, marginBottom: 10, textAlign: 'right', fontSize: 16, backgroundColor: '#fbfcfc' },
  primaryButton: { minHeight: 46, backgroundColor: '#17324d', borderRadius: 11, padding: 12, alignItems: 'center', justifyContent: 'center' },
  buttonText: { color: '#fff', fontWeight: '800' },
  dangerButton: { minHeight: 42, borderWidth: 1, borderColor: '#b55248', borderRadius: 10, padding: 10, alignItems: 'center', justifyContent: 'center', marginTop: 9 },
  dangerText: { color: '#a8443d', fontWeight: '800' },
  refresh: { minHeight: 46, alignItems: 'center', justifyContent: 'center', marginTop: 18, borderWidth: 1, borderColor: '#17324d', borderRadius: 11 },
  refreshText: { color: '#17324d', fontWeight: '800' },
  roleChoices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 8, marginBottom: 10 },
  roleChoice: { borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingVertical: 9, paddingHorizontal: 10, backgroundColor: '#fbfcfc' },
  roleChoiceActive: { backgroundColor: '#dceee7', borderColor: '#2f6654' },
  roleChoiceText: { color: '#39556a', fontSize: 13, fontWeight: '700' },
  pressed: { opacity: 0.82 },
});
