import { useCallback, useEffect, useRef, useState } from 'react';
import { useFocusEffect, useRouter } from 'expo-router';
import { ActivityIndicator, Image, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { friendlyDataError, getMyEmployeeProfile, listMyNotifications, type MobileNotification, type MobileProfile } from '../lib/mobileData';
import { countUnreadNotifications, loadHomeSummary } from '../lib/homeData';
import { homeAccess, type HomeDestination, type TaskFilter } from '../lib/homeModel';
import { loadOrganizationBranding, type OrganizationBranding } from '../lib/organizationBranding';
import { supabase } from '../lib/supabase';
import HomeIcon, { type HomeIconName } from './HomeIcon';

const NAVY = '#0b3458';
const GOLD = '#dba62a';
const services: Array<{ key: HomeDestination; title: string; subtitle: string; icon: HomeIconName }> = [
  { key: 'tasks', title: 'إدارة المهام', subtitle: 'إنشاء ومتابعة المهام', icon: 'tasks' },
  { key: 'reports', title: 'التقارير', subtitle: 'تقارير شاملة ومفصلة', icon: 'reports' },
  { key: 'employees', title: 'إدارة الموظفين', subtitle: 'بيانات الموظفين والحسابات', icon: 'employees' },
  { key: 'branches', title: 'إدارة الفروع', subtitle: 'إضافة وتعديل الفروع', icon: 'branches' },
  { key: 'performance', title: 'إحصائيات ومقارنة الأداء', subtitle: 'ترتيب الموظفين ومقارنة الفروع', icon: 'reports' },
  { key: 'task-designer', title: 'مصمم المهام', subtitle: 'تصميم مهام دورية ومخصصة', icon: 'task-designer' },
  { key: 'report-designer', title: 'مصمم التقارير', subtitle: 'إنشاء تقارير ديناميكية', icon: 'report-designer' },
  { key: 'agreements', title: 'اتفاقية العمل', subtitle: 'عرض وقبول اتفاقية الموظف', icon: 'agreement' },
  { key: 'hr', title: 'الموارد البشرية', subtitle: 'العقود والدوام والرواتب', icon: 'agreement' },
  { key: 'permissions', title: 'الصلاحيات', subtitle: 'إدارة صلاحيات المستخدمين', icon: 'permissions' },
];
const serviceGroups: Array<{ title: string; keys: HomeDestination[] }> = [
  { title: 'العمل والمتابعة', keys: ['tasks', 'reports', 'performance'] },
  { title: 'الموظفون والفروع', keys: ['employees', 'branches'] },
  { title: 'أدوات الإعداد', keys: ['task-designer', 'report-designer'] },
  { title: 'الموارد والإعدادات', keys: ['agreements', 'hr', 'permissions'] },
];
const metrics: Array<{ filter: TaskFilter; title: string; icon: HomeIconName; background: string; foreground: string }> = [
  { filter: 'all', title: 'إجمالي المهام', icon: 'tasks', background: '#e0ecff', foreground: '#164c80' },
  { filter: 'in_progress', title: 'قيد التنفيذ', icon: 'play', background: '#e2f3ee', foreground: '#146b50' },
  { filter: 'submitted', title: 'بانتظار المراجعة', icon: 'check', background: '#fff0dc', foreground: '#915511' },
  { filter: 'late', title: 'مهام متأخرة', icon: 'clock', background: '#ffe2e7', foreground: '#ab2b37' },
];
type Summary = Awaited<ReturnType<typeof loadHomeSummary>>;
type Props = { profile: MobileProfile; onNavigate?: (destination: HomeDestination) => void; onSignOut?: () => void };

export default function HomeDashboard({ profile: initialProfile, onNavigate, onSignOut }: Props) {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { width, fontScale } = useWindowDimensions();
  const compact = width < 370;
  const largeText = fontScale > 1.3;
  const [profile, setProfile] = useState(initialProfile);
  const [branchId, setBranchId] = useState<string | null>(() => initialProfile.branches.find((branch) => branch.isDefault)?.id ?? initialProfile.branches[0]?.id ?? null);
  const [roleCode, setRoleCode] = useState(initialProfile.roles[0]?.code ?? '');
  const [summary, setSummary] = useState<Summary | null>(null);
  const [unread, setUnread] = useState<number | null>(null);
  const [branding, setBranding] = useState<OrganizationBranding | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [notificationError, setNotificationError] = useState('');
  const [modal, setModal] = useState<'context' | 'notifications' | null>(null);
  const [notifications, setNotifications] = useState<MobileNotification[]>([]);
  const [notificationsBusy, setNotificationsBusy] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const request = useRef(0);
  const lastLoadedAt = useRef(0);
  const hasLoaded = useRef(false);
  const access = homeAccess(profile);
  const currentBranch = profile.branches.find((branch) => branch.id === branchId);
  const currentRole = profile.roles.find((role) => role.code === roleCode) ?? profile.roles[0];

  const load = useCallback(async (force = false) => {
    if (!force && hasLoaded.current && Date.now() - lastLoadedAt.current < 30_000) return;
    const ticket = ++request.current;
    setError('');
    setRefreshing(true);
    try {
      const identity = await getMyEmployeeProfile();
      if (!identity?.employee) {
        if (ticket !== request.current) return;
        onSignOut?.();
        router.replace('/');
        throw new Error('employee_not_active');
      }
      const fresh = identity.employee;
      if (ticket !== request.current) return;
      setProfile(fresh);
      // Only assignments supplied by the authenticated profile can be chosen.
      const authorizedBranch = branchId && fresh.branches.some((branch) => branch.id === branchId) ? branchId : null;
      if (branchId !== authorizedBranch) {
        setBranchId(authorizedBranch);
        setSummary(null);
        setLastUpdated(null);
        hasLoaded.current = false;
        return;
      }
      const [counts, brand, badge] = await Promise.all([
        loadHomeSummary(fresh, authorizedBranch),
        loadOrganizationBranding(fresh.institutionId).catch(() => null),
        countUnreadNotifications().catch(() => null),
      ]);
      if (ticket !== request.current) return;
      setSummary(counts);
      setBranding(brand);
      setUnread(badge);
      setNotificationError(badge === null ? 'تعذر تحديث عداد التنبيهات. أعد المحاولة.' : '');
      setLastUpdated(new Date());
      lastLoadedAt.current = Date.now();
      hasLoaded.current = true;
    } catch (cause) {
      if (ticket === request.current) setError(friendlyDataError(cause, 'تعذر تحديث الرئيسية. تحقق من الاتصال واسحب لأسفل لإعادة المحاولة.'));
    } finally {
      if (ticket === request.current) setRefreshing(false);
    }
  }, [branchId, onSignOut, router]);

  useFocusEffect(useCallback(() => {
    void load();
    return () => { ++request.current; };
  }, [load]));
  useEffect(() => { setProfile(initialProfile); }, [initialProfile]);

  function openTasks(status: TaskFilter = 'all') {
    if (!access.tasks) return;
    router.push({ pathname: '/tasks', params: { status, mode: access.manageTasks ? 'all' : 'mine', ...(branchId ? { branchId } : {}) } });
  }
  function navigate(destination: HomeDestination) {
    if (!access[destination]) return;
    if (destination === 'settings' || destination === 'permissions') router.push('/settings');
    else if (destination === 'agreements') router.push('/agreement' as never);
    else if (destination === 'hr') router.push('/hr' as never);
    else if (onNavigate) onNavigate(destination);
    else if (destination === 'tasks') {
      if (access.manageTasks) router.push({ pathname: '/admin', params: { section: 'tasks' } });
      else openTasks();
    } else if (destination === 'reports' && !access.manageTasks) {
      router.push({ pathname: '/tasks', params: { view: 'reports', mode: 'mine', ...(branchId ? { branchId } : {}) } });
    } else if (destination === 'employees' && access.settings) router.push('/settings');
    else router.push({ pathname: '/admin', params: { section: destination } });
  }
  async function openNotifications() {
    setModal('notifications');
    setNotificationsBusy(true);
    setNotificationError('');
    try { setNotifications(await listMyNotifications()); }
    catch (cause) { setNotificationError(friendlyDataError(cause, 'تعذر تحميل التنبيهات. تحقق من الاتصال ثم أعد المحاولة.')); }
    finally { setNotificationsBusy(false); }
  }
  async function signOut() {
    if (signingOut) return;
    setSigningOut(true);
    try {
      if (!supabase) throw new Error('supabase_not_configured');
      const { error: signOutError } = await supabase.auth.signOut();
      if (signOutError) throw signOutError;
      onSignOut?.();
      router.replace('/');
    } catch { setError('تعذر تسجيل الخروج بأمان. تحقق من الاتصال ثم أعد المحاولة.'); }
    finally { setSigningOut(false); }
  }
  function chooseBranch(id: string | null) {
    if (id !== null && !profile.branches.some((branch) => branch.id === id)) return;
    if (id === branchId) return;
    ++request.current;
    setBranchId(id);
    setSummary(null);
    setLastUpdated(null);
  }
  const formatDate = (date: Date) => new Intl.DateTimeFormat('ar-YE', { calendar: 'gregory', numberingSystem: 'latn', dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Aden' }).format(date);

  return <SafeAreaView edges={['top', 'left', 'right']} style={styles.safe}>
    <View style={styles.frame}>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.content} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load(true)} tintColor={NAVY} colors={[NAVY]} />}>
        <View style={[styles.brandHeader, compact && styles.compactHeader]}>
          <Image source={require('../assets/alshaeri-official-logo.png')} style={[styles.logo, compact && styles.compactLogo]} resizeMode="contain" accessibilityLabel="الشعار الرسمي لمؤسسة الشاعري" />
          <Pressable accessibilityRole="button" accessibilityLabel="تبديل الحساب" accessibilityHint="تسجيل الخروج وفتح حساب آخر" disabled={signingOut} style={({ pressed }) => [styles.accountSwitchButton, pressed && styles.pressed]} onPress={() => void signOut()}>
            <HomeIcon name="avatar" size={24} color={NAVY} />
          </Pressable>
          <View style={styles.brandCopy}>
            <Text style={[styles.brandTitle, compact && styles.compactTitle]}>برنامج الشاعري</Text>
            <Text style={[styles.brandSubtitle, compact && styles.compactSubtitle]}>{branding?.name || 'مؤسسة الشاعري للتجارة العامة'}</Text>
            <View style={styles.mottoRow}><View style={styles.mottoLine} /><Text style={styles.motto}>{branding?.tagline || 'معاً .. نحو إدارة أفضل'}</Text><View style={styles.mottoLine} /></View>
          </View>
          <Pressable accessibilityRole="button" accessibilityLabel={`الإشعارات، ${unread === null ? 'العداد غير متاح' : `${unread} غير مقروءة`}`} style={({ pressed }) => [styles.notificationButton, pressed && styles.pressed]} onPress={() => void openNotifications()}>
            <HomeIcon name="bell" size={28} color="#fff" />
            {unread !== null && unread > 0 && <View style={styles.badge}><Text style={styles.badgeText}>{unread > 99 ? '99+' : unread}</Text></View>}
          </Pressable>
        </View>

        <View style={styles.main}>
          {!!error && <View style={styles.errorPanel}><Text accessibilityRole="alert" style={styles.error}>{error}{lastUpdated ? ' الأرقام المعروضة من آخر تحديث ناجح.' : ''}</Text><Pressable style={styles.retry} onPress={() => void load()} accessibilityRole="button"><Text style={styles.retryText}>إعادة المحاولة</Text></Pressable></View>}
          <View style={styles.metrics}>
            {metrics.map((item) => <Pressable key={item.filter} accessibilityRole="button" accessibilityState={{ disabled: !access.tasks || summary === null }} accessibilityLabel={`${item.title}: ${summary?.[item.filter as keyof Summary] ?? 'لم تحمل بعد'}`} disabled={!access.tasks || summary === null} style={({ pressed }) => [styles.metric, { backgroundColor: item.background, borderColor: `${item.foreground}25` }, pressed && styles.pressed]} onPress={() => openTasks(item.filter)}>
              <HomeIcon name={item.icon} size={compact ? 27 : 31} color={item.foreground} />
              <Text style={[styles.metricValue, { color: item.foreground }]}>{summary?.[item.filter as keyof Summary] ?? '—'}</Text>
              <Text style={[styles.metricLabel, compact && styles.compactMetricLabel, { color: item.foreground }]}>{item.title}</Text>
            </Pressable>)}
          </View>

          {serviceGroups.map((group) => {
            const groupServices = group.keys.map((key) => services.find((item) => item.key === key)).filter((item): item is typeof services[number] => Boolean(item && access[item.key]));
            if (!groupServices.length) return null;
            return <View key={group.title} style={styles.serviceGroup}><View style={styles.serviceGroupHeading}><Text style={styles.serviceGroupTitle}>{group.title}</Text><Text style={styles.serviceGroupHint}>{groupServices.length} أقسام</Text></View><View style={styles.moduleGrid}>
              {groupServices.map((item) => <Pressable key={item.key} accessibilityRole="button" accessibilityState={{ disabled: false }} accessibilityLabel={`${item.title}، ${item.subtitle}`} style={({ pressed }) => [styles.moduleCard, largeText && styles.largeModuleCard, pressed && styles.pressed]} onPress={() => navigate(item.key)}>
                <HomeIcon name={item.icon} size={compact ? 31 : 37} />
                <View style={styles.moduleCopy}><Text style={[styles.moduleTitle, compact && styles.compactModuleTitle]}>{item.title}</Text><Text style={[styles.moduleSubtitle, compact && styles.compactModuleSubtitle]}>{item.subtitle}</Text></View>
              </Pressable>)}
            </View></View>;
          })}

          <View style={[styles.branchFooter, largeText && styles.stackedFooter]}>
            <View style={styles.footerPart}><HomeIcon name="calendar" size={27} /><View style={styles.footerCopy}><Text style={styles.footerTitle}>آخر تحديث</Text><Text style={styles.footerValue}>{lastUpdated ? formatDate(lastUpdated) : 'لم يُحدّث بعد'}</Text></View></View>
            <View style={styles.footerDivider} />
            <Pressable accessibilityRole="button" accessibilityLabel="تغيير الفرع الحالي" style={styles.footerPart} onPress={() => setModal('context')}><HomeIcon name="branches" size={28} /><View style={styles.footerCopy}><Text style={styles.footerTitle}>الفرع الحالي</Text><Text style={styles.branchName}>{currentBranch?.name || 'كل الفروع المسموح بها'}</Text></View></Pressable>
          </View>
        </View>
      </ScrollView>

      <View style={[styles.bottomBar, { paddingBottom: Math.max(insets.bottom, 8) }]}>
        {([{ key: 'home', title: 'الرئيسية', icon: 'home' }, { key: 'tasks', title: 'المهام', icon: 'tasks' }, { key: 'employees', title: 'الموظفون', icon: 'employees' }, { key: 'settings', title: 'الإعدادات', icon: 'settings' }] as const).map((item) => {
          const selected = item.key === 'home';
          const enabled = selected || access[item.key];
          return <Pressable key={item.key} accessibilityRole="tab" accessibilityState={{ selected, disabled: !enabled }} disabled={!enabled} style={({ pressed }) => [styles.bottomItem, selected && styles.bottomItemActive, !enabled && styles.bottomItemDisabled, pressed && styles.pressed]} onPress={() => { if (!selected) navigate(item.key); }}><HomeIcon name={item.icon} size={29} color={selected ? NAVY : '#fff'} /><Text style={[styles.bottomLabel, selected && styles.bottomLabelActive]}>{item.title}</Text></Pressable>;
        })}
      </View>
    </View>

    <Modal visible={modal !== null} transparent animationType="fade" onRequestClose={() => setModal(null)}>
      <View style={styles.modalBackdrop}><SafeAreaView style={styles.modalCard}>
        <View style={styles.modalHeading}><Text accessibilityRole="header" style={styles.modalTitle}>{modal === 'context' ? 'الدور والفرع' : 'الإشعارات'}</Text><Pressable accessibilityRole="button" accessibilityLabel="إغلاق" style={styles.closeButton} onPress={() => setModal(null)}><Text style={styles.closeText}>إغلاق</Text></Pressable></View>
        <ScrollView contentContainerStyle={styles.modalContent}>
          {modal === 'context' ? <>
            <Text style={styles.fieldLabel}>الصفة الوظيفية</Text><Text style={styles.modalHint}>اختر صفة من أدوارك المسندة. لا يغير هذا الاختيار صلاحيات حسابك.</Text>
            {profile.roles.map((role) => <Pressable key={role.code} accessibilityRole="radio" accessibilityState={{ checked: currentRole?.code === role.code }} style={[styles.contextChoice, currentRole?.code === role.code && styles.contextSelected]} onPress={() => setRoleCode(role.code)}><Text style={styles.contextText}>{role.nameAr}</Text>{currentRole?.code === role.code && <HomeIcon name="check" size={22} color="#146b50" />}</Pressable>)}
            <Text style={styles.fieldLabel}>الفرع الحالي</Text><Text style={styles.modalHint}>يصفّي هذا الاختيار ملخص الرئيسية وقائمة المهام.</Text>
            {[{ id: null, name: 'كل الفروع المسموح بها' }, ...profile.branches].map((branch) => <Pressable key={branch.id ?? 'all'} accessibilityRole="radio" accessibilityState={{ checked: branchId === branch.id }} style={[styles.contextChoice, branchId === branch.id && styles.contextSelected]} onPress={() => chooseBranch(branch.id)}><Text style={styles.contextText}>{branch.name}</Text>{branchId === branch.id && <HomeIcon name="check" size={22} color="#146b50" />}</Pressable>)}
            <Pressable accessibilityRole="button" accessibilityLabel="تبديل الحساب" accessibilityHint="تسجيل الخروج وفتح حساب آخر" disabled={signingOut} style={styles.signOutButton} onPress={() => void signOut()}><HomeIcon name="avatar" size={25} color="#a62636" /></Pressable>
          </> : <>
            {notificationsBusy && <ActivityIndicator color={NAVY} />}
            {!!notificationError && <Text accessibilityRole="alert" style={styles.error}>{notificationError}</Text>}
            {!notificationsBusy && !notificationError && !notifications.length && <Text style={styles.modalHint}>لا توجد تنبيهات جديدة.</Text>}
            {!notificationsBusy && notifications.map((item) => <View key={item.id} style={styles.notificationCard}><Text style={styles.fieldLabel}>{item.title}</Text><Text style={styles.modalHint}>{item.body}</Text><Text style={styles.notificationDate}>{formatDate(new Date(item.created_at))}{item.read_at ? ' · مقروء' : ' · جديد'}</Text></View>)}
            <Pressable accessibilityRole="button" style={styles.contextChoice} onPress={() => void openNotifications()}><Text style={styles.contextText}>تحديث التنبيهات</Text></Pressable>
          </>}
        </ScrollView>
      </SafeAreaView></View>
    </Modal>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f5f7fd' },
  frame: { flex: 1, width: '100%', maxWidth: 840, alignSelf: 'center', direction: 'rtl' },
  scroll: { flex: 1 },
  content: { flexGrow: 1, paddingBottom: 16 },
  brandHeader: { flexDirection: 'row-reverse', alignItems: 'center', paddingHorizontal: 10, paddingTop: 10, paddingBottom: 8, minHeight: 122, gap: 8, direction: 'rtl' },
  compactHeader: { paddingHorizontal: 8, minHeight: 104, gap: 5 },
  logo: { width: 74, height: 86, flexShrink: 0 },
  compactLogo: { width: 58, height: 70 },
  accountSwitchButton: { width: 44, height: 44, borderRadius: 22, borderWidth: 1, borderColor: '#c6d3e3', backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', flexShrink: 0 },
  brandCopy: { flex: 1, minWidth: 0, gap: 4, alignItems: 'center' },
  brandTitle: { color: NAVY, fontSize: 24, fontWeight: '900', textAlign: 'center', writingDirection: 'rtl', flexShrink: 1 },
  compactTitle: { fontSize: 19 },
  brandSubtitle: { color: NAVY, fontSize: 13, fontWeight: '800', textAlign: 'center', writingDirection: 'rtl', flexShrink: 1 },
  compactSubtitle: { fontSize: 11 },
  mottoRow: { flexDirection: 'row', gap: 5, alignItems: 'center', justifyContent: 'center' },
  mottoLine: { width: 15, height: 1.5, backgroundColor: '#bf9229' },
  motto: { color: NAVY, fontSize: 11, fontWeight: '700', textAlign: 'center', writingDirection: 'rtl', flexShrink: 1 },
  notificationButton: { width: 48, height: 48, borderRadius: 24, backgroundColor: NAVY, alignItems: 'center', justifyContent: 'center', flexShrink: 0 },
  badge: { position: 'absolute', right: -3, top: -5, borderRadius: 13, backgroundColor: '#c32f32', minWidth: 24, minHeight: 24, paddingHorizontal: 4, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: '#f5f7fd' },
  badgeText: { color: '#fff', fontSize: 12, fontWeight: '800' },
  main: { paddingHorizontal: 10, gap: 11, paddingTop: 8 },
  metrics: { flexDirection: 'row', gap: 7, direction: 'rtl' },
  metric: { flex: 1, minWidth: 0, minHeight: 122, borderWidth: 1, borderRadius: 15, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 3, paddingVertical: 10, gap: 3 },
  metricValue: { fontSize: 31, fontWeight: '900', textAlign: 'center' },
  metricLabel: { fontSize: 13, fontWeight: '800', textAlign: 'center', lineHeight: 20, writingDirection: 'rtl' },
  compactMetricLabel: { fontSize: 11 },
  moduleGrid: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', rowGap: 8, direction: 'rtl' },
  serviceGroup: { gap: 7 },
  serviceGroupHeading: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 3, direction: 'rtl' },
  serviceGroupTitle: { color: NAVY, fontSize: 15, fontWeight: '900', textAlign: 'right', writingDirection: 'rtl' },
  serviceGroupHint: { color: '#718096', fontSize: 11, fontWeight: '700', writingDirection: 'rtl' },
  moduleCard: { width: '49%', minHeight: 82, flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 10, paddingVertical: 9, borderRadius: 16, backgroundColor: '#fbfcff', borderWidth: 1, borderColor: '#d6dfed', shadowColor: '#244979', shadowOffset: { width: 0, height: 3 }, shadowOpacity: 0.12, shadowRadius: 4, elevation: 2, direction: 'rtl' },
  largeModuleCard: { flexDirection: 'column', alignItems: 'center' },
  moduleCopy: { flex: 1, gap: 3, minWidth: 0 },
  moduleTitle: { color: NAVY, fontSize: 16, fontWeight: '800', textAlign: 'right', writingDirection: 'rtl' },
  compactModuleTitle: { fontSize: 14 },
  moduleSubtitle: { color: '#4e596c', fontSize: 11.5, textAlign: 'right', lineHeight: 18, writingDirection: 'rtl' },
  compactModuleSubtitle: { fontSize: 10.5 },
  unavailableCard: { backgroundColor: '#eef2f8', elevation: 0, shadowOpacity: 0 },
  unavailableText: { color: '#505a6b', fontSize: 10, textAlign: 'right', writingDirection: 'rtl' },
  branchFooter: { flexDirection: 'row', alignItems: 'center', padding: 10, gap: 8, borderRadius: 14, backgroundColor: '#dfe7f7', minHeight: 72, direction: 'rtl' },
  stackedFooter: { flexDirection: 'column', alignItems: 'stretch' },
  footerPart: { flex: 1, flexDirection: 'row-reverse', alignItems: 'center', gap: 7, minHeight: 44 },
  footerCopy: { flex: 1 },
  footerTitle: { color: NAVY, fontSize: 12, fontWeight: '800', textAlign: 'right', writingDirection: 'rtl' },
  footerValue: { color: NAVY, fontSize: 10.5, lineHeight: 17, textAlign: 'right', writingDirection: 'rtl' },
  branchName: { color: NAVY, fontSize: 12, fontWeight: '700', lineHeight: 19, textAlign: 'right', writingDirection: 'rtl' },
  footerDivider: { height: 35, width: 1, backgroundColor: GOLD },
  bottomBar: { flexDirection: 'row', backgroundColor: NAVY, borderTopWidth: 3, borderTopColor: GOLD, paddingTop: 7, paddingHorizontal: 6, gap: 4, direction: 'rtl' },
  bottomItem: { flex: 1, minHeight: 65, paddingVertical: 7, paddingHorizontal: 2, alignItems: 'center', justifyContent: 'center', gap: 4, borderRadius: 17 },
  bottomItemActive: { backgroundColor: '#e5b336' },
  bottomItemDisabled: { opacity: 0.55 },
  bottomLabel: { color: '#fff', fontSize: 13, fontWeight: '700', textAlign: 'center', writingDirection: 'rtl' },
  bottomLabelActive: { color: NAVY, fontWeight: '900' },
  pressed: { opacity: 0.78 },
  errorPanel: { padding: 10, borderRadius: 12, backgroundColor: '#fff0f1', gap: 5 },
  error: { color: '#9f2535', fontSize: 13, lineHeight: 21, textAlign: 'right', writingDirection: 'rtl' },
  retry: { minHeight: 44, alignItems: 'center', justifyContent: 'center' },
  retryText: { color: NAVY, fontWeight: '800', textDecorationLine: 'underline' },
  modalBackdrop: { flex: 1, backgroundColor: '#061f38aa', justifyContent: 'center', padding: 18 },
  modalCard: { width: '100%', maxWidth: 540, maxHeight: '85%', alignSelf: 'center', borderRadius: 22, backgroundColor: '#fff', direction: 'rtl' },
  modalHeading: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingTop: 12 },
  modalTitle: { color: NAVY, fontSize: 21, fontWeight: '800', writingDirection: 'rtl' },
  closeButton: { minWidth: 60, minHeight: 44, alignItems: 'center', justifyContent: 'center' },
  closeText: { color: NAVY, fontWeight: '700' },
  modalContent: { padding: 16, gap: 9 },
  fieldLabel: { color: NAVY, fontSize: 16, fontWeight: '800', textAlign: 'right', writingDirection: 'rtl', marginTop: 5 },
  modalHint: { color: '#4e596c', fontSize: 13, lineHeight: 22, textAlign: 'right', writingDirection: 'rtl' },
  contextChoice: { minHeight: 48, flexDirection: 'row-reverse', justifyContent: 'space-between', alignItems: 'center', borderWidth: 1, borderColor: '#d6dfed', borderRadius: 11, padding: 10, gap: 9 },
  contextSelected: { borderColor: '#146b50', backgroundColor: '#e2f3ee' },
  contextText: { flexShrink: 1, color: NAVY, fontSize: 14, fontWeight: '700', writingDirection: 'rtl', textAlign: 'right' },
  signOutButton: { width: 52, height: 48, alignSelf: 'flex-end', alignItems: 'center', justifyContent: 'center', borderColor: '#b32f3d', borderWidth: 1, borderRadius: 11, marginTop: 10 },
  notificationCard: { padding: 12, backgroundColor: '#f5f7fd', borderRadius: 12, gap: 5 },
  notificationDate: { color: '#4e596c', fontSize: 11, textAlign: 'right', writingDirection: 'rtl' },
});
