import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Image,
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
import type { MobileProfile } from '../lib/mobileData';
import HomeDashboard from '../components/HomeDashboard';

type Profile = MobileProfile;

export default function Home() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [checkingSession, setCheckingSession] = useState(true);
  const [employeeNo, setEmployeeNo] = useState('');
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const clearHomeProfile = useCallback(() => { setProfile(null); setCode(''); setError(''); }, []);

  useEffect(() => {
    void load();
    const subscription = supabase?.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') { setProfile(null); setCode(''); setError(''); }
    });
    return () => subscription?.data.subscription.unsubscribe();
  }, []);

  async function load(options: { showConnectionError?: boolean } = {}) {
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
      const permissions = new Set(identity.employee.permissions);
      if (!permissions.has('tasks.manage') && !permissions.has('tasks.execute')) {
        setError('حسابك نشط، لكن لم تُربط به صلاحية تشغيلية بعد. اطلب من صاحب المؤسسة مراجعة دورك وصلاحياتك.');
      }
    } catch (cause) {
      setProfile(null);
      // Restoring a persisted session is best-effort. A transient network/auth
      // lookup failure must not block the login screen before credentials are entered.
      // After an explicit login or manual retry, show the actionable connection error.
      setError(options.showConnectionError
        ? friendlyDataError(cause, 'تعذر الاتصال بـSupabase. تحقق من الإنترنت وحاول مرة أخرى.')
        : '');
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
      setError('أدخل اسم الموظف ورمز الدخول.');
      return;
    }
    if (!/^\S{8,64}$/.test(code)) {
      setError('يجب أن تتكون كلمة المرور من 8 إلى 64 محرفًا دون مسافات.');
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
        else if (status === 401) setError('اسم الموظف أو رمز الدخول غير صحيح.');
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
      await load({ showConnectionError: true });
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
      await load({ showConnectionError: true });
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
              <Image source={require('../assets/alshaeri-official-logo.png')} style={styles.loginLogo} resizeMode="contain" accessibilityLabel="شعار الشاعري للتجارة العامة" />
              <Text style={styles.eyebrow}>بوابة العمل والتواصل الإداري</Text>
              <Text style={styles.title}>مانجمنت</Text>
              <Text style={styles.copy}>سجّل دخولك للوصول إلى مهامك، تقاريرك، وتنبيهات العمل في مكان واحد.</Text>
              {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
              <TextInput
                style={styles.input}
                placeholder="اسم الموظف"
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
                placeholder="كلمة المرور"
                secureTextEntry
                autoCapitalize="none"
                autoCorrect={false}
                autoComplete="off"
                returnKeyType="done"
                value={code}
                onChangeText={setCode}
                onSubmitEditing={() => void login()}
                editable={!busy}
                accessibilityLabel="كلمة المرور"
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
              <Text style={styles.helpText}>نسيت الرمز أو لم يُعيّن لك بعد؟ تواصل مع الإدارة.</Text>
            </View>
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    );
  }

  return <HomeDashboard profile={profile} onSignOut={clearHomeProfile} />;
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
    direction: 'rtl',
  },
  loginLogo: { width: 150, height: 105, alignSelf: 'center', marginBottom: 4 },
  eyebrow: { alignSelf: 'stretch', color: '#718394', fontSize: 13, fontWeight: '700', marginBottom: 8, textAlign: 'right', writingDirection: 'rtl', lineHeight: 20 },
  title: { alignSelf: 'stretch', color: '#17324d', fontSize: 28, fontWeight: '800', textAlign: 'right', writingDirection: 'rtl', marginBottom: 12, lineHeight: 40 },
  copy: { alignSelf: 'stretch', color: '#718394', fontSize: 15, lineHeight: 24, textAlign: 'right', writingDirection: 'rtl', marginBottom: 18 },
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
    writingDirection: 'rtl',
  },
  error: { alignSelf: 'stretch', color: '#a8443d', minHeight: 22, textAlign: 'right', writingDirection: 'rtl', lineHeight: 22, marginBottom: 4 },
  helpText: { alignSelf: 'stretch', color: '#718394', fontSize: 13, textAlign: 'right', writingDirection: 'rtl', lineHeight: 20, marginTop: 14 },
  button: { minHeight: 50, backgroundColor: '#0D2C54', borderRadius: 12, padding: 14, alignItems: 'center', justifyContent: 'center', borderBottomWidth: 3, borderBottomColor: '#E5A93C' },
  buttonText: { alignSelf: 'auto', color: '#fff', fontWeight: '800', fontSize: 16, textAlign: 'center', writingDirection: 'rtl' },
  resetButton: { minHeight: 44, alignItems: 'center', justifyContent: 'center', marginTop: 6 },
  resetText: { alignSelf: 'auto', color: '#39556a', fontWeight: '700', textAlign: 'center', writingDirection: 'rtl', textDecorationLine: 'underline' },
  pressed: { opacity: 0.82 },
});
