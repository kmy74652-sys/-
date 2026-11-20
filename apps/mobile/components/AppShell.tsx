import { ReactNode } from 'react';
import { Image, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { useRouter } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import HomeIcon from './HomeIcon';
import { supabase } from '../lib/supabase';
const NAVY = '#0b3458';
const GOLD = '#dba62a';
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
export default function AppShell({ children, title, subtitle, profileName, scroll = true, refreshing = false, onRefresh }: Props) {
  const { width } = useWindowDimensions();
  const compact = width < 370;
  const router = useRouter();
  const signOut = async () => { try { await supabase?.auth.signOut(); } finally { router.replace('/'); } };
  const content = <View style={[styles.content, compact && styles.compactContent]}>{children}</View>;
  return <SafeAreaView edges={['top', 'left', 'right']} style={styles.safe}>
    <View style={styles.frame}>
      <SharedBrandHeader title={title} subtitle={subtitle} profileName={profileName} compact={compact} onSwitchAccount={() => void signOut()} onNotifications={() => router.push('/tasks')} />
      {scroll ? <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={onRefresh ? <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={NAVY} colors={[NAVY]} /> : undefined}>{content}</ScrollView> : content}
    </View>
  </SafeAreaView>;
}
export function SharedBrandHeader({ title, subtitle, profileName, organizationName = 'مؤسسة الشاعري للتجارة العامة', tagline = 'معاً .. نحو إدارة أفضل', unread, compact = false, onSwitchAccount, onNotifications }: { title?: string; subtitle?: string; profileName?: string; organizationName?: string; tagline?: string; unread?: number | null; compact?: boolean; onSwitchAccount?: () => void; onNotifications?: () => void }) {
  return <View style={[styles.header, compact && styles.compactHeader]}>
    <View style={styles.headerIdentity}>
      <Image source={require('../assets/alshaeri-official-logo.png')} style={[styles.logo, compact && styles.compactLogo]} resizeMode="contain" accessibilityLabel="الشعار الرسمي لمؤسسة الشاعري" />
      <View style={styles.headerCopy}>
        <Text style={[styles.brand, compact && styles.compactBrand]}>مانجمنت</Text>
        <Text style={styles.org}>{organizationName}</Text>
        <View style={styles.mottoRow}><View style={styles.mottoLine} /><Text style={styles.motto}>{tagline}</Text><View style={styles.mottoLine} /></View>
        {!!title && <Text style={styles.title}>{title}</Text>}
        {!!subtitle && <Text style={styles.subtitle}>{subtitle}</Text>}
        {!!profileName && <Text style={styles.profile}>مرحباً، {profileName}</Text>}
      </View>
    </View>
    <View style={styles.headerActions}>
      <Pressable accessibilityRole="button" accessibilityLabel="تبديل الحساب" accessibilityHint="تسجيل الخروج وفتح حساب آخر" style={({ pressed }) => [styles.accountButton, pressed && styles.pressed]} onPress={onSwitchAccount}><HomeIcon name="avatar" size={23} color={NAVY} /></Pressable>
      <Pressable accessibilityRole="button" accessibilityLabel={`التنبيهات${unread !== undefined && unread !== null ? `، ${unread} غير مقروءة` : ''}`} style={({ pressed }) => [styles.notificationButton, pressed && styles.pressed]} onPress={onNotifications}><HomeIcon name="bell" size={25} color="#fff" />{unread !== undefined && unread !== null && unread > 0 && <View style={styles.badge}><Text style={styles.badgeText}>{unread > 99 ? '99+' : unread}</Text></View>}</Pressable>
    </View>
  </View>;
}
/** @deprecated Use SharedBrandHeader through AppShell. Kept for compatibility with older feature modules. */
export function ScreenHeader(props: { title: string; subtitle?: string; profileName?: string }) { return <SharedBrandHeader {...props} />; }
const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f5f7fd', direction: 'rtl' },
  frame: { flex: 1, maxWidth: 840, width: '100%', alignSelf: 'center', direction: 'rtl' },
  scroll: { flex: 1 },
  scrollContent: { paddingBottom: 18 },
  content: { padding: 12, gap: 12, direction: 'rtl' },
  compactContent: { paddingHorizontal: 8 },
  header: { minHeight: 104, flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8, paddingHorizontal: 10, paddingTop: 3, paddingBottom: 7, backgroundColor: '#fff', borderBottomWidth: 1, borderBottomColor: '#e4eaf0', direction: 'rtl' },
  compactHeader: { minHeight: 96, paddingHorizontal: 7 },
  headerIdentity: { flex: 1, minWidth: 0, flexDirection: 'row-reverse', alignItems: 'center', gap: 8 },
  logo: { width: 74, height: 86, flexShrink: 0 },
  compactLogo: { width: 63, height: 73 },
  headerCopy: { flex: 1, minWidth: 0, alignItems: 'flex-end', gap: 1 },
  brand: { color: NAVY, fontSize: 20, fontWeight: '900', textAlign: 'right', writingDirection: 'rtl' },
  compactBrand: { fontSize: 17 },
  org: { color: NAVY, fontSize: 11, fontWeight: '700', textAlign: 'right', writingDirection: 'rtl' },
  mottoRow: { flexDirection: 'row-reverse', alignItems: 'center', gap: 4, maxWidth: '100%' },
  mottoLine: { height: 1, width: 13, backgroundColor: GOLD },
  motto: { color: '#9a6814', fontSize: 9, fontWeight: '800', textAlign: 'right' },
  title: { color: NAVY, fontSize: 16, fontWeight: '900', textAlign: 'right', writingDirection: 'rtl', marginTop: 2 },
  subtitle: { color: '#637188', fontSize: 10, textAlign: 'right', writingDirection: 'rtl' },
  profile: { color: '#a6761f', fontSize: 10, fontWeight: '800', textAlign: 'right', writingDirection: 'rtl' },
  headerActions: { flexDirection: 'row-reverse', alignItems: 'center', gap: 7, marginLeft: 2 },
  accountButton: { width: 39, height: 39, borderRadius: 11, borderWidth: 1, borderColor: '#d5e0ea', backgroundColor: '#f4f8fb', alignItems: 'center', justifyContent: 'center' },
  notificationButton: { width: 42, height: 42, borderRadius: 12, backgroundColor: NAVY, alignItems: 'center', justifyContent: 'center' },
  badge: { position: 'absolute', right: -3, top: -5, minWidth: 22, minHeight: 22, borderRadius: 12, paddingHorizontal: 4, backgroundColor: '#c32f32', borderWidth: 2, borderColor: '#fff', alignItems: 'center', justifyContent: 'center' },
  badgeText: { color: '#fff', fontSize: 11, fontWeight: '800' },
  pressed: { opacity: 0.75 },
});
