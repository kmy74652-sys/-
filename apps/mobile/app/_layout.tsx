import { Stack, useRouter } from 'expo-router';
import { useFonts } from 'expo-font';
import { useEffect } from 'react';
import { I18nManager, StatusBar, Text, TextInput, View } from 'react-native';
import * as Notifications from 'expo-notifications';
import { supabase } from '../lib/supabase';
import { registerForPushNotifications, resetPushRegistration } from '../lib/pushNotifications';

// The application is Arabic-first. Persist RTL at the native layout level so
// flex rows, navigation screens, and modal previews share one direction.
I18nManager.allowRTL(true);
if (!I18nManager.isRTL) I18nManager.forceRTL(true);

export default function Layout() {
  const router = useRouter();
  const [fontsLoaded] = useFonts({ AlshaeriArabic: require('../assets/fonts/AlshaeriArabic-Regular.ttf') });

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    const registerCurrentUser = async () => {
      const { data } = await client.auth.getSession();
      if (active && data.session?.user) {
        try { await registerForPushNotifications(data.session.user.id); } catch { /* Push is optional; in-app notifications remain available. */ }
      }
    };
    void registerCurrentUser();
    const { data: listener } = client.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_OUT') { resetPushRegistration(); return; }
      if (session?.user) void registerForPushNotifications(session.user.id).catch(() => undefined);
    });
    const responseSubscription = Notifications.addNotificationResponseReceivedListener(() => {
      // Tasks and their linked reports are intentionally one employee workspace.
      router.push('/tasks' as never);
    });
    return () => { active = false; listener.subscription.unsubscribe(); responseSubscription.remove(); };
  }, [router]);

  if (!fontsLoaded) return <View style={{ flex: 1, backgroundColor: '#f5f7fd' }} />;
  const TextDefaults = Text as typeof Text & { defaultProps?: { style?: unknown } };
  const TextInputDefaults = TextInput as typeof TextInput & { defaultProps?: { style?: unknown } };
  TextDefaults.defaultProps = { ...TextDefaults.defaultProps, style: [{ fontFamily: 'AlshaeriArabic' }, TextDefaults.defaultProps?.style] };
  TextInputDefaults.defaultProps = { ...TextInputDefaults.defaultProps, style: [{ fontFamily: 'AlshaeriArabic', writingDirection: 'rtl' }, TextInputDefaults.defaultProps?.style] };
  return <View style={{ flex: 1, direction: 'rtl', backgroundColor: '#f5f7fd' }}><StatusBar barStyle="dark-content" backgroundColor="#f5f7fd" /><Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#f5f7fd' } }} /></View>;
}
