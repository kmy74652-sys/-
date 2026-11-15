import { useEffect, useState } from 'react';
import { useRouter } from 'expo-router';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { supabase } from '../lib/supabase';
import { friendlyDataError, getMyEmployeeProfile } from '../lib/mobileData';

type Profile = {
  fullName: string;
  employeeNo: string;
  roles: { code: string; nameAr: string }[];
  permissions: string[];
  branches: { name: string }[];
};

const modules = [
  ['المهام والمتابعة', 'tasks.read'],
  ['العملاء والحسابات', 'customers.read'],
  ['التقارير والرقابة', 'finance.read'],
] as const;

export default function Home() {
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [checkingSession, setCheckingSession] = useState(true);
  const [employeeNo, setEmployeeNo] = useState('');
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    void load();
  }, []);

  async function load() {
    try {
      if (!supabase) {
        setError('إعدادات Supabase غير متاحة.');
        setProfile(null);
        return;
      }
      setError('');
      const identity = await getMyEmployeeProfile();
      if (!identity) {
        setProfile(null);
        return;
      }
      if (!identity.employee) {
        setProfile(null);
        setError('تم تسجيل الدخول إلى Supabase، لكن الحساب غير مرتبط بملف موظف نشط. تواصل مع مسؤول النظام.');
        return;
      }
      setProfile(identity.employee);
      setError('');
    } catch (cause) {
      setProfile(null);
      setError(friendlyDataError(cause, 'تعذر الاتصال بـSupabase. تحقق من الإنترنت وحاول مرة أخرى.'));
    } finally {
      setCheckingSession(false);
    }
  }

  async function login() {
    if (!supabase) {
      setError('إعدادات Supabase غير متاحة.');
      return;
    }
    if (!employeeNo.trim() || !code) {
      setError('أدخل رقم الموظف ورمز الدخول.');
      return;
    }
    if (!/^\S{8,64}$/.test(code)) {
      setError('يجب أن يتكون رمز الدخول من 8 إلى 64 محرفًا دون مسافات.');
      return;
    }

    setBusy(true);
    setError('');
    try {
      const { data, error: functionError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'login', employeeNo: employeeNo.trim(), code },
      });
      if (functionError) {
        const status = (functionError as { context?: { status?: number } }).context?.status;
        if (status === 429) setError('محاولات كثيرة. انتظر 15 دقيقة ثم حاول مجددًا.');
        else if (status === 401) setError('رقم الموظف أو رمز الدخول غير صحيح، أو لم يعيّن المالك رمزًا لهذا الموظف.');
        else if (status === 404 || status === 503) setError('خدمة الدخول بالرمز أو تحديث قاعدة البيانات غير جاهز في Supabase بعد.');
        else setError('تعذر الاتصال بخدمة تسجيل الدخول. تحقق من الإنترنت وحاول مجددًا.');
        return;
      }
      if (typeof data?.access_token !== 'string' || typeof data?.refresh_token !== 'string') {
        setError('لم تُرجع خدمة الدخول جلسة صالحة. تحقق من إعداد Supabase.');
        return;
      }
      const { error: sessionError } = await supabase.auth.setSession({
        access_token: data.access_token,
        refresh_token: data.refresh_token,
      });
      if (sessionError) throw sessionError;
      setCode('');
      await load();
    } catch {
      setError('تعذر إكمال تسجيل الدخول بسبب انقطاع الاتصال. تحقق من الإنترنت وحاول مجددًا.');
    } finally {
      setBusy(false);
    }
  }

  async function retrySession() {
    setBusy(true);
    setError('');
    try {
      await load();
    } finally {
      setBusy(false);
    }
  }

  if (checkingSession) {
    return (
      <SafeAreaView style={[styles.safe, styles.bootScreen]}>
        <ActivityIndicator size="large" color="#17324d" />
        <Text style={styles.copy}>جارٍ التحقق من الجلسة…</Text>
      </SafeAreaView>
    );
  }

  if (!profile) {
    return (
      <SafeAreaView style={styles.safe}>
        <KeyboardAvoidingView
          style={styles.keyboardArea}
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        >
          <ScrollView
            contentContainerStyle={styles.authScroll}
            keyboardShouldPersistTaps="handled"
          >
            <View style={styles.auth}>
              <Text style={styles.mark}>ش</Text>
              <Text style={styles.eyebrow}>وصول آمن للموظفين</Text>
              <Text style={styles.title}>برنامج الشاعري</Text>
              <Text style={styles.copy}>أدخل رقم الموظف والرمز الشخصي الذي عيّنه صاحب المؤسسة. لا يلزم إدخال بريد إلكتروني.</Text>
              {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
              <TextInput
                style={styles.input}
                placeholder="رقم الموظف"
                autoCapitalize="none"
                autoCorrect={false}
                autoComplete="off"
                returnKeyType="next"
                value={employeeNo}
                onChangeText={setEmployeeNo}
                editable={!busy}
                accessibilityLabel="رقم الموظف"
              />
              <TextInput
                style={styles.input}
                placeholder="رمز الدخول الشخصي"
                secureTextEntry
                autoCapitalize="none"
                autoCorrect={false}
                autoComplete="off"
                returnKeyType="done"
                value={code}
                onChangeText={setCode}
                onSubmitEditing={() => void login()}
                editable={!busy}
                accessibilityLabel="رمز الدخول الشخصي"
              />
              <Pressable
                accessibilityRole="button"
                accessibilityState={{ disabled: busy }}
                style={({ pressed }) => [styles.button, pressed && !busy && styles.pressed]}
                onPress={() => void login()}
                disabled={busy}
              >
                {busy ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>دخول آمن</Text>}
              </Pressable>
              {!!error && <Pressable accessibilityRole="button" disabled={busy} style={styles.resetButton} onPress={() => void retrySession()}>
                <Text style={styles.resetText}>إعادة الاتصال بـSupabase</Text>
              </Pressable>}
              <Text style={styles.helpText}>نسيت الرمز أو لم يُعيّن لك بعد؟ تواصل مع صاحب المؤسسة.</Text>
            </View>
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    );
  }

  const allowed = new Set(profile.permissions);
  const isOwner = profile.roles.some((role) => role.code === 'owner') && allowed.has('employees.manage');
  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.eyebrow}>
          {profile.employeeNo} · {profile.roles.map((role) => role.nameAr).join('، ')}
        </Text>
        <Text style={styles.title}>مرحبًا، {profile.fullName}</Text>
        <Text style={styles.copy}>الوحدات الظاهرة مرتبطة بصلاحيات حسابك.</Text>
        <View style={styles.grid}>
          {modules.filter(([, permission]) => allowed.has(permission)).map(([name]) => (
            <View style={styles.card} key={name}>
              <Text style={styles.cardTitle}>{name}</Text>
              <Text style={styles.cardCopy}>{profile.branches.map((branch) => branch.name).join('، ')}</Text>
            </View>
          ))}
        </View>
        {allowed.has('tasks.read') && (
          <Pressable accessibilityRole="button" style={styles.taskLink} onPress={() => router.push('/tasks')}>
            <Text style={styles.taskLinkText}>فتح المهام والتقارير والتنبيهات</Text>
          </Pressable>
        )}
        {isOwner && (
          <Pressable accessibilityRole="button" style={styles.settingsLink} onPress={() => router.push('/settings')}>
            <Text style={styles.settingsLinkText}>إعدادات الموظفين ورموز الدخول</Text>
          </Pressable>
        )}
        <Pressable
          accessibilityRole="button"
          style={({ pressed }) => [styles.outline, pressed && styles.pressed]}
          onPress={() => void (async () => {
            try {
              const { error: signOutError } = await supabase?.auth.signOut() ?? {};
              if (signOutError) throw signOutError;
              setProfile(null);
              setError('');
            } catch {
              setError('تعذر تسجيل الخروج بأمان. تحقق من الاتصال ثم أعد المحاولة.');
            }
          })()}
        >
          <Text style={styles.outlineText}>تسجيل الخروج</Text>
        </Pressable>
        {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f4f7f8' },
  bootScreen: { alignItems: 'center', justifyContent: 'center', padding: 24 },
  keyboardArea: { flex: 1 },
  authScroll: { flexGrow: 1, justifyContent: 'center', padding: 16, paddingBottom: 28 },
  auth: {
    width: '100%',
    maxWidth: 480,
    alignSelf: 'center',
    padding: 22,
    backgroundColor: '#fff',
    borderRadius: 22,
    borderWidth: 1,
    borderColor: '#e2e9eb',
  },
  content: { padding: 18, paddingTop: 28, paddingBottom: 32 },
  mark: { color: '#17324d', fontSize: 42, fontWeight: '800', textAlign: 'right' },
  eyebrow: { color: '#718394', fontSize: 13, fontWeight: '700', marginBottom: 8, textAlign: 'right', lineHeight: 20 },
  title: { color: '#17324d', fontSize: 28, fontWeight: '800', textAlign: 'right', marginBottom: 12, lineHeight: 40 },
  copy: { color: '#718394', fontSize: 15, lineHeight: 24, textAlign: 'right', marginBottom: 18 },
  input: {
    minHeight: 50,
    borderWidth: 1,
    borderColor: '#d6e0e4',
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    marginBottom: 12,
    textAlign: 'right',
    fontSize: 16,
    backgroundColor: '#fbfcfc',
  },
  error: { color: '#a8443d', minHeight: 22, textAlign: 'right', lineHeight: 22, marginBottom: 4 },
  helpText: { color: '#718394', fontSize: 13, textAlign: 'right', lineHeight: 20, marginTop: 14 },
  button: { minHeight: 50, backgroundColor: '#17324d', borderRadius: 12, padding: 14, alignItems: 'center', justifyContent: 'center' },
  buttonText: { color: '#fff', fontWeight: '800', fontSize: 16 },
  resetButton: { minHeight: 44, alignItems: 'center', justifyContent: 'center', marginTop: 6 },
  resetText: { color: '#39556a', fontWeight: '700', textDecorationLine: 'underline' },
  pressed: { opacity: 0.82 },
  grid: { gap: 12 },
  taskLink: { minHeight: 52, marginTop: 16, borderRadius: 12, padding: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: '#17324d' },
  taskLinkText: { color: '#fff', fontWeight: '800', fontSize: 16 },
  settingsLink: { minHeight: 52, marginTop: 12, borderRadius: 12, padding: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: '#2f6654' },
  settingsLinkText: { color: '#fff', fontWeight: '800', fontSize: 16 },
  card: { backgroundColor: '#fff', borderRadius: 16, padding: 18, borderWidth: 1, borderColor: '#e2e9eb' },
  cardTitle: { color: '#17324d', fontSize: 17, fontWeight: '800', textAlign: 'right', lineHeight: 26 },
  cardCopy: { color: '#718394', marginTop: 8, textAlign: 'right', lineHeight: 22 },
  outline: { minHeight: 48, marginTop: 24, borderWidth: 1, borderColor: '#17324d', borderRadius: 12, padding: 12, alignItems: 'center', justifyContent: 'center' },
  outlineText: { color: '#17324d', fontWeight: '800' },
});
