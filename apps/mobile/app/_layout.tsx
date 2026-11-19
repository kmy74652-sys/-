import { Stack } from 'expo-router';
import { useFonts } from 'expo-font';
import { I18nManager, StatusBar, Text, TextInput, View } from 'react-native';

// The application is Arabic-first. Persist RTL at the native layout level so
// flex rows, navigation screens, and modal previews share one direction.
I18nManager.allowRTL(true);
// forceRTL is required on the first launch as well; native layout direction is
// persisted by React Native and becomes effective before the next render/reload.
if (!I18nManager.isRTL) I18nManager.forceRTL(true);

export default function Layout() {
  const [fontsLoaded] = useFonts({ AlshaeriArabic: require('../assets/fonts/AlshaeriArabic-Regular.ttf') });
  if (!fontsLoaded) return <View style={{ flex: 1, backgroundColor: '#f5f7fd' }} />;
  const TextDefaults = Text as typeof Text & { defaultProps?: { style?: unknown } };
  const TextInputDefaults = TextInput as typeof TextInput & { defaultProps?: { style?: unknown } };
  TextDefaults.defaultProps = { ...TextDefaults.defaultProps, style: [{ fontFamily: 'AlshaeriArabic' }, TextDefaults.defaultProps?.style] };
  TextInputDefaults.defaultProps = { ...TextInputDefaults.defaultProps, style: [{ fontFamily: 'AlshaeriArabic', writingDirection: 'rtl' }, TextInputDefaults.defaultProps?.style] };
  return <View style={{ flex: 1, direction: 'rtl', backgroundColor: '#f5f7fd' }}><StatusBar barStyle="dark-content" backgroundColor="#f5f7fd" /><Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#f5f7fd' } }} /></View>;
}
