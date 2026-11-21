import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Image, Pressable, RefreshControl, SafeAreaView, ScrollView, Share, StyleSheet, Text, TextInput, View } from 'react-native';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import * as FileSystem from 'expo-file-system';
import AdenDeadlinePicker, { adenDateTimeToIso, currentAdenDateTime } from '../components/AdenDeadlinePicker';
import HomeDashboard from '../components/HomeDashboard';
import AppShell, { type ShellTab } from '../components/AppShell';
import { friendlyDataError, getMyEmployeeProfile, type MobileProfile } from '../lib/mobileData';
import { createAdministrativeTask, loadDashboardData, roleLabel, statusLabel, type DashboardData } from '../lib/adminData';
import { supabase } from '../lib/supabase';
import { loadOrganizationBranding } from '../lib/organizationBranding';
import { listApprovedDesignerTemplates, type ReportTemplate } from '../lib/reportDesigner';
import ReportDesigner from '../components/ReportDesigner';
import { type TaskTemplateDraft } from '../components/TaskDesigner';
import OrganizationalTaskDesigner from '../components/OrganizationalTaskDesigner';
import { deleteTaskDesignerTemplate, listApprovedTaskReportForms, listTaskDesignerCategories, listTaskDesignerTemplates, saveTaskDesignerTemplate, type StoredTaskTemplate, type TaskCategoryRow } from '../lib/taskDesigner';
import { deleteManagedBranch, deleteManagedReport, deleteManagedTask, updateManagedTask } from '../lib/managementData';
import { reviewEmployeeRoleReport } from '../lib/employeeRoleReports';
import PerformanceAnalytics from '../components/PerformanceAnalytics';
import { readSessionCache, writeSessionCache } from '../lib/mobileSessionCache';
import ReportSubmissionReviewPanel from '../components/ReportSubmissionReviewPanel';
import TaskPublicationReviewPanel from '../components/TaskPublicationReviewPanel';
import { submitTaskPublicationRequest } from '../lib/taskPublication';

type Section = 'overview' | 'tasks' | 'task-designer' | 'report-designer' | 'reports' | 'performance' | 'hr' | 'branches' | 'employees' | 'activity';
const sections: Array<[Section, string]> = [['overview', 'الرئيسية'], ['tasks', 'إدارة المهام'], ['task-designer', 'الجدول التنظيمي'], ['report-designer', 'مصمم التقارير'], ['reports', 'تقارير الموظفين'], ['performance', 'إحصائيات الأداء'], ['branches', 'الفروع'], ['employees', 'الموظفون'], ['activity', 'السجل والمرفقات']];
const allowedSections: readonly Section[] = sections.map(([value]) => value);
function isSection(value: string | undefined): value is Section { return Boolean(value && allowedSections.includes(value as Section)); }
type HomeDestination = 'tasks' | 'reports' | 'employees' | 'branches' | 'performance' | 'task-designer' | 'report-designer' | 'agreements' | 'hr' | 'permissions' | 'settings';
const roleCodes = ['owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'];
const priorityLabels: Record<string, string> = { normal: 'عادية', important: 'مهمة', urgent: 'عاجلة', critical: 'حرجة' };

export default function AdminScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ section?: string | string[] }>();
  const requestedSection = Array.isArray(params.section) ? params.section[0] : params.section;
  const [section, setSection] = useState<Section>('overview');
  const [profile, setProfile] = useState<MobileProfile | null>(null);
  const [currentName, setCurrentName] = useState('');
  const [brandName, setBrandName] = useState('مؤسسة الشاعري للتجارة العامة');
  const [brandTagline, setBrandTagline] = useState('معًا... نحو إدارة أفضل');
  const [brandLogoUrl, setBrandLogoUrl] = useState<string | null>(null);
  const [data, setData] = useState<DashboardData | null>(null);
  const [designerTemplates, setDesignerTemplates] = useState<ReportTemplate[]>([]);
  const [taskDesignerTemplates, setTaskDesignerTemplates] = useState<StoredTaskTemplate[]>([]);
  const [taskCategories, setTaskCategories] = useState<TaskCategoryRow[]>([]);
  const [permissions, setPermissions] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const lastLoadedAt = useRef(0);
  const loadInFlight = useRef<Promise<void> | null>(null);
  const adminCacheKey = useRef('');
  const [showCreate, setShowCreate] = useState(false);
  const [initialDeadline] = useState(currentAdenDateTime);
  const [draft, setDraft] = useState({ title: '', description: '', dueDate: initialDeadline.date, dueTime: initialDeadline.time, priority: 'normal', roleCode: 'admin_followup', branchId: '', assignedEmployeeId: '', templateId: '', reportTemplateId: '', reportRequired: true });

  useEffect(() => {
    if (isSection(requestedSection)) setSection(requestedSection);
  }, [requestedSection]);

  const load = useCallback(async (force = false) => {
    const now = Date.now();
    if (loadInFlight.current) return loadInFlight.current;
    if (!force && now - lastLoadedAt.current < 30_000) return;
    setError('');
    const request = (async () => {
      try {
      const identity = await getMyEmployeeProfile();
      if (!identity?.employee) throw new Error('employee_not_active');
      setProfile(identity.employee);
      setCurrentName(identity.employee.fullName || 'المستخدم');
      const brandingRequest = loadOrganizationBranding(identity.employee.institutionId);
      const currentPermissions = identity.employee.permissions;
      if (!currentPermissions.includes('tasks.manage')) throw new Error('permission_denied');
      const canManageLibrary = currentPermissions.includes('task_library.manage');
      const canManageReports = currentPermissions.includes('report_forms.manage');
      const cacheKey = `${identity.userId}:${identity.employee.institutionId}`;
      adminCacheKey.current = cacheKey;
      const cachedDashboard = readSessionCache<DashboardData>('admin-dashboard', cacheKey);
      const cachedReportTemplates = readSessionCache<ReportTemplate[]>('admin-report-templates', cacheKey);
      const cachedTaskTemplates = readSessionCache<StoredTaskTemplate[]>('admin-task-templates', cacheKey);
      const cachedCategories = readSessionCache<TaskCategoryRow[]>('admin-task-categories', cacheKey);
      setPermissions(currentPermissions);
      if (cachedDashboard) setData(cachedDashboard);
      if (cachedReportTemplates) setDesignerTemplates(cachedReportTemplates);
      if (cachedTaskTemplates) setTaskDesignerTemplates(cachedTaskTemplates);
      if (cachedCategories) setTaskCategories(cachedCategories);
      if (cachedDashboard || cachedReportTemplates || cachedTaskTemplates || cachedCategories) {
        setLoading(false);
        setNotice('تُعرض آخر بيانات ناجحة، جارٍ تحديث لوحة المشرف في الخلفية…');
      }
      const [branding, dashboard, reportTemplates, editableTaskTemplates, categories] = await Promise.all([
        brandingRequest,
        loadDashboardData({ force, maxAgeMs: 30_000 }),
        canManageReports ? listApprovedDesignerTemplates() : canManageLibrary ? listApprovedTaskReportForms() : Promise.resolve([]),
        canManageLibrary ? listTaskDesignerTemplates() : Promise.resolve([]),
        canManageLibrary ? listTaskDesignerCategories() : Promise.resolve([]),
      ]);
      setBrandName(branding.name);
      setBrandTagline(branding.tagline);
      setBrandLogoUrl(branding.logoUrl);
      setNotice(branding.settingsAvailable ? (cachedDashboard ? 'تم تحديث لوحة المشرف في الخلفية.' : '') : 'تعديل هوية المؤسسة سيتاح بعد تحديث قاعدة البيانات؛ لوحة الإدارة تعمل بالبيانات الحالية.');
      setData(dashboard);
      setDesignerTemplates(reportTemplates);
      setTaskDesignerTemplates(editableTaskTemplates);
      setTaskCategories(categories);
      writeSessionCache('admin-dashboard', cacheKey, dashboard);
      writeSessionCache('admin-report-templates', cacheKey, reportTemplates);
      writeSessionCache('admin-task-templates', cacheKey, editableTaskTemplates);
      writeSessionCache('admin-task-categories', cacheKey, categories);
        lastLoadedAt.current = Date.now();
      } catch (cause) { setError(friendlyDataError(cause, 'تعذر تحميل لوحة الإدارة من Supabase.')); }
      finally { setLoading(false); setRefreshing(false); }
    })();
    loadInFlight.current = request;
    try { await request; } finally { if (loadInFlight.current === request) loadInFlight.current = null; }
  }, []);
  useEffect(() => { void load(true); }, [load]);
  useEffect(() => { const sub = AppState.addEventListener('change', (state) => { if (state === 'active') void load(); }); return () => sub.remove(); }, [load]);
  useEffect(() => { const timer = setInterval(() => void load(), 60_000); return () => clearInterval(timer); }, [load]);

  const counts = useMemo(() => {
    const tasks = data?.tasks ?? [];
    return { all: tasks.length, new: tasks.filter((task) => ['new', 'received'].includes(task.status)).length, active: tasks.filter((task) => ['in_progress', 'on_hold'].includes(task.status)).length, review: tasks.filter((task) => task.status === 'report_submitted').length, late: tasks.filter((task) => task.status === 'late' || (!!task.dueAt && new Date(task.dueAt) < new Date() && !['completed_approved', 'cancelled'].includes(task.status))).length, done: tasks.filter((task) => task.status === 'completed_approved').length };
  }, [data]);
  const updateTaskLocally = useCallback((taskId: string, patch: Partial<DashboardData['tasks'][number]>) => {
    setData((current) => {
      if (!current) return current;
      const next = { ...current, tasks: current.tasks.map((task) => task.id === taskId ? { ...task, ...patch } : task) };
      if (adminCacheKey.current) writeSessionCache('admin-dashboard', adminCacheKey.current, next);
      return next;
    });
  }, []);
  const removeTaskLocally = useCallback((taskId: string) => {
    setData((current) => {
      if (!current) return current;
      const next = { ...current, tasks: current.tasks.filter((task) => task.id !== taskId) };
      if (adminCacheKey.current) writeSessionCache('admin-dashboard', adminCacheKey.current, next);
      return next;
    });
  }, []);
  const restoreTaskLocally = useCallback((task: DashboardData['tasks'][number]) => {
    setData((current) => {
      if (!current || current.tasks.some((item) => item.id === task.id)) return current;
      const next = { ...current, tasks: [...current.tasks, task].sort((left, right) => (left.dueAt ?? '').localeCompare(right.dueAt ?? '')) };
      if (adminCacheKey.current) writeSessionCache('admin-dashboard', adminCacheKey.current, next);
      return next;
    });
  }, []);
  const updateReportLocally = useCallback((reportId: string, patch: Partial<DashboardData['reports'][number]>) => {
    setData((current) => {
      if (!current) return current;
      const next = { ...current, reports: current.reports.map((report) => report.id === reportId ? { ...report, ...patch } : report) };
      if (adminCacheKey.current) writeSessionCache('admin-dashboard', adminCacheKey.current, next);
      return next;
    });
  }, []);
  const removeReportLocally = useCallback((reportId: string) => {
    setData((current) => {
      if (!current) return current;
      const next = { ...current, reports: current.reports.filter((report) => report.id !== reportId) };
      if (adminCacheKey.current) writeSessionCache('admin-dashboard', adminCacheKey.current, next);
      return next;
    });
  }, []);

  async function signOut() {
    try {
      if (!supabase) throw new Error('supabase_unavailable');
      const { error: signOutError } = await supabase.auth.signOut();
      if (signOutError) throw signOutError;
      router.replace('/');
    } catch {
      setError('تعذر تسجيل الخروج. تحقق من الاتصال ثم حاول مرة أخرى.');
    }
  }
  async function createTask() {
    const dueAt = adenDateTimeToIso(draft.dueDate, draft.dueTime);
    if (!draft.title.trim() || !dueAt) { setError('أدخل عنوان المهمة واختر تاريخًا ووقتًا صالحين للموعد النهائي.'); return; }
    if (!draft.assignedEmployeeId) { setError('اختر الموظف المستلم للمهمة قبل النشر.'); return; }
    const startAt = new Date();
    if (new Date(dueAt).getTime() < startAt.getTime()) { setError('لا يمكن أن يسبق الموعد النهائي بداية المهمة. اختر موعدًا الآن أو لاحقًا بتوقيت عدن.'); return; }
    try {
      setError(''); setNotice('');
      const selectedReport = designerTemplates.find((template) => template.role_code === draft.roleCode && template.approved_version_id && template.is_active !== false);
      const createdTask = await createAdministrativeTask({
        title: draft.title, description: draft.description, dueAt, priority: draft.priority,
        roleCode: draft.roleCode, branchId: draft.branchId || null, assignedEmployeeId: draft.assignedEmployeeId, templateId: draft.templateId || null,
        reportTemplateId: selectedReport?.id ?? null, reportVersionId: selectedReport?.approved_version_id ?? null,
        reportRequired: Boolean(selectedReport?.approved_version_id),
      });
      const branchName = data?.branches.find((branch) => branch.id === (draft.branchId || null))?.name ?? null;
      setData((current) => {
        if (!current) return current;
        const next = {
          ...current,
          tasks: [...current.tasks, {
            id: createdTask.id,
            title: draft.title.trim(),
            description: draft.description.trim() || null,
            branchId: draft.branchId || null,
            branchName,
            assignedTo: createdTask.assigned_to,
            dueAt,
            priority: draft.priority,
            status: 'new' as const,
          }].sort((left, right) => (left.dueAt ?? '').localeCompare(right.dueAt ?? '')),
        };
        if (adminCacheKey.current) writeSessionCache('admin-dashboard', adminCacheKey.current, next);
        return next;
      });
      const nextDeadline = currentAdenDateTime();
      setDraft({ title: '', description: '', dueDate: nextDeadline.date, dueTime: nextDeadline.time, priority: 'normal', roleCode: 'admin_followup', branchId: '', assignedEmployeeId: '', templateId: '', reportTemplateId: '', reportRequired: true });
      setShowCreate(false); setNotice('تم إنشاء المهمة وإسنادها للموظف المحدد. ظهرت مباشرة في القائمة.');
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر إنشاء المهمة. تأكد من وجود موظف نشط ضمن التصنيف والفرع المحددين.')); }
  }
  async function saveDesignerTask(draft: TaskTemplateDraft) {
    const saved = await saveTaskDesignerTemplate(draft, taskCategories);
    await load(true);
    return saved;
  }
  async function sendDesignerTask(draft: TaskTemplateDraft, branchId: string | null, dueAt: string) {
    if (!draft.id) throw new Error('task_template_save_response_invalid');
    await submitTaskPublicationRequest(draft.id, branchId, dueAt);
    await load(true);
  }
  const canManageTasks = permissions.includes('tasks.manage');
  const canManageTaskLibrary = permissions.includes('task_library.manage');
  const canManageReports = permissions.includes('report_forms.manage');
  const canViewReports = permissions.includes('reports.read_all') || permissions.includes('tasks.review');
  const canManageEmployees = Boolean(profile?.roles.some((role) => role.code === 'owner' || role.code === 'admin_followup') && permissions.includes('employees.manage'));
  const canViewEmployees = canManageEmployees || permissions.includes('employees.read');
  const canViewBranches = permissions.includes('branches.read_all') || permissions.includes('branches.manage');
  const canViewActivity = permissions.includes('audit.read');
  const fmt = (value: string | null) => value ? new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : 'غير محدد';

  function navigateFromHome(destination: HomeDestination) {
    if (destination === 'settings' || destination === 'permissions') { router.push('/settings'); return; }
    if (destination === 'agreements') { router.push('/agreement' as never); return; }
    if (destination === 'hr') { router.push('/hr' as never); return; }
    if (destination === 'employees') { if (canManageEmployees) router.push('/settings?tab=employees'); else if (canViewEmployees) setSection('employees'); return; }
    if (destination === 'tasks') { setSection('tasks'); return; }
    if (destination === 'reports') { if (canViewReports) setSection('reports'); return; }
    if (destination === 'branches') { if (canViewBranches) setSection('branches'); return; }
    if (destination === 'performance') { if (canViewReports) setSection('performance'); return; }
    if (destination === 'task-designer') { if (canManageTaskLibrary) setSection('task-designer'); return; }
    if (destination === 'report-designer') { if (canManageReports) setSection('report-designer'); }
  }

  if (loading) return <SafeAreaView style={styles.safe}><View style={styles.center}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.muted}>جارٍ تحميل لوحة الإدارة…</Text></View></SafeAreaView>;
  if (section === 'overview' && profile) return <HomeDashboard profile={profile} onNavigate={navigateFromHome} />;
  const shellTab: ShellTab = section === 'tasks' ? 'tasks' : section === 'employees' ? 'employees' : section === 'overview' ? 'home' : 'settings';
  const sectionTitles: Record<Section, string> = { overview: 'الرئيسية', tasks: 'إدارة المهام', 'task-designer': 'مصمم المهام', 'report-designer': 'مصمم التقارير', reports: 'تقارير الموظفين', performance: 'إحصائيات ومقارنة الأداء', hr: 'الموارد البشرية', branches: 'إدارة الفروع', employees: 'الموظفون', activity: 'السجل والمرفقات' };
  return <AppShell activeTab={shellTab} title={sectionTitles[section]} subtitle="لوحة إدارة المؤسسة" profileName={currentName} onRefresh={() => { setRefreshing(true); void load(true); }}>
    <Stack.Screen options={{ headerShown: false }} />
    {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
    {!!notice && <Text style={styles.notice}>{notice}</Text>}

      {section === 'overview' && !profile && <Overview counts={counts} data={data} fmt={fmt} onSection={setSection} onSettings={() => router.push('/settings')} onHR={() => router.push('/hr' as never)} canDesign={canManageTaskLibrary} canDesignReports={canManageReports} />}
      {section === 'tasks' && <TasksSection data={data} designerTemplates={designerTemplates} canDesign={canManageTaskLibrary} showCreate={showCreate} setShowCreate={setShowCreate} draft={draft} setDraft={setDraft} createTask={createTask} fmt={fmt} onOpenTasks={() => router.push('/tasks')} canManage={canManageTasks} institutionId={profile?.institutionId ?? ''} onReload={load} onTaskUpdated={updateTaskLocally} onTaskDeleted={removeTaskLocally} onTaskRestored={restoreTaskLocally} onDesignerSave={saveDesignerTask} onDesignerSend={sendDesignerTask} />}
      {section === 'task-designer' && (canManageTaskLibrary ? <><Text style={styles.sectionTitle}>طلبات اعتماد ونشر المهام</Text>{profile?.roles.some((role) => role.code === 'owner') && <TaskPublicationReviewPanel branches={data?.branches ?? []} onPublished={() => load(true)} />}<TaskTemplatesSection templates={taskDesignerTemplates} categories={taskCategories} employees={data?.employees ?? []} branches={data?.branches ?? []} onReload={load} /></> : <Unavailable title="الجدول التنظيمي" text="لا تملك صلاحية إدارة الجداول التنظيمية." />)}
      {section === 'report-designer' && (canManageReports ? <ReportDesigner organizationId={profile?.institutionId ?? ''} /> : <Unavailable title="مصمم التقارير" text="لا تملك صلاحية إدارة نماذج التقارير." />)}
      {section === 'reports' && (canViewReports ? <View style={{ gap: 14 }}><ReportSubmissionReviewPanel canReview={permissions.includes('report_submissions.review')} canApprove={permissions.includes('report_submissions.approve')} /><ReportsSection data={data} fmt={fmt} onOpenTasks={() => router.push('/tasks')} canManage={canManageEmployees} institutionId={profile?.institutionId ?? ''} onReportUpdated={updateReportLocally} onReportDeleted={removeReportLocally} /></View> : <Unavailable title="تقارير الموظفين" text="لا تملك صلاحية قراءة تقارير المؤسسة أو مراجعتها." />)}
      {section === 'performance' && (canViewReports ? <PerformanceAnalytics /> : <Unavailable title="إحصائيات ومقارنة الأداء" text="لا تملك صلاحية عرض إحصائيات الأداء." />)}
      {section === 'branches' && (canViewBranches ? <BranchesSection data={data} institutionId={profile?.institutionId ?? ''} canManage={canManageEmployees} onReload={load} /> : <Unavailable title="إدارة الفروع" text="لا تملك صلاحية عرض الفروع." />)}
      {section === 'employees' && (canViewEmployees ? <EmployeesSection data={data} /> : <Unavailable title="الموظفون" text="لا تملك صلاحية عرض الموظفين." />)}
      {section === 'activity' && (canViewActivity ? <ActivitySection data={data} fmt={fmt} /> : <Unavailable title="سجل النشاط" text="لا تملك صلاحية قراءة سجل النشاط." />)}
  </AppShell>;
}

function Overview({ counts, data, fmt, onSection, onSettings, onHR, canDesign, canDesignReports }: { counts: { all: number; new: number; active: number; review: number; late: number; done: number }; data: DashboardData | null; fmt: (v: string | null) => string; onSection: (section: Section) => void; onSettings: () => void; onHR: () => void; canDesign: boolean; canDesignReports: boolean }) { return <>
  <View style={styles.metricsHeader}><Text style={styles.sectionTitle}>ملخص المهام</Text><Text style={styles.metricsHint}>متابعة أعمال المؤسسة</Text></View>
  <View style={styles.metrics}>{[{label:'إجمالي المهام',value:counts.all,tone:'blue',glyph:'▦'},{label:'قيد التنفيذ',value:counts.active,tone:'green',glyph:'▶'},{label:'بانتظار المراجعة',value:counts.review,tone:'amber',glyph:'✓'},{label:'مهام متأخرة',value:counts.late,tone:'red',glyph:'◷'}].map((item) => <View style={[styles.metric, styles['metric_'+item.tone as 'metric_blue']] as any} key={item.label}><Text style={styles.metricGlyph}>{item.glyph}</Text><Text style={styles.metricValue}>{item.value}</Text><Text style={styles.metricLabel}>{item.label}</Text></View>)}</View>
  <View style={styles.moduleHeader}><Text style={styles.sectionTitle}>خدمات الإدارة</Text><Text style={styles.metricsHint}>اختر القسم المطلوب</Text></View>
  <View style={styles.moduleGrid}>
    {[{title:'إدارة المهام',sub:'إنشاء ومتابعة التكليفات',glyph:'▣',section:'tasks' as Section},{title:'التقارير',sub:'تقارير الموظفين ومراجعتها',glyph:'▤',section:'reports' as Section},{title:'إدارة الفروع',sub:'إضافة الفروع وتعديلها',glyph:'⌂',section:'branches' as Section},{title:'إدارة الموظفين',sub:'بيانات الموظفين وحساباتهم',glyph:'♟',section:'employees' as Section},...(canDesign?[{title:'مصمم المهام',sub:'قوالب وخطوات ديناميكية',glyph:'✎',section:'task-designer' as Section}]:[]),...(canDesignReports?[{title:'مصمم التقارير',sub:'إنشاء نماذج التقارير',glyph:'▤',section:'report-designer' as Section}]:[]),{title:'الموارد البشرية',sub:'العقود والدوام والرواتب',glyph:'◫',section:'hr' as Section},{title:'سجل النشاط',sub:'مراجعة الأحداث والمرفقات',glyph:'◷',section:'activity' as Section}].map((item,index)=><Pressable key={item.title} style={styles.moduleCard} onPress={()=>item.section === 'hr' ? onHR() : onSection(item.section)}><View style={[styles.moduleIcon,index%2===0?styles.moduleIconGold:styles.moduleIconBlue]}><Text style={styles.moduleGlyph}>{item.glyph}</Text></View><View style={styles.moduleCopy}><Text style={styles.moduleTitle}>{item.title}</Text><Text style={styles.moduleSubtitle}>{item.sub}</Text></View><Text style={styles.moduleArrow}>‹</Text></Pressable>)}
    <Pressable style={styles.moduleCard} onPress={onSettings}><View style={styles.moduleIcon}><Text style={styles.moduleGlyph}>⚙</Text></View><View style={styles.moduleCopy}><Text style={styles.moduleTitle}>الصلاحيات والإعدادات</Text><Text style={styles.moduleSubtitle}>إدارة حسابات المستخدمين</Text></View><Text style={styles.moduleArrow}>‹</Text></Pressable>
  </View>
  <View style={styles.branchFooter}><Text style={styles.branchFooterTitle}>الفروع المسجلة</Text><Text style={styles.branchFooterValue}>{(data?.branches ?? []).filter((branch)=>branch.isActive).length} فروع نشطة</Text></View>
  <View style={styles.activityPreview}><Text style={styles.sectionTitle}>آخر النشاط</Text>{(data?.activity ?? []).slice(0,3).map((item)=><View style={styles.activityPreviewRow} key={item.id}><Text style={styles.cardTitle}>{item.action}</Text><Text style={styles.meta}>{fmt(item.createdAt)}</Text></View>)}{!(data?.activity ?? []).length&&<Text style={styles.muted}>لا توجد أنشطة حديثة.</Text>}</View>
</>; }

function TasksSection({ data, designerTemplates, canDesign, showCreate, setShowCreate, draft, setDraft, createTask, fmt, onOpenTasks, canManage, institutionId, onReload, onTaskUpdated, onTaskDeleted, onTaskRestored, onDesignerSave, onDesignerSend }: any) {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [edits, setEdits] = useState<Record<string, { title: string; description: string }>>({});
  const [busyMutation, setBusyMutation] = useState<string | null>(null);
  const [showDesigner, setShowDesigner] = useState(false);
  const tasks = data?.tasks ?? [];
  const statusOptions = [
    ['all','الكل'],['new','جديدة'],['received','مستلمة'],['in_progress','قيد التنفيذ'],
    ['report_submitted','بانتظار المراجعة'],['completed_approved','مكتملة'],['late','متأخرة'],['cancelled','ملغاة'],
  ];
  const filtered = tasks.filter((task: any) =>
    (statusFilter === 'all' || task.status === statusFilter) &&
    (!search.trim() || `${task.title ?? ''} ${task.branchName ?? ''}`.toLocaleLowerCase('ar').includes(search.trim().toLocaleLowerCase('ar')))
  );
  const counts = {
    all: tasks.length,
    active: tasks.filter((task: any) => ['new','received','in_progress','on_hold'].includes(task.status)).length,
    review: tasks.filter((task: any) => task.status === 'report_submitted').length,
    late: tasks.filter((task: any) => task.status === 'late' || (!!task.dueAt && new Date(task.dueAt) < new Date() && !['completed_approved','cancelled'].includes(task.status))).length,
  };
  const employeesForDraft = (data?.employees ?? []).filter((employee: any) => employee.active && Boolean(employee.userId) && (employee.assignments ?? []).some((assignment: any) => assignment.roleCode === draft.roleCode && (!draft.branchId || assignment.branchId === draft.branchId)));
  return <View style={{ gap: 12 }}>
    <View style={styles.taskManagementHero}>
      <View style={styles.taskManagementHeroCopy}>
        <Text style={styles.taskManagementEyebrow}>إدارة وتنظيم العمل</Text>
        <Text style={styles.taskManagementTitle}>المهام والتكليفات</Text>
        <Text style={styles.taskManagementSubtitle}>أنشئ التكليفات، تابع التنفيذ، وراجع التقارير من مكان واحد</Text>
      </View>
      <View style={styles.taskManagementHeroIcon}><Text style={styles.taskManagementHeroGlyph}>▣</Text></View>
    </View>
    <View style={styles.taskSummaryGrid}>
      {[{label:'كل المهام',value:counts.all,tone:'blue'},{label:'قيد العمل',value:counts.active,tone:'green'},{label:'بانتظار المراجعة',value:counts.review,tone:'gold'},{label:'متأخرة',value:counts.late,tone:'red'}].map((item:any)=>
        <View key={item.label} style={[styles.taskSummaryCard, item.tone==='green'?styles.taskSummaryGreen:item.tone==='gold'?styles.taskSummaryGold:item.tone==='red'?styles.taskSummaryRed:styles.taskSummaryBlue]}>
          <Text style={styles.taskSummaryValue}>{item.value}</Text><Text style={styles.taskSummaryLabel}>{item.label}</Text>
        </View>
      )}
    </View>
    <View style={styles.taskSectionHeading}>
      <View style={styles.taskHeadingCopy}><Text style={styles.sectionTitle}>قائمة التكليفات</Text><Text style={styles.taskSectionHint}>المهام المسجلة في المؤسسة</Text></View>
      <View style={styles.actionsRow}>{canDesign ? <Pressable style={styles.taskCreateButton} onPress={() => { setShowDesigner(!showDesigner); setShowCreate(false); }}><Text style={styles.taskCreateButtonText}>{showDesigner ? 'إغلاق النموذج' : '＋ من مصمم المهام — إنشاء تكليف'}</Text></Pressable> : <Pressable style={styles.taskCreateButton} onPress={() => { setShowCreate(!showCreate); setShowDesigner(false); }}><Text style={styles.taskCreateButtonText}>{showCreate?'إغلاق':'＋ إنشاء تكليف'}</Text></Pressable>}</View>
    </View>
    {canDesign && showDesigner && <View style={styles.card}><Text style={styles.formTitle}>إرسال مهمة من المصمم</Text><Text style={styles.copy}>صمّم المهمة واحفظها ثم أرسلها للمراجعة والاعتماد الإداري؛ وبعد الاعتماد تصل تلقائياً للموظفين المطابقين للتصنيف والفرع.</Text><OrganizationalTaskDesigner employees={data?.employees ?? []} branches={data?.branches ?? []} canManage={canManage} onSave={onDesignerSave} onSend={onDesignerSend} onList={onReload} /></View>}
    {showCreate && <View style={styles.form}>
      <View style={styles.formTitleRow}><Text style={styles.formTitle}>بيانات التكليف الجديد</Text><Text style={styles.formStep}>1 · التفاصيل</Text></View>
      {[['title', 'عنوان المهمة'], ['description', 'وصف وتعليمات التنفيذ']].map(([key, label]) => <TextInput key={key} style={styles.input} placeholder={label} value={draft[key]} onChangeText={(value) => setDraft({ ...draft, [key]: value })} multiline={key === 'description'} />)}
      <AdenDeadlinePicker date={draft.dueDate} time={draft.dueTime} onChange={(dueDate, dueTime) => setDraft({ ...draft, dueDate, dueTime })} />
      <Text style={styles.fieldLabel}>التصنيف الوظيفي المستهدف</Text>
      <View style={styles.choices}>{roleCodes.map((role) => <Pressable key={role} style={[styles.choice, draft.roleCode === role && styles.choiceSelected]} onPress={() => setDraft({ ...draft, roleCode: role, branchId: '', assignedEmployeeId: '', templateId: '', reportTemplateId: designerTemplates.some((item: ReportTemplate) => item.id === draft.reportTemplateId && item.role_code === role) ? draft.reportTemplateId : '' })}><Text style={draft.roleCode === role ? styles.choiceSelectedText : styles.choiceText}>{roleLabel(role)}</Text></Pressable>)}</View>
      <Text style={styles.fieldLabel}>الفرع</Text>
      <View style={styles.choices}><Pressable style={[styles.choice, !draft.branchId && styles.choiceSelected]} onPress={() => setDraft({ ...draft, branchId: '', assignedEmployeeId: '' })}><Text style={!draft.branchId ? styles.choiceSelectedText : styles.choiceText}>كل الفروع</Text></Pressable>{(data?.branches ?? []).map((branch: any) => <Pressable key={branch.id} style={[styles.choice, draft.branchId === branch.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, branchId: branch.id, assignedEmployeeId: '' })}><Text style={draft.branchId === branch.id ? styles.choiceSelectedText : styles.choiceText}>{branch.name}</Text></Pressable>)}</View>
      <Text style={styles.fieldLabel}>الموظف المستلم</Text>
      <View style={styles.choices}>{employeesForDraft.map((employee: any) => <Pressable key={employee.id} style={[styles.choice, draft.assignedEmployeeId === employee.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, assignedEmployeeId: employee.id })}><Text style={draft.assignedEmployeeId === employee.id ? styles.choiceSelectedText : styles.choiceText}>{employee.name} · رقم {employee.employeeNo ?? 'غير مسجل'}</Text></Pressable>)}</View>
      {!employeesForDraft.length && <Text style={styles.error}>لا يوجد موظف نشط مرتبط بحساب دخول بهذا التصنيف والفرع. اختر «كل الفروع» أو راجع تعيين الدور والفرع.</Text>}
      <Text style={{ color: '#52687a', backgroundColor: '#eef5f7', borderRadius: 10, padding: 10, textAlign: 'right', lineHeight: 21 }}>حقول التقرير المعتمدة للدور المحدد تُرسل تلقائياً إلى تبويب «إعداد التقارير» لدى الموظف، ولا تحتاج إلى ربط يدوي داخل المهمة.</Text>
      <Pressable style={styles.primary} onPress={() => void createTask()}><Text style={styles.primaryText}>حفظ ونشر التكليف</Text></Pressable>
    </View>}
    <View style={styles.taskSearchBox}><Text style={styles.taskSearchGlyph}>⌕</Text><TextInput style={styles.taskSearchInput} value={search} onChangeText={setSearch} placeholder="ابحث بعنوان المهمة أو الفرع..." placeholderTextColor="#8493a4" /></View>
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.taskStatusFilters}>
      {statusOptions.map(([value,label])=><Pressable key={value} style={[styles.taskStatusChip,statusFilter===value&&styles.taskStatusChipActive]} onPress={()=>setStatusFilter(value)}><Text style={[styles.taskStatusChipText,statusFilter===value&&styles.taskStatusChipTextActive]}>{label}</Text></Pressable>)}
    </ScrollView>
    {filtered.length ? filtered.map((task: any) => {
      const late = task.status === 'late' || (!!task.dueAt && new Date(task.dueAt) < new Date() && !['completed_approved','cancelled'].includes(task.status));
      return <View style={styles.taskListCard} key={task.id}>
        <View style={styles.taskListTop}><View style={[styles.taskStatusDot,{backgroundColor:late?'#c84b4b':task.status==='completed_approved'?'#29936a':task.status==='report_submitted'?'#d49a27':'#3977b8'}]} /><Text style={styles.taskListTitle}>{task.title}</Text><Text style={[styles.taskStatusBadge,late?styles.taskStatusLate:task.status==='completed_approved'?styles.taskStatusDone:task.status==='report_submitted'?styles.taskStatusReview:styles.taskStatusActive]}>{late?'متأخرة':statusLabel(task.status)}</Text></View>
        <Text style={styles.taskListMeta}>{task.branchName || 'كل الفروع'} · {task.assignedTo ? 'مُسندة لموظف' : 'بانتظار الإسناد'} · {priorityLabels[task.priority] || task.priority}</Text>
        <Text style={styles.taskListMeta}>الوصول: {task.status === 'new' ? 'تم الإرسال — بانتظار فتح الموظف' : task.status === 'received' ? 'تم الاستلام' : task.status === 'in_progress' ? 'تم الفتح وبدأ التنفيذ' : task.status === 'report_submitted' ? 'تم التنفيذ وإرسال التقرير' : statusLabel(task.status)}</Text><View style={styles.taskListFooter}><Text style={styles.taskDueLabel}>الموعد: {fmt(task.dueAt)}</Text><Text style={styles.taskIdLabel}>#{String(task.id).slice(0,8)}</Text></View>
        {canManage && <>
          <TextInput style={styles.input} placeholder="تعديل عنوان المهمة" value={edits[task.id]?.title ?? task.title} onChangeText={(value) => setEdits((current) => ({ ...current, [task.id]: { title: value, description: current[task.id]?.description ?? task.description ?? '' } }))} />
          <TextInput style={styles.input} placeholder="تعديل وصف المهمة" value={edits[task.id]?.description ?? task.description ?? ''} onChangeText={(value) => setEdits((current) => ({ ...current, [task.id]: { title: current[task.id]?.title ?? task.title, description: value } }))} multiline />
          <Pressable disabled={busyMutation === task.id} style={styles.secondary} onPress={() => void (async () => { setBusyMutation(task.id); try { const title = edits[task.id]?.title ?? task.title; const description = edits[task.id]?.description ?? task.description ?? ''; await updateManagedTask(institutionId, task.id, title, description, task.dueAt); onTaskUpdated(task.id, { title, description }); } catch (error) { Alert.alert('تعذر التعديل', (error as Error)?.message ?? 'تحقق من الصلاحية والاتصال.'); } finally { setBusyMutation(null); } })()}><Text style={styles.secondaryText}>{busyMutation === task.id ? 'جارٍ الحفظ…' : 'حفظ تعديل المهمة'}</Text></Pressable>
          <Pressable disabled={busyMutation === task.id} style={styles.dangerButton} onPress={() => Alert.alert('إزالة المهمة', 'ستتم إزالة المهمة من القوائم النشطة مع الاحتفاظ بسجل النشاط الإداري لأغراض التدقيق. هل تريد المتابعة؟', [{ text: 'إلغاء', style: 'cancel' }, { text: 'إزالة', style: 'destructive', onPress: () => void (async () => { setBusyMutation(task.id); onTaskDeleted(task.id); try { await deleteManagedTask(institutionId, task.id); } catch (error) { onTaskRestored(task); Alert.alert('تعذر إزالة المهمة', (error as Error)?.message ?? 'تعذر تنفيذ العملية. أُعيدت المهمة إلى القائمة.'); } finally { setBusyMutation(null); } })() }])}><Text style={styles.dangerText}>إزالة المهمة</Text></Pressable>
        </>}
      </View>;
    }) : <View style={styles.taskEmpty}><Text style={styles.taskEmptyGlyph}>▤</Text><Text style={styles.taskEmptyTitle}>لا توجد مهام مطابقة</Text><Text style={styles.taskEmptyText}>{tasks.length?'جرّب تغيير البحث أو حالة المهمة.':'ابدأ بإنشاء أول تكليف للمؤسسة.'}</Text></View>}
    <Pressable style={styles.taskOpenExecution} onPress={onOpenTasks}><Text style={styles.taskOpenExecutionText}>فتح شاشة تنفيذ المهام والتقارير والمرفقات ←</Text></Pressable>
  </View>;
}
function ReportsSection({ data, fmt, onOpenTasks, canManage, institutionId, onReportUpdated, onReportDeleted }: { data: DashboardData | null; fmt: (value: string | null) => string; onOpenTasks: () => void; canManage: boolean; institutionId: string; onReportUpdated: (reportId: string, patch: Partial<DashboardData['reports'][number]>) => void; onReportDeleted: (reportId: string) => void }) {
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState<'all' | 'submitted' | 'approved' | 'returned'>('all');
  const [exporting, setExporting] = useState(false);
  const [reviewNote, setReviewNote] = useState('');
  const reports = (data?.reports ?? []).filter((report) => status === 'all' || report.status === status).filter((report) => !query.trim() || `${report.taskTitle} ${report.employeeName}`.toLocaleLowerCase('ar').includes(query.trim().toLocaleLowerCase('ar')));
  const statusLabel = (value: string) => value === 'submitted' ? 'بانتظار المراجعة' : value === 'approved' ? 'معتمد' : 'معاد للتعديل';
  async function exportCsv() { if (!reports.length || exporting || !FileSystem.cacheDirectory) return; setExporting(true); try { const headers = ['الحالة', 'المهمة', 'الموظف', 'تاريخ الإرسال', 'الحقول والقيم']; const quote = (value: unknown) => `"${String(value ?? '').replaceAll('"', '""')}"`; const rows = reports.map((report) => [statusLabel(report.status), report.taskTitle, report.employeeName, fmt(report.submittedAt), Object.entries(report.values).map(([key, value]) => `${key}: ${formatReportValue(value)}`).join(' | ')].map(quote).join(',')); const uri = `${FileSystem.cacheDirectory}employee-reports.csv`; await FileSystem.writeAsStringAsync(uri, `\uFEFF${[headers.map(quote).join(','), ...rows].join('\n')}`); await Share.share({ title: 'تقارير الموظفين', url: uri, message: 'تقرير الموظفين المصدّر بصيغة CSV' }); } finally { setExporting(false); } }
  return <><Text style={styles.sectionTitle}>تقارير الموظفين</Text><Text style={styles.copy}>هنا تظهر تقارير المهام وتقارير الدور اليومية المستقلة في قائمة موحدة. تقارير الدور لا ترتبط بمهمة أو بمصمم التقرير الديناميكي.</Text><Pressable disabled={!reports.length || exporting} style={styles.secondary} onPress={() => void exportCsv()}><Text style={styles.secondaryText}>{exporting ? 'جارٍ تجهيز التصدير…' : 'تصدير CSV وفتحه في Excel'}</Text></Pressable><TextInput style={styles.input} value={query} onChangeText={setQuery} placeholder="ابحث باسم الموظف أو التقرير…" accessibilityLabel="البحث في التقارير" /><View style={styles.choices}>{([['all', 'كل التقارير'], ['submitted', 'بانتظار المراجعة'], ['approved', 'معتمدة'], ['returned', 'معادة للتعديل']] as const).map(([value, label]) => <Pressable key={value} accessibilityRole="button" accessibilityState={{ selected: status === value }} style={[styles.choice, status === value && styles.choiceSelected]} onPress={() => setStatus(value)}><Text style={status === value ? styles.choiceSelectedText : styles.choiceText}>{label}</Text></Pressable>)}</View>{reports.length ? reports.map((report) => <View style={styles.card} key={report.id}><View style={styles.taskLine}><Text style={styles.cardTitle}>{statusLabel(report.status)}</Text><Text style={styles.badge}>{report.source === 'role' ? 'تقرير دور' : report.status}</Text></View><Text style={styles.meta}>{report.source === 'role' ? `التقرير: ${report.taskTitle} · الدور: ${roleLabel(report.roleCode ?? '')}${report.branchName ? ` · الفرع: ${report.branchName}` : ''}` : `المهمة: ${report.taskTitle}`}</Text><Text style={styles.meta}>الموظف: {report.employeeName} · {fmt(report.submittedAt)}</Text>{report.fields.length ? report.fields.map((field) => <View style={styles.reportValueRow} key={`${report.id}-${field.key}`}><Text style={styles.reportValueLabel}>{field.label}</Text><Text style={styles.reportValue}>{formatReportValue(report.values[field.key])}</Text></View>) : Object.entries(report.values).map(([key, value]) => <View style={styles.reportValueRow} key={`${report.id}-${key}`}><Text style={styles.reportValueLabel}>{key}</Text><Text style={styles.reportValue}>{formatReportValue(value)}</Text></View>)}{!!report.reviewNote && <Text style={styles.warning}>ملاحظة المراجع: {report.reviewNote}</Text>}{report.source === 'role' ? canManage && report.status === 'submitted' && <><TextInput style={styles.input} value={reviewNote} onChangeText={setReviewNote} placeholder="ملاحظة المراجعة" /><Pressable style={styles.primary} onPress={() => void (async () => { await reviewEmployeeRoleReport(report.id, 'approved', reviewNote || null); onReportUpdated(report.id, { status: 'approved', reviewNote: reviewNote || null }); setReviewNote(''); })()}><Text style={styles.primaryText}>اعتماد تقرير الدور</Text></Pressable><Pressable disabled={!reviewNote.trim()} style={styles.secondary} onPress={() => void (async () => { await reviewEmployeeRoleReport(report.id, 'returned', reviewNote); onReportUpdated(report.id, { status: 'returned', reviewNote }); setReviewNote(''); })()}><Text style={styles.secondaryText}>إرجاع للتعديل</Text></Pressable></> : <Pressable style={styles.secondary} onPress={onOpenTasks}><Text style={styles.secondaryText}>فتح المهمة للمراجعة والاعتماد</Text></Pressable>}{canManage && report.source === 'task' && <Pressable style={styles.dangerButton} onPress={() => Alert.alert('حذف التقرير نهائيًا', 'سيُحذف التقرير المرفوع وقيمه نهائيًا وتعود المهمة للتنفيذ. هل تريد المتابعة؟', [{ text: 'إلغاء', style: 'cancel' }, { text: 'حذف نهائي', style: 'destructive', onPress: () => void (async () => { try { await deleteManagedReport(institutionId, report.id); onReportDeleted(report.id); } catch (error) { Alert.alert('تعذر الحذف', (error as Error)?.message ?? 'تحقق من الصلاحية.'); } })() }])}><Text style={styles.dangerText}>حذف التقرير نهائيًا</Text></Pressable>}</View>) : <Text style={styles.muted}>لا توجد تقارير مطابقة للبحث أو التصفية.</Text>}</>;
}
function formatReportValue(value: unknown) { if (value === null || value === undefined || value === '') return 'لم يُعبّأ'; if (typeof value === 'object') return JSON.stringify(value); return String(value); }
function BranchesSection({ data, institutionId, canManage, onReload }: any) {
  const [code, setCode] = useState('');
  const [name, setName] = useState('');
  const [renames, setRenames] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [branchError, setBranchError] = useState('');
  const [branchNotice, setBranchNotice] = useState('');
  async function manage(action: 'create' | 'update' | 'archive' | 'activate' | 'delete', branchId?: string, branchName?: string) {
    if (!supabase) return;
    setBusy(true); setBranchError(''); setBranchNotice('');
    try {
      if (action === 'delete') {
        await deleteManagedBranch(institutionId, branchId ?? '');
        setBranchNotice('تم حذف الفرع نهائيًا.');
        await onReload(true);
        return;
      }
      const { error } = await supabase.functions.invoke('employee-code-auth', { body: {
        action: 'manage_branch', branchAction: action, branchId: branchId ?? null,
        code: action === 'create' ? code.trim().toUpperCase() : null,
        name: action === 'create' ? name.trim() : branchName?.trim() ?? null,
      }});
      if (error) throw error;
      setBranchNotice(action === 'create' ? 'تمت إضافة الفرع.' : action === 'update' ? 'تم تعديل اسم الفرع.' : action === 'archive' ? 'تمت أرشفة الفرع وإيقاف استخدامه.' : 'تمت إعادة تفعيل الفرع.')
      if (action === 'create') { setCode(''); setName(''); }
      await onReload();
    } catch (error) {
      const status = (error as any)?.context?.status;
      setBranchError(status === 403 ? 'لا تملك صلاحية إدارة الفروع.' : 'تعذر تنفيذ العملية. تحقق من صلاحية الفرع أو تكرار الكود.');
    } finally { setBusy(false); }
  }
  return <>
    <Text style={styles.sectionTitle}>إدارة الفروع</Text>
    <Text style={styles.copy}>يمكن إضافة الفروع وتعديل أسمائها وأرشفتها. الأرشفة توقف استخدام الفرع الجديد وتحافظ على المهام والسجلات السابقة.</Text>
    {!!branchError && <Text style={styles.error}>{branchError}</Text>}
    {!!branchNotice && <Text style={styles.notice}>{branchNotice}</Text>}
    {canManage && <View style={styles.form}>
      <Text style={styles.fieldLabel}>إضافة فرع جديد</Text>
      <TextInput style={styles.input} placeholder="كود الفرع مثل BRANCH-2" autoCapitalize="characters" value={code} onChangeText={setCode}/>
      <TextInput style={styles.input} placeholder="اسم الفرع" value={name} onChangeText={setName}/>
      <Pressable disabled={busy || !code.trim() || !name.trim()} style={styles.primary} onPress={() => void manage('create')}><Text style={styles.primaryText}>{busy ? 'جارٍ الحفظ…' : 'إضافة الفرع'}</Text></Pressable>
    </View>}
    {(data?.branches ?? []).map((branch: any) => <View style={styles.card} key={branch.id}>
      <Text style={styles.cardTitle}>{branch.name}</Text>
      <Text style={styles.meta}>الكود: {branch.code} · المستوى: {branch.level || 'غير محدد'} · {branch.isActive ? 'نشط' : 'مؤرشف'}</Text>
      {canManage && branch.isActive && <>
        <TextInput style={styles.input} placeholder="الاسم الجديد للفرع" value={renames[branch.id] ?? branch.name} onChangeText={(value) => setRenames((current) => ({...current,[branch.id]:value}))}/>
        <Pressable disabled={busy || !(renames[branch.id] ?? branch.name).trim()} style={styles.secondary} onPress={() => void manage('update',branch.id,renames[branch.id] ?? branch.name)}><Text style={styles.secondaryText}>حفظ الاسم</Text></Pressable>
        <Pressable disabled={busy} style={styles.secondary} onPress={() => Alert.alert('أرشفة الفرع','سيتم إيقاف الفرع مع الاحتفاظ بسجلاته ومهامه. هل تريد المتابعة؟',[{text:'إلغاء',style:'cancel'},{text:'أرشفة',style:'destructive',onPress:()=>void manage('archive',branch.id)}])}><Text style={styles.secondaryText}>أرشفة الفرع</Text></Pressable>
      </>}
      {canManage && branch.isActive && <Pressable disabled={busy} style={styles.dangerButton} onPress={() => Alert.alert('حذف الفرع نهائيًا', 'لا يمكن التراجع عن حذف الفرع. إذا كان مرتبطًا بمهام أو موظفين سيرفض النظام العملية. هل تريد المتابعة؟', [{ text: 'إلغاء', style: 'cancel' }, { text: 'حذف نهائي', style: 'destructive', onPress: () => void manage('delete', branch.id) }])}><Text style={styles.dangerText}>حذف الفرع نهائيًا</Text></Pressable>}
      {canManage && !branch.isActive && <Pressable disabled={busy} style={styles.secondary} onPress={() => void manage('activate',branch.id)}><Text style={styles.secondaryText}>إعادة تفعيل الفرع</Text></Pressable>}
    </View>)}
  </>;
}
function EmployeesSection({ data }: any) { return <><Text style={styles.sectionTitle}>الموظفون والتصنيفات الوظيفية</Text>{(data?.employees ?? []).map((employee: any) => <View style={styles.card} key={employee.id}><Text style={styles.cardTitle}>{employee.name}</Text><Text style={styles.meta}>{employee.employeeNo || 'بدون رقم'} · {employee.active ? 'نشط' : 'غير نشط'}</Text><Text style={styles.meta}>{employee.roles.length ? employee.roles.map(roleLabel).join('، ') : 'دون تصنيف'} · {employee.branchName ?? 'دون فرع'}</Text></View>)}</>; }
function ActivitySection({ data, fmt }: any) { return <><Text style={styles.sectionTitle}>سجل النشاط والمرفقات</Text><Text style={styles.copy}>السجل يعرض الأحداث المسموح بها حسب RLS. إدارة المرفقات تتم من داخل تقرير المهمة.</Text>{(data?.activity ?? []).map((item: any) => <View style={styles.row} key={item.id}><Text style={styles.cardTitle}>{item.action}</Text><Text style={styles.meta}>المهمة {item.taskId.slice(0, 8)} · {fmt(item.createdAt)}</Text></View>)}</>; }
function Unavailable({ title, text }: { title: string; text: string }) { return <View style={styles.unavailable}><Text style={styles.sectionTitle}>{title}</Text><Text style={styles.copy}>{text}</Text></View>; }

function TaskTemplatesSection({ templates, categories, employees, branches, onReload }: { templates: StoredTaskTemplate[]; categories: TaskCategoryRow[]; employees: NonNullable<DashboardData>['employees']; branches: NonNullable<DashboardData>['branches']; onReload: () => Promise<void> }) {
  const [selected, setSelected] = useState<StoredTaskTemplate | null>(null);
  const [editing, setEditing] = useState(false);
  const [saveError, setSaveError] = useState('');
  const visibleTemplates = Array.from(new Map([...templates]
    .sort((left, right) => Number(right.isActive) - Number(left.isActive) || right.version - left.version)
    .map((template) => [`${template.roleCode}:${template.title.trim().toLocaleLowerCase('ar')}`, template] as const)).values());
  async function save(draft: TaskTemplateDraft) {
    try {
      setSaveError('');
      const saved = await saveTaskDesignerTemplate(draft, categories);
      await onReload();
      return saved;
    } catch (cause) {
      setSaveError(friendlyDataError(cause, 'تعذر حفظ قالب المهمة. تحقق من الصلاحيات ونماذج التقارير المعتمدة.'));
      throw cause;
    }
  }
  async function sendDirectly(draft: TaskTemplateDraft, branchId: string | null, dueAt: string) {
    if (!draft.id) throw new Error('task_template_save_response_invalid');
    await submitTaskPublicationRequest(draft.id, branchId, dueAt);
    await onReload();
    setSelected(null);
    setEditing(false);
  }
  return <View style={{ gap: 12 }}>
    <View style={styles.card}><Text style={styles.sectionTitle}>مصمم الجدول التنظيمي للمهام</Text><Text style={styles.copy}>أنشئ جدول الدوام، المهام اليومية، المسؤوليات، مؤشرات الأداء، متطلبات الإثبات وحقول تقرير المهمة. حقول التقرير التي تضيفها هنا تبقى داخل قالب المهمة وتصل للموظف في تبويب «إعداد التقارير» المرتبط بالمهمة، دون إنشاء نموذج في «مصمم التقارير».</Text><Pressable style={styles.primary} onPress={() => { setSelected(null); setEditing(true); setSaveError(''); }}><Text style={styles.primaryText}>جدول تنظيمي جديد</Text></Pressable></View>
    {visibleTemplates.map((template) => <View key={template.id} style={styles.templateCard}>
      <View style={styles.templateHeader}>
        <View style={styles.templateHeaderCopy}><Text style={styles.templateTitle}>{template.title}</Text><Text style={styles.templateRole}>{roleLabel(template.roleCode)}</Text></View>
        <Text style={[styles.templateStatus, template.isActive ? styles.templateStatusActive : styles.templateStatusInactive]}>{template.isActive ? 'نشط' : 'غير نشط'}</Text>
      </View>
      <View style={styles.templateMetaRow}><View style={styles.templateMetaChip}><Text style={styles.templateMetaValue}>{template.steps.length}</Text><Text style={styles.templateMetaLabel}>خطوات</Text></View><View style={styles.templateMetaChip}><Text style={styles.templateMetaValue}>{template.reportFields.length}</Text><Text style={styles.templateMetaLabel}>حقول التقرير</Text></View><View style={styles.templateMetaChip}><Text style={styles.templateMetaValue}>{template.version}</Text><Text style={styles.templateMetaLabel}>الإصدار</Text></View></View>
      <View style={styles.templateActions}>
        <Pressable style={styles.templateEditButton} onPress={() => { setSelected(template); setEditing(true); setSaveError(''); }}><Text style={styles.templateEditText}>تعديل القالب</Text></Pressable>
        <Pressable style={styles.templateDeleteButton} onPress={() => Alert.alert('حذف القالب نهائياً', 'سيُحذف قالب الجدول وبياناته من مكتبة القوالب نهائياً. ستبقى المهام السابقة وتقاريرها محفوظة دون ارتباط بالقالب. لا يمكن التراجع عن هذا الإجراء.', [{ text: 'إلغاء', style: 'cancel' }, { text: 'حذف نهائي', style: 'destructive', onPress: () => void (async () => { try { setSaveError(''); await deleteTaskDesignerTemplate(template.id!); setSelected(null); setEditing(false); await onReload(); } catch (cause) { setSaveError(friendlyDataError(cause, 'تعذر حذف القالب نهائياً.')); } })() }])}><Text style={styles.templateDeleteText}>حذف نهائي</Text></Pressable>
      </View>
    </View>)}
    {!!saveError && <Text accessibilityRole="alert" style={styles.error}>{saveError}</Text>}
    {editing && <OrganizationalTaskDesigner key={selected?.id ?? 'new-organizational-schedule'} initialTemplate={selected ?? undefined} employees={employees} branches={branches} canManage={true} onSave={save} onSend={sendDirectly} onList={onReload} />}
    {visibleTemplates.length === 0 && <Text style={styles.muted}>لا توجد قوالب بعد؛ أنشئ قالبًا جديدًا للبدء.</Text>}
  </View>;
}

const styles = StyleSheet.create({
  shellActions: { flexDirection:'row-reverse', alignItems:'center', justifyContent:'space-between', gap:8 },
  brandHeader: { flexDirection:'row-reverse', alignItems:'center', justifyContent:'space-between', paddingVertical:10, paddingHorizontal:2, minHeight:82 },
  brandIdentity: { flexDirection:'row-reverse', alignItems:'center', flex:1, gap:10 },
  brandLogo: { width:68, height:68, borderRadius:18, backgroundColor:'#fff', borderWidth:1, borderColor:'#e2e9f2' },
  brandTitles: { flex:1, alignItems:'flex-end' },
  brandName: { color:'#103967', fontSize:24, fontWeight:'900', textAlign:'right' },
  brandSubtitle: { color:'#17324d', fontSize:14, fontWeight:'800', textAlign:'right', marginTop:1 },
  brandMotto: { color:'#b57b08', fontSize:12, fontWeight:'700', textAlign:'right', marginTop:4 },
  headerActions: { flexDirection:'row-reverse', alignItems:'center', gap:7 },
  notificationButton: { width:42, height:42, borderRadius:14, backgroundColor:'#123b69', alignItems:'center', justifyContent:'center' },
  signOutButton: { minHeight:42, borderRadius:12, borderWidth:1, borderColor:'#b55248', backgroundColor:'#fff', paddingHorizontal:10, alignItems:'center', justifyContent:'center' },
  signOutButtonText: { color:'#a8443d', fontSize:12, fontWeight:'800' },
  notificationGlyph: { color:'#fff', fontSize:25, fontWeight:'900' },
  welcomeBanner: { minHeight:108, borderRadius:20, backgroundColor:'#123b69', padding:17, flexDirection:'row-reverse', alignItems:'center', gap:13, borderBottomWidth:4, borderBottomColor:'#e7ae28', shadowColor:'#102f52', shadowOpacity:0.12, shadowRadius:9, shadowOffset:{width:0,height:4}, elevation:3 },
  welcomeAvatar: { width:62, height:62, borderRadius:31, backgroundColor:'#e8f0f8', borderWidth:3, borderColor:'#d7e4f2', alignItems:'center', justifyContent:'center' },
  avatarGlyph: { color:'#173e6d', fontSize:38, lineHeight:44 },
  welcomeText: { flex:1, alignItems:'flex-end' },
  welcomeTitle: { color:'#fff', fontSize:21, fontWeight:'900', textAlign:'right' },
  welcomeRole: { color:'#f4c64d', fontSize:15, fontWeight:'800', marginTop:6 },
  metricsHeader: { flexDirection:'row-reverse', alignItems:'center', justifyContent:'space-between', marginTop:6 },
  metricsHint: { color:'#8493a4', fontSize:11, textAlign:'right' },
  moduleHeader: { flexDirection:'row-reverse', alignItems:'center', justifyContent:'space-between', marginTop:8 },
  metric_blue: { backgroundColor:'#e6f0ff', borderColor:'#b9d2f5', borderBottomColor:'#477bb8' },
  metric_green: { backgroundColor:'#e3f4ee', borderColor:'#bde4d5', borderBottomColor:'#31916a' },
  metric_amber: { backgroundColor:'#fff1df', borderColor:'#f0d8b4', borderBottomColor:'#d59a24' },
  metric_red: { backgroundColor:'#ffeaeb', borderColor:'#f3c9ce', borderBottomColor:'#c65c63' },
  metricGlyph: { color:'#174779', fontSize:20, fontWeight:'900' },
  moduleGrid: { flexDirection:'row-reverse', flexWrap:'wrap', gap:9, justifyContent:'space-between' },
  taskManagementHero:{backgroundColor:'#103967',borderRadius:20,padding:17,flexDirection:'row-reverse',alignItems:'center',gap:12,borderBottomWidth:4,borderBottomColor:'#e7ae28'},
  taskManagementHeroCopy:{flex:1,alignItems:'flex-end',gap:4},
  taskManagementEyebrow:{color:'#f4c64d',fontSize:12,fontWeight:'800'},
  taskManagementTitle:{color:'#fff',fontSize:23,fontWeight:'900',textAlign:'right'},
  taskManagementSubtitle:{color:'#dce7f2',fontSize:12,lineHeight:19,textAlign:'right'},
  taskManagementHeroIcon:{width:54,height:54,borderRadius:17,backgroundColor:'#fff2d7',alignItems:'center',justifyContent:'center'},
  taskManagementHeroGlyph:{color:'#173e6d',fontSize:30,fontWeight:'900'},
  taskSummaryGrid:{flexDirection:'row-reverse',gap:7},
  taskSummaryCard:{flex:1,minHeight:78,borderRadius:14,padding:8,alignItems:'center',justifyContent:'center',borderWidth:1},
  taskSummaryBlue:{backgroundColor:'#e8f0fc',borderColor:'#c8d9f1'},
  taskSummaryGreen:{backgroundColor:'#e5f4ed',borderColor:'#c5e6d5'},
  taskSummaryGold:{backgroundColor:'#fff3dc',borderColor:'#f0dfb8'},
  taskSummaryRed:{backgroundColor:'#ffeded',borderColor:'#f0cccc'},
  taskSummaryValue:{color:'#173e6d',fontSize:23,fontWeight:'900'},
  taskSummaryLabel:{color:'#64778a',fontSize:10,fontWeight:'700',textAlign:'center',marginTop:3},
  taskSectionHeading:{flexDirection:'row-reverse',alignItems:'center',justifyContent:'space-between',gap:8},
  taskHeadingCopy:{flex:1,alignItems:'flex-end'},
  taskSectionHint:{color:'#8795a4',fontSize:11,marginTop:3},
  taskCreateButton:{backgroundColor:'#dba52c',borderRadius:12,paddingHorizontal:13,paddingVertical:11},
  taskCreateButtonText:{color:'#17324d',fontSize:13,fontWeight:'900'},
  formTitleRow:{flexDirection:'row-reverse',alignItems:'center',justifyContent:'space-between',marginBottom:3},
  formTitle:{color:'#103967',fontSize:17,fontWeight:'900'},
  formStep:{color:'#a87916',fontSize:11,fontWeight:'800'},
  taskSearchBox:{minHeight:48,backgroundColor:'#fff',borderWidth:1,borderColor:'#d8e2ed',borderRadius:13,flexDirection:'row-reverse',alignItems:'center',paddingHorizontal:12,gap:8},
  taskSearchGlyph:{color:'#b17c12',fontSize:24},
  taskSearchInput:{flex:1,minHeight:44,textAlign:'right',color:'#17324d'},
  taskStatusFilters:{flexDirection:'row-reverse',gap:7,paddingVertical:2},
  taskStatusChip:{borderRadius:18,borderWidth:1,borderColor:'#d2deea',backgroundColor:'#fff',paddingHorizontal:12,paddingVertical:8},
  taskStatusChipActive:{backgroundColor:'#103967',borderColor:'#103967'},
  taskStatusChipText:{color:'#4d6278',fontSize:12,fontWeight:'700'},
  taskStatusChipTextActive:{color:'#fff'},
  taskListCard:{backgroundColor:'#fff',borderWidth:1,borderColor:'#dce5ef',borderRadius:16,padding:13,gap:8,shadowColor:'#17324d',shadowOpacity:0.05,shadowRadius:5,shadowOffset:{width:0,height:2},elevation:1},
  taskListTop:{flexDirection:'row-reverse',alignItems:'center',gap:7},
  taskStatusDot:{width:8,height:8,borderRadius:4},
  taskListTitle:{flex:1,color:'#173e6d',fontSize:15,fontWeight:'900',textAlign:'right'},
  taskStatusBadge:{overflow:'hidden',borderRadius:12,paddingHorizontal:8,paddingVertical:5,fontSize:10,fontWeight:'800'},
  taskStatusLate:{backgroundColor:'#ffebeb',color:'#a83c3c'},
  taskStatusDone:{backgroundColor:'#e5f4ed',color:'#26744e'},
  taskStatusReview:{backgroundColor:'#fff3dc',color:'#946b12'},
  taskStatusActive:{backgroundColor:'#e8f0fc',color:'#315f94'},
  taskListMeta:{color:'#74869a',fontSize:11,textAlign:'right'},
  taskListFooter:{borderTopWidth:1,borderTopColor:'#edf1f5',paddingTop:8,flexDirection:'row-reverse',justifyContent:'space-between',alignItems:'center'},
  taskDueLabel:{color:'#526b82',fontSize:11,fontWeight:'700'},
  taskIdLabel:{color:'#9aa6b3',fontSize:10},
  taskEmpty:{alignItems:'center',backgroundColor:'#fff',borderRadius:16,borderWidth:1,borderColor:'#dce5ef',padding:24,gap:7},
  taskEmptyGlyph:{color:'#b17c12',fontSize:30},
  taskEmptyTitle:{color:'#173e6d',fontSize:16,fontWeight:'900'},
  taskEmptyText:{color:'#8190a1',fontSize:12,textAlign:'center'},
  taskOpenExecution:{backgroundColor:'#e8eef7',borderRadius:13,padding:13,alignItems:'center'},
  taskOpenExecutionText:{color:'#173e6d',fontSize:12,fontWeight:'900'},
  templateCard:{backgroundColor:'#fff',borderRadius:18,borderWidth:1,borderColor:'#dce5ef',padding:15,gap:12,shadowColor:'#17324d',shadowOpacity:0.06,shadowRadius:7,shadowOffset:{width:0,height:3},elevation:2},
  templateHeader:{flexDirection:'row-reverse',alignItems:'flex-start',justifyContent:'space-between',gap:10},
  templateHeaderCopy:{flex:1,alignItems:'flex-end',gap:4},
  templateTitle:{color:'#17324d',fontSize:17,fontWeight:'900',textAlign:'right',lineHeight:25},
  templateRole:{color:'#718394',fontSize:12,fontWeight:'700',textAlign:'right'},
  templateStatus:{borderRadius:16,paddingHorizontal:10,paddingVertical:6,fontSize:12,fontWeight:'900'},
  templateStatusActive:{color:'#23633c',backgroundColor:'#e8f5eb'},
  templateStatusInactive:{color:'#73521f',backgroundColor:'#fff3d8'},
  templateMetaRow:{flexDirection:'row-reverse',gap:8,borderTopWidth:1,borderTopColor:'#edf1f5',paddingTop:10},
  templateMetaChip:{flex:1,backgroundColor:'#f5f8fa',borderRadius:11,paddingVertical:8,alignItems:'center',gap:2},
  templateMetaValue:{color:'#17324d',fontSize:16,fontWeight:'900'},
  templateMetaLabel:{color:'#718394',fontSize:10,fontWeight:'700'},
  templateActions:{flexDirection:'row-reverse',gap:8},
  templateEditButton:{flex:1,minHeight:45,borderRadius:11,backgroundColor:'#e8f0f3',alignItems:'center',justifyContent:'center',paddingHorizontal:8},
  templateEditText:{color:'#17324d',fontWeight:'900',fontSize:13},
  templateDeleteButton:{flex:1,minHeight:45,borderRadius:11,backgroundColor:'#fff0ef',borderWidth:1,borderColor:'#e1a7a2',alignItems:'center',justifyContent:'center',paddingHorizontal:8},
  templateDeleteText:{color:'#a8443d',fontWeight:'900',fontSize:13},
  moduleCard: { width:'48%', minHeight:102, backgroundColor:'#fff', borderRadius:17, borderWidth:1, borderColor:'#d5e0ef', padding:11, flexDirection:'row-reverse', alignItems:'center', gap:7, shadowColor:'#163b65', shadowOpacity:0.07, shadowRadius:7, shadowOffset:{width:0,height:3}, elevation:2 },
  moduleIcon: { width:42, height:42, borderRadius:13, backgroundColor:'#e7effb', alignItems:'center', justifyContent:'center' },
  moduleIconGold: { backgroundColor:'#fff1d6' },
  moduleIconBlue: { backgroundColor:'#e7effb' },
  moduleGlyph: { color:'#153f70', fontSize:24, fontWeight:'900' },
  moduleCopy: { flex:1, alignItems:'flex-end' },
  moduleTitle: { color:'#103967', fontSize:14, fontWeight:'900', textAlign:'right' },
  moduleSubtitle: { color:'#6c7d91', fontSize:10, lineHeight:15, textAlign:'right', marginTop:4 },
  moduleArrow: { color:'#b47b0d', fontSize:23, fontWeight:'900' },
  branchFooter: { backgroundColor:'#e6edf8', borderRadius:15, padding:13, flexDirection:'row-reverse', alignItems:'center', justifyContent:'space-between', marginTop:5 },
  branchFooterTitle: { color:'#173e6d', fontSize:13, fontWeight:'900' },
  branchFooterValue: { color:'#173e6d', fontSize:13, fontWeight:'800' },
  activityPreview: { backgroundColor:'#fff', borderRadius:15, borderWidth:1, borderColor:'#dce5f1', padding:13, gap:9 },
  activityPreviewRow: { borderTopWidth:1, borderTopColor:'#edf1f5', paddingTop:8, gap:3 },
  bottomLabel: { color:'#fff', fontSize:11, fontWeight:'800' },
  bottomLabelActive: { color:'#103967' },
  safe: { flex: 1, backgroundColor: '#f4f7f8' }, content: { padding: 16, paddingTop: 12, paddingBottom: 124, gap: 12 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 }, topbar: { flexDirection: 'row-reverse', justifyContent: 'space-between', alignItems: 'center' }, eyebrow: { color: '#718394', fontWeight: '700', textAlign: 'right' }, title: { color: '#17324d', fontSize: 28, fontWeight: '900', textAlign: 'right', marginTop: 3 }, signOut: { borderWidth: 1, borderColor: '#b55248', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 9 }, signOutText: { color: '#a8443d', fontWeight: '800' }, nav: { flexDirection: 'row-reverse', gap: 8, paddingVertical: 5 }, navChip: { borderWidth: 1, borderColor: '#ccd9df', borderRadius: 20, paddingHorizontal: 12, paddingVertical: 9 }, navChipSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, navText: { color: '#39556a', fontSize: 13 }, navTextSelected: { color: '#fff', fontWeight: '800', fontSize: 13 }, sectionTitle: { color: '#17324d', fontSize: 19, fontWeight: '900', textAlign: 'right', marginTop: 8 }, sectionHeader: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between' }, metrics: { flexDirection: 'row-reverse', flexWrap: 'wrap', justifyContent: 'space-between', rowGap: 10 }, metric: { width: '48%', minHeight: 112, backgroundColor: '#fff', borderRadius: 17, borderWidth: 1, borderBottomWidth: 4, borderColor: '#e0e8eb', paddingVertical: 12, paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center', shadowColor: '#17324d', shadowOpacity: 0.06, shadowRadius: 6, shadowOffset: { width: 0, height: 2 }, elevation: 2 }, metricValue: { color: '#17324d', fontSize: 25, fontWeight: '900' }, metricLabel: { color: '#718394', fontSize: 12, textAlign: 'center', marginTop: 3 }, primary: { minHeight: 48, backgroundColor: '#17324d', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 12 }, primarySmall: { backgroundColor: '#17324d', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10 }, primaryText: { color: '#fff', fontWeight: '800' }, secondary: { minHeight: 46, backgroundColor: '#e8f0f3', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 12 }, secondaryText: { color: '#17324d', fontWeight: '800' }, dangerButton: { minHeight: 44, borderRadius: 10, borderWidth: 1, borderColor: '#b84444', padding: 10, alignItems: 'center', justifyContent: 'center' }, dangerText: { color: '#a84444', fontWeight: '900' }, card: { backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e0e8eb', padding: 14, gap: 5 }, reportValueRow: { backgroundColor: '#f7fafb', borderRadius: 10, borderWidth: 1, borderColor: '#e4ecef', padding: 10, gap: 3, marginTop: 4 }, reportValueLabel: { color: '#39556a', fontSize: 12, fontWeight: '900', textAlign: 'right' }, reportValue: { color: '#17324d', fontSize: 14, lineHeight: 21, textAlign: 'right' }, row: { backgroundColor: '#fff', borderRightWidth: 3, borderRightColor: '#2f6654', borderRadius: 12, padding: 13, gap: 4 }, actionsRow: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7 }, taskLine: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8 }, cardTitle: { color: '#17324d', fontSize: 15, fontWeight: '800', textAlign: 'right' }, badge: { color: '#23633c', backgroundColor: '#e8f5eb', paddingHorizontal: 8, paddingVertical: 5, borderRadius: 12, fontSize: 12 }, meta: { color: '#718394', fontSize: 12, lineHeight: 19, textAlign: 'right' }, copy: { color: '#536978', lineHeight: 22, textAlign: 'right' }, form: { backgroundColor: '#fff', borderRadius: 14, padding: 14, gap: 10, borderWidth: 1, borderColor: '#dce6e9' }, input: { minHeight: 46, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, textAlign: 'right', backgroundColor: '#fbfcfc' }, fieldLabel: { color: '#29475a', fontWeight: '800', textAlign: 'right' }, choices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7 }, choice: { borderWidth: 1, borderColor: '#ccd9df', borderRadius: 18, paddingHorizontal: 10, paddingVertical: 8 }, choiceSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, choiceText: { color: '#39556a', fontSize: 12 }, choiceSelectedText: { color: '#fff', fontWeight: '800', fontSize: 12 }, error: { color: '#a8443d', backgroundColor: '#fff0ef', borderRadius: 10, padding: 11, textAlign: 'right', lineHeight: 21 }, notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 10, padding: 11, textAlign: 'right' }, warning: { color: '#8a5b16', backgroundColor: '#fff4d7', borderRadius: 10, padding: 10, textAlign: 'right', lineHeight: 20 }, muted: { color: '#718394', textAlign: 'right', paddingVertical: 10 }, unavailable: { backgroundColor: '#fff7e8', borderColor: '#efddb7', borderWidth: 1, borderRadius: 14, padding: 15, gap: 8 }, settings: { minHeight: 46, borderWidth: 1, borderColor: '#17324d', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 11, marginTop: 8 }, settingsText: { color: '#17324d', fontWeight: '800' } });
