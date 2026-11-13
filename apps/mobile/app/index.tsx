import { useEffect, useState } from 'react';
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
import { flushQueue } from '../lib/syncQueue';

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
  const [profile, setProfile] = useState<Profile | null>(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    void load();
  }, []);

  async function load() {
    if (!supabase) return;
    const { data } = await supabase.auth.getSession();
    if (!data.session) return;
    const baseUrl = process.env.EXPO_PUBLIC_API_BASE_URL ?? '';
    if (baseUrl) await flushQueue(data.session.access_token, baseUrl);
    const response = await fetch(`${baseUrl}/api/me`, {
      headers: { Authorization: `Bearer ${data.session.access_token}` },
    });
    if (response.ok) setProfile((await response.json()).employee as Profile);
  }

  async function login() {
    if (!supabase) {
      setError('إعدادات Supabase غير متاحة.');
      return;
    }
    setBusy(true);
    setError('');
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    if (signInError) {
      setError('تعذر تسجيل الدخول.');
    } else {
      await load();
    }
    setBusy(false);
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
              {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
              <Pressable
                accessibilityRole="button"
                accessibilityState={{ disabled: busy }}
                style={({ pressed }) => [styles.button, pressed && !busy && styles.pressed]}
                onPress={() => void login()}
                disabled={busy}
              >
                {busy ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>دخول آمن</Text>}
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
        <Pressable
          accessibilityRole="button"
          style={({ pressed }) => [styles.outline, pressed && styles.pressed]}
          onPress={() => {
            void supabase?.auth.signOut();
            setProfile(null);
          }}
        >
          <Text style={styles.outlineText}>تسجيل الخروج</Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f4f7f8' },
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
  button: { minHeight: 50, backgroundColor: '#17324d', borderRadius: 12, padding: 14, alignItems: 'center', justifyContent: 'center' },
  buttonText: { color: '#fff', fontWeight: '800', fontSize: 16 },
  pressed: { opacity: 0.82 },
  grid: { gap: 12 },
  card: { backgroundColor: '#fff', borderRadius: 16, padding: 18, borderWidth: 1, borderColor: '#e2e9eb' },
  cardTitle: { color: '#17324d', fontSize: 17, fontWeight: '800', textAlign: 'right', lineHeight: 26 },
  cardCopy: { color: '#718394', marginTop: 8, textAlign: 'right', lineHeight: 22 },
  outline: { minHeight: 48, marginTop: 24, borderWidth: 1, borderColor: '#17324d', borderRadius: 12, padding: 12, alignItems: 'center', justifyContent: 'center' },
  outlineText: { color: '#17324d', fontWeight: '800' },
});
