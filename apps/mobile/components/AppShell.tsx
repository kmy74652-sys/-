import { ReactNode } from 'react';
import { Image, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import HomeIcon, { type HomeIconName } from './HomeIcon';
import { supabase } from '../lib/supabase';

const NAVY = '#0b3458';
const GOLD = '#e5b336';
export type ShellTab = 'home' | 'tasks' | 'employees' | 'settings';

type Props = {
  children: ReactNode;
  activeTab: ShellTab;
  title: string;
  subtitle?: string;
  profileName?: string;
  scroll?: boolean;
  refreshing?: boolean;
  onRefresh?: () => void;
};

export default function AppShell({ children, activeTab, title, subtitle, profileName, scroll = true, refreshing = false, onRefresh }: Props) {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const compact = width < 370;
  const content = <View style={[styles.content, compact && styles.compactContent]}>{children}</View>;
  const navigate = (tab: ShellTab) => {
    if (tab === 'home') router.replace('/');
    else if (tab === 'tasks') router.push('/tasks');
    else if (tab === 'employees') router.push('/settings?tab=employees');
    else router.push('/settings');
  };
  return <SafeAreaView edges={['top', 'left', 'right']} style={styles.safe}>
    <View style={styles.frame}>
      {scroll ? <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={onRefresh ? <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={NAVY} colors={[NAVY]} /> : undefined}>{content}</ScrollView> : content}
      <View style={[styles.bottomBar, { paddingBottom: Math.max(insets.bottom, 8) }]}>
        {([{ key: 'home', title: 'الرئيسية', icon: 'home' }, { key: 'tasks', title: 'المهام', icon: 'tasks' }, { key: 'employees', title: 'الموظفون', icon: 'employees' }, { key: 'settings', title: 'الإعدادات', icon: 'settings' }] as const).map((item) => <Pressable key={item.key} accessibilityRole="tab" accessibilityState={{ selected: activeTab === item.key }} style={[styles.bottomItem, activeTab === item.key && styles.bottomItemActive]} onPress={() => navigate(item.key)}><HomeIcon name={item.icon as HomeIconName} size={28} color={activeTab === item.key ? NAVY : '#fff'} /><Text style={[styles.bottomLabel, activeTab === item.key && styles.bottomLabelActive]}>{item.title}</Text></Pressable>)}
      </View>
    </View>
  </SafeAreaView>;
}

export function ScreenHeader({ title, subtitle, profileName, onBack }: { title: string; subtitle?: string; profileName?: string; onBack?: () => void }) {
  const router = useRouter();
  async function switchAccount() {
    if (supabase) await supabase.auth.signOut();
    router.replace('/');
  }
  return <View style={styles.header}>
    <View style={styles.headerIdentity}><Image source={require('../assets/alshaeri-official-logo.png')} style={styles.logo} resizeMode="contain" /><View style={styles.headerCopy}><Text style={styles.brand}>برنامج الشاعري</Text><Text style={styles.org}>مؤسسة الشاعري للتجارة العامة</Text><Text style={styles.title}>{title}</Text>{!!subtitle && <Text style={styles.subtitle}>{subtitle}</Text>}{!!profileName && <Text style={styles.profile}>مرحباً، {profileName}</Text>}</View></View>
    <View style={styles.headerActions}>{onBack && <Pressable accessibilityRole="button" style={styles.back} onPress={onBack}><Text style={styles.backText}>رجوع</Text></Pressable>}<Pressable accessibilityRole="button" accessibilityLabel="تسجيل الخروج وتبديل الحساب" style={styles.switchAccount} onPress={() => void switchAccount()}><Text style={styles.switchAccountText}>تبديل الحساب</Text></Pressable></View>
  </View>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f5f7fd', direction: 'rtl' }, frame: { flex: 1, maxWidth: 840, width: '100%', alignSelf: 'center', direction: 'rtl' }, scroll: { flex: 1 }, scrollContent: { paddingBottom: 18 }, content: { padding: 12, gap: 12, direction: 'rtl' }, compactContent: { paddingHorizontal: 8 }, header: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8, paddingHorizontal: 4, paddingTop: 4, paddingBottom: 5, direction: 'rtl' }, headerIdentity: { flex: 1, flexDirection: 'row-reverse', alignItems: 'center', gap: 8 }, logo: { width: 61, height: 61 }, headerCopy: { flex: 1, alignItems: 'flex-end', gap: 1 }, brand: { color: NAVY, fontSize: 22, fontWeight: '900', textAlign: 'right', writingDirection: 'rtl' }, org: { color: NAVY, fontSize: 12, fontWeight: '700', textAlign: 'right', writingDirection: 'rtl' }, title: { color: NAVY, fontSize: 19, fontWeight: '900', textAlign: 'right', writingDirection: 'rtl' }, subtitle: { color: '#637188', fontSize: 12, textAlign: 'right', writingDirection: 'rtl' }, profile: { color: '#a6761f', fontSize: 12, fontWeight: '800', textAlign: 'right', writingDirection: 'rtl' }, headerActions: { alignItems: 'flex-end', gap: 5 }, back: { minHeight: 34, minWidth: 55, borderRadius: 11, backgroundColor: '#e6edf6', alignItems: 'center', justifyContent: 'center' }, backText: { color: NAVY, fontWeight: '800', fontSize: 12 }, switchAccount: { minHeight: 34, borderRadius: 11, borderWidth: 1, borderColor: '#b65050', backgroundColor: '#fff', paddingHorizontal: 9, alignItems: 'center', justifyContent: 'center' }, switchAccountText: { color: '#9f3e3e', fontWeight: '800', fontSize: 11 }, bottomBar: { flexDirection: 'row-reverse', backgroundColor: NAVY, borderTopWidth: 3, borderTopColor: GOLD, paddingTop: 7, paddingHorizontal: 6, gap: 4, direction: 'rtl' }, bottomItem: { flex: 1, minHeight: 65, paddingVertical: 7, alignItems: 'center', justifyContent: 'center', gap: 4, borderRadius: 17 }, bottomItemActive: { backgroundColor: GOLD }, bottomLabel: { color: '#fff', fontSize: 13, fontWeight: '700', writingDirection: 'rtl' }, bottomLabelActive: { color: NAVY, fontWeight: '900' },
});
