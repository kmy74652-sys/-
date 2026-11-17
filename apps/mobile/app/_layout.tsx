import { Stack } from 'expo-router';
import { I18nManager } from 'react-native';

// The application is Arabic-first. Persist RTL at the native layout level so
// flex rows, navigation screens, and modal previews share one direction.
I18nManager.allowRTL(true);
I18nManager.forceRTL(true);

export default function Layout() { return <Stack screenOptions={{ headerShown: false }} />; }
