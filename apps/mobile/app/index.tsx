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
  roles: { nameAr: string }[];
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
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
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
    setBusy(true);
    setError('');
    try {
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (signInError) {
        setError(signInError.status === 429
          ? 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.'
          : [400, 401, 422].includes(signInError.status ?? 0)
            ? 'لم يقبل Supabase البريد أو كلمة المرور. تحقق منهما أو استخدم رابط استعادة كلمة المرور.'
            : `تعذر الاتصال بخدمة تسجيل الدخول${signInError.status ? ` (HTTP ${signInError.status})` : ''}. تحقق من الإنترنت وحاول مجددًا.`);
        return;
      }
      await load();
    } catch {
      setError('تعذر إكمال تسجيل الدخول بسبب انقطاع الاتصال. تحقق من الإنترنت وحاول مجددًا.');
    } finally {
      setBusy(false);
    }
  }

  async function resetPassword() {
    if (!supabase) { setError('إعدادات Supabase غير متاحة.'); return; }
    if (!email.trim()) { setError('اكتب بريدك الإلكتروني أولًا لإرسال رابط الاستعادة.'); return; }
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.trim());
      if (resetError) throw resetError;
      setNotice('إذا كان البريد مسجلًا، سيصلك رابط استعادة كلمة المرور.');
    } catch {
      setError('تعذر إرسال رابط الاستعادة. تحقق من البريد والاتصال ثم حاول مجددًا.');
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
              <Text style={styles.copy}>استخدم الحساب المرتبط بملف موظف نشط.</Text>
              {!!notice && <Text accessibilityLiveRegion="polite" style={styles.success}>{notice}</Text>}
              {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
              <TextInput
                style={styles.input}
                placeholder="البريد الإلكتروني"
                autoCapitalize="none"
                autoComplete="email"
                keyboardType="email-address"
                returnKeyType="next"
                value={email}
                onChangeText={setEmail}
              />
              <TextInput
                style={styles.input}
                placeholder="كلمة المرور"
                secureTextEntry
                autoComplete="current-password"
                returnKeyType="done"
                value={password}
                onChangeText={setPassword}
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
              <Pressable accessibilityRole="button" disabled={busy} style={styles.resetButton} onPress={() => void resetPassword()}>
                <Text style={styles.resetText}>نسيت كلمة المرور؟ أرسل رابط استعادة</Text>
              </Pressable>
            </View>
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    );
  }

  const allowed = new Set(profile.permissions);
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
  success: { color: '#23633c', minHeight: 22, textAlign: 'right', lineHeight: 22, marginBottom: 8 },
  button: { minHeight: 50, backgroundColor: '#17324d', borderRadius: 12, padding: 14, alignItems: 'center', justifyContent: 'center' },
  buttonText: { color: '#fff', fontWeight: '800', fontSize: 16 },
  resetButton: { minHeight: 44, alignItems: 'center', justifyContent: 'center', marginTop: 6 },
  resetText: { color: '#39556a', fontWeight: '700', textDecorationLine: 'underline' },
  pressed: { opacity: 0.82 },
  grid: { gap: 12 },
  taskLink: { minHeight: 52, marginTop: 16, borderRadius: 12, padding: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: '#17324d' },
  taskLinkText: { color: '#fff', fontWeight: '800', fontSize: 16 },
  card: { backgroundColor: '#fff', borderRadius: 16, padding: 18, borderWidth: 1, borderColor: '#e2e9eb' },
  cardTitle: { color: '#17324d', fontSize: 17, fontWeight: '800', textAlign: 'right', lineHeight: 26 },
  cardCopy: { color: '#718394', marginTop: 8, textAlign: 'right', lineHeight: 22 },
  outline: { minHeight: 48, marginTop: 24, borderWidth: 1, borderColor: '#17324d', borderRadius: 12, padding: 12, alignItems: 'center', justifyContent: 'center' },
  outlineText: { color: '#17324d', fontWeight: '800' },
});
