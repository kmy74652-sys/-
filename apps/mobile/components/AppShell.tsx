import { ReactNode } from 'react';
import { Image, RefreshControl, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

const NAVY = '#0b3458';
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

export default function AppShell({ children, scroll = true, refreshing = false, onRefresh }: Props) {
  const { width } = useWindowDimensions();
  const compact = width < 370;
  const content = <View style={[styles.content, compact && styles.compactContent]}>{children}</View>;
  return <SafeAreaView edges={['top', 'left', 'right']} style={styles.safe}>
    <View style={styles.frame}>
      {scroll ? <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={onRefresh ? <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={NAVY} colors={[NAVY]} /> : undefined}>{content}</ScrollView> : content}
    </View>
  </SafeAreaView>;
}

export function ScreenHeader({ title, subtitle, profileName }: { title: string; subtitle?: string; profileName?: string; onBack?: () => void }) {
  return <View style={styles.header}>
    <View style={styles.headerIdentity}>
      <Image source={require('../assets/alshaeri-official-logo.png')} style={styles.logo} resizeMode="contain" accessibilityLabel="الشعار الرسمي لمؤسسة الشاعري" />
      <View style={styles.headerCopy}>
        <Text style={styles.brand}>برنامج الشاعري</Text>
        <Text style={styles.org}>مؤسسة الشاعري للتجارة العامة</Text>
        <Text style={styles.title}>{title}</Text>
        {!!subtitle && <Text style={styles.subtitle}>{subtitle}</Text>}
        {!!profileName && <Text style={styles.profile}>مرحباً، {profileName}</Text>}
      </View>
    </View>
  </View>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f5f7fd', direction: 'rtl' },
  frame: { flex: 1, maxWidth: 840, width: '100%', alignSelf: 'center', direction: 'rtl' },
  scroll: { flex: 1 },
  scrollContent: { paddingBottom: 18 },
  content: { padding: 12, gap: 12, direction: 'rtl' },
  compactContent: { paddingHorizontal: 8 },
  header: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8, paddingHorizontal: 4, paddingTop: 4, paddingBottom: 8, direction: 'rtl' },
  headerIdentity: { flex: 1, minWidth: 0, flexDirection: 'row-reverse', alignItems: 'center', gap: 8 },
  logo: { width: 61, height: 61, flexShrink: 0 },
  headerCopy: { flex: 1, minWidth: 0, alignItems: 'flex-end', gap: 1 },
  brand: { color: NAVY, fontSize: 22, fontWeight: '900', textAlign: 'right', writingDirection: 'rtl' },
  org: { color: NAVY, fontSize: 12, fontWeight: '700', textAlign: 'right', writingDirection: 'rtl' },
  title: { color: NAVY, fontSize: 19, fontWeight: '900', textAlign: 'right', writingDirection: 'rtl' },
  subtitle: { color: '#637188', fontSize: 12, textAlign: 'right', writingDirection: 'rtl' },
  profile: { color: '#a6761f', fontSize: 12, fontWeight: '800', textAlign: 'right', writingDirection: 'rtl' },
});
