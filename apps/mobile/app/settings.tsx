import { useEffect, useState } from 'react';
import { useRouter } from 'expo-router';
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
  employeeNo: string;
  fullName: string;
  status: string;
  hasAuthAccount: boolean;
  codeSetAt: string | null;
};

type EmployeeListResult = { employees?: EmployeeAccess[] };

function functionStatus(error: unknown) {
  return (error as { context?: { status?: number } } | null)?.context?.status;
}

function functionErrorText(error: unknown) {
  const status = functionStatus(error);
  if (status === 401) return 'انتهت الجلسة. سجّل الدخول مجددًا.';
  if (status === 403) return 'هذه الإعدادات متاحة لصاحب المؤسسة فقط.';
  if (status === 404 || status === 503) return 'خدمة الرموز أو migration 019 غير منشورين على Supabase بعد.';
  if (status === 429) return 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.';
  return 'تعذر إكمال الطلب. تحقق من الاتصال وحاول مجددًا.';
}

export default function EmployeeAccessSettings() {
  const router = useRouter();
  const [employees, setEmployees] = useState<EmployeeAccess[]>([]);
  const [codes, setCodes] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busyEmployeeId, setBusyEmployeeId] = useState<string | null>(null);
  const [isOwner, setIsOwner] = useState(false);
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
        setError('يجب تسجيل الدخول بحساب صاحب المؤسسة لفتح هذه الإعدادات.');
        return;
      }
      const owner = identity.employee.roles.some((role) => role.code === 'owner')
        && identity.employee.permissions.includes('employees.manage');
      setIsOwner(owner);
      if (!owner) {
        setError('هذه الإعدادات متاحة لصاحب المؤسسة فقط.');
        return;
      }
      const { data, error: listError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'list' },
      });
      if (listError) {
        setError(functionErrorText(listError));
        return;
      }
      setEmployees((data as EmployeeListResult | null)?.employees ?? []);
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر تحميل قائمة الموظفين. تحقق من الاتصال ثم أعد المحاولة.'));
    } finally {
      setLoading(false);
    }
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
      if (!refreshError) setEmployees((data as EmployeeListResult | null)?.employees ?? []);
    } catch {
      setError('تعذر حفظ الرمز. تحقق من الاتصال ثم حاول مجددًا.');
    } finally {
      setBusyEmployeeId(null);
    }
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
      if (!refreshError) setEmployees((data as EmployeeListResult | null)?.employees ?? []);
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

        {loading ? (
          <View style={styles.loading}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.copy}>جارٍ تحميل الموظفين…</Text></View>
        ) : isOwner && employees.length === 0 ? (
          <Text style={styles.copy}>لا توجد ملفات موظفين مرتبطة بهذه المؤسسة.</Text>
        ) : isOwner ? employees.map((employee) => {
          const active = employee.status === 'active';
          const busy = busyEmployeeId === employee.id;
          return (
            <View style={styles.employeeCard} key={employee.id}>
              <Text style={styles.employeeName}>{employee.fullName}</Text>
              <Text style={styles.employeeMeta}>رقم الموظف: {employee.employeeNo}</Text>
              <Text style={styles.employeeMeta}>
                {employee.codeSetAt ? 'تم تعيين رمز دخول' : 'لم يُعيّن رمز دخول بعد'}
                {!active ? ' · الحساب غير نشط' : ''}
              </Text>
              {!employee.hasAuthAccount && (
                <Text style={styles.warning}>لا يوجد حساب مصادقة مرتبط بملف هذا الموظف؛ لا يمكن تعيين رمز له حتى يربطه مسؤول النظام.</Text>
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
  pressed: { opacity: 0.82 },
});
