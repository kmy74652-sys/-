import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Image, Pressable, RefreshControl, SafeAreaView, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import AdenDeadlinePicker, { adenDateTimeToIso, currentAdenDateTime } from '../components/AdenDeadlinePicker';
import { friendlyDataError, getMyEmployeeProfile } from '../lib/mobileData';
import { createAdministrativeTask, loadDashboardData, roleLabel, statusLabel, type DashboardData } from '../lib/adminData';
import { supabase } from '../lib/supabase';
import { loadOrganizationBranding } from '../lib/organizationBranding';
import { listApprovedDesignerTemplates, type ReportTemplate } from '../lib/reportDesigner';
import ReportDesigner from '../components/ReportDesigner';
import TaskDesigner, { type TaskTemplateDraft } from '../components/TaskDesigner';
import { assignTaskFromTemplate, listApprovedTaskReportForms, listTaskDesignerCategories, listTaskDesignerTemplates, saveTaskDesignerTemplate, setTaskDesignerTemplateActive, type StoredTaskTemplate, type TaskCategoryRow } from '../lib/taskDesigner';

type Section = 'overview' | 'tasks' | 'task-designer' | 'reports' | 'branches' | 'employees' | 'activity';
const sections: Array<[Section, string]> = [['overview', 'الرئيسية'], ['tasks', 'إدارة المهام'], ['task-designer', 'مصمم المهام والتقارير'], ['reports', 'تقارير الموظفين'], ['branches', 'الفروع'], ['employees', 'الموظفون'], ['activity', 'السجل والمرفقات']];
const roleCodes = ['owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'];
const priorityLabels: Record<string, string> = { normal: 'عادية', important: 'مهمة', urgent: 'عاجلة', critical: 'حرجة' };

export default function AdminScreen() {
  const router = useRouter();
  const [section, setSection] = useState<Section>('overview');
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
  const [showCreate, setShowCreate] = useState(false);
  const [initialDeadline] = useState(currentAdenDateTime);
  const [draft, setDraft] = useState({ title: '', description: '', dueDate: initialDeadline.date, dueTime: initialDeadline.time, priority: 'normal', roleCode: 'admin_followup', branchId: '', assignedEmployeeId: '', templateId: '', reportTemplateId: '', reportRequired: true });

  const load = useCallback(async () => {
    setError('');
    try {
      const identity = await getMyEmployeeProfile();
      if (!identity?.employee) throw new Error('employee_not_active');
      setCurrentName(identity.employee.fullName || 'المستخدم');
      const branding = await loadOrganizationBranding(identity.employee.institutionId);
      setBrandName(branding.name);
      setBrandTagline(branding.tagline);
      setBrandLogoUrl(branding.logoUrl);
      setNotice(branding.settingsAvailable ? '' : 'تعديل هوية المؤسسة سيتاح بعد تحديث قاعدة البيانات؛ لوحة الإدارة تعمل بالبيانات الحالية.');
      const currentPermissions = identity.employee.permissions;
      if (!currentPermissions.includes('tasks.manage')) throw new Error('permission_denied');
      const canManageLibrary = currentPermissions.includes('task_library.manage');
      const canManageReports = currentPermissions.includes('report_forms.manage');
      const dashboard = await loadDashboardData();
      const reportTemplates = canManageReports ? await listApprovedDesignerTemplates() : canManageLibrary ? await listApprovedTaskReportForms() : [];
      const editableTaskTemplates = canManageLibrary ? await listTaskDesignerTemplates() : [];
      const categories = canManageLibrary ? await listTaskDesignerCategories() : [];
      setPermissions(currentPermissions);
      setData(dashboard);
      setDesignerTemplates(reportTemplates);
      setTaskDesignerTemplates(editableTaskTemplates);
      setTaskCategories(categories);
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر تحميل لوحة الإدارة من Supabase.')); }
    finally { setLoading(false); setRefreshing(false); }
  }, []);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => { const sub = AppState.addEventListener('change', (state) => { if (state === 'active') void load(); }); return () => sub.remove(); }, [load]);

  const counts = useMemo(() => {
    const tasks = data?.tasks ?? [];
    return { all: tasks.length, new: tasks.filter((task) => ['new', 'received'].includes(task.status)).length, active: tasks.filter((task) => ['in_progress', 'on_hold'].includes(task.status)).length, review: tasks.filter((task) => task.status === 'report_submitted').length, late: tasks.filter((task) => task.status === 'late' || (!!task.dueAt && new Date(task.dueAt) < new Date() && !['completed_approved', 'cancelled'].includes(task.status))).length, done: tasks.filter((task) => task.status === 'completed_approved').length };
  }, [data]);

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
      const selectedReport = designerTemplates.find((template) => template.id === draft.reportTemplateId && template.role_code === draft.roleCode);
      if (draft.reportTemplateId && !selectedReport?.approved_version_id) throw new Error('report_form_version_requires_approval');
      await createAdministrativeTask({
        title: draft.title, description: draft.description, dueAt, priority: draft.priority,
        roleCode: draft.roleCode, branchId: draft.branchId || null, assignedEmployeeId: draft.assignedEmployeeId, templateId: draft.templateId || null,
        reportTemplateId: selectedReport?.id ?? null, reportVersionId: selectedReport?.approved_version_id ?? null,
        reportRequired: draft.reportRequired,
      });
      const nextDeadline = currentAdenDateTime();
      setDraft({ title: '', description: '', dueDate: nextDeadline.date, dueTime: nextDeadline.time, priority: 'normal', roleCode: 'admin_followup', branchId: '', assignedEmployeeId: '', templateId: '', reportTemplateId: '', reportRequired: true });
      setShowCreate(false); setNotice('تم إنشاء المهمة وإسنادها للموظف المحدد.'); await load();
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر إنشاء المهمة. تأكد من وجود موظف نشط ضمن التصنيف والفرع المحددين.')); }
  }
  const canManageTaskLibrary = permissions.includes('task_library.manage');
  const fmt = (value: string | null) => value ? new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : 'غير محدد';

  if (loading) return <SafeAreaView style={styles.safe}><View style={styles.center}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.muted}>جارٍ تحميل لوحة الإدارة…</Text></View></SafeAreaView>;
  return <SafeAreaView style={styles.safe}>
    <Stack.Screen options={{ headerShown: false }} />
    <ScrollView refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); void load(); }} />} contentContainerStyle={styles.content}>
      <View style={styles.brandHeader}><View style={styles.brandIdentity}><Image source={brandLogoUrl ? { uri: brandLogoUrl } : require('../assets/icon.png')} style={styles.brandLogo} resizeMode="contain" /><View style={styles.brandTitles}><Text style={styles.brandName}>برنامج الشاعري</Text><Text style={styles.brandSubtitle}>{brandName}</Text><Text style={styles.brandMotto}>{brandTagline}</Text></View></View><View style={styles.headerActions}><Pressable accessibilityRole="button" accessibilityLabel="سجل النشاط" style={styles.notificationButton} onPress={() => setSection('activity')}><Text style={styles.notificationGlyph}>♧</Text></Pressable><Pressable accessibilityRole="button" accessibilityLabel="تسجيل الخروج وتبديل الحساب" style={styles.signOutButton} onPress={() => void signOut()}><Text style={styles.signOutButtonText}>تبديل الحساب</Text></Pressable></View></View>
      <View style={styles.welcomeBanner}><View style={styles.welcomeAvatar}><Text style={styles.avatarGlyph}>●</Text></View><View style={styles.welcomeText}><Text style={styles.welcomeTitle}>مرحباً، {currentName || 'بك'}</Text><Text style={styles.welcomeRole}>لوحة إدارة المؤسسة</Text></View></View>
      {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
      {!!notice && <Text style={styles.notice}>{notice}</Text>}

      {section === 'overview' && <Overview counts={counts} data={data} fmt={fmt} onSection={setSection} onSettings={() => router.push('/settings')} canDesign={canManageTaskLibrary} /> }
      {section === 'tasks' && <>{canManageTaskLibrary && <TaskAssignmentSection templates={taskDesignerTemplates} data={data} onReload={load} onEditTemplates={() => setSection('task-designer')} />}<TasksSection data={data} designerTemplates={designerTemplates} showCreate={showCreate} setShowCreate={setShowCreate} draft={draft} setDraft={setDraft} createTask={createTask} fmt={fmt} onOpenTasks={() => router.push('/tasks')} /></>}
      {section === 'task-designer' && canManageTaskLibrary && <TaskTemplatesSection templates={taskDesignerTemplates} categories={taskCategories} onReload={load} />}
      {section === 'reports' && <ReportsSection data={data} fmt={fmt} />}
      {section === 'branches' && <BranchesSection data={data} canManage={permissions.includes('branches.manage')} onReload={load} />}
      {section === 'employees' && <EmployeesSection data={data} />}
      {section === 'activity' && <ActivitySection data={data} fmt={fmt} />}
    </ScrollView>
    <View style={styles.bottomBar}><Pressable style={[styles.bottomItem, section === 'overview' && styles.bottomItemActive]} onPress={() => setSection('overview')}><Text style={[styles.bottomGlyph, section === 'overview' && styles.bottomGlyphActive]}>⌂</Text><Text style={[styles.bottomLabel, section === 'overview' && styles.bottomLabelActive]}>الرئيسية</Text></Pressable><Pressable style={[styles.bottomItem, section === 'tasks' && styles.bottomItemActive]} onPress={() => setSection('tasks')}><Text style={[styles.bottomGlyph, section === 'tasks' && styles.bottomGlyphActive]}>▣</Text><Text style={[styles.bottomLabel, section === 'tasks' && styles.bottomLabelActive]}>المهام</Text></Pressable><Pressable style={[styles.bottomItem, section === 'employees' && styles.bottomItemActive]} onPress={() => setSection('employees')}><Text style={[styles.bottomGlyph, section === 'employees' && styles.bottomGlyphActive]}>♟</Text><Text style={[styles.bottomLabel, section === 'employees' && styles.bottomLabelActive]}>الموظفون</Text></Pressable><Pressable style={styles.bottomItem} onPress={() => router.push('/settings')}><Text style={styles.bottomGlyph}>⚙</Text><Text style={styles.bottomLabel}>الإعدادات</Text></Pressable></View>
  </SafeAreaView>;
}

function Overview({ counts, data, fmt, onSection, onSettings, canDesign }: { counts: { all: number; new: number; active: number; review: number; late: number; done: number }; data: DashboardData | null; fmt: (v: string | null) => string; onSection: (section: Section) => void; onSettings: () => void; canDesign: boolean }) { return <>
  <View style={styles.metricsHeader}><Text style={styles.sectionTitle}>ملخص المهام</Text><Text style={styles.metricsHint}>متابعة أعمال المؤسسة</Text></View>
  <View style={styles.metrics}>{[{label:'إجمالي المهام',value:counts.all,tone:'blue',glyph:'▦'},{label:'قيد التنفيذ',value:counts.active,tone:'green',glyph:'▶'},{label:'بانتظار المراجعة',value:counts.review,tone:'amber',glyph:'✓'},{label:'مهام متأخرة',value:counts.late,tone:'red',glyph:'◷'}].map((item) => <View style={[styles.metric, styles['metric_'+item.tone as 'metric_blue']] as any} key={item.label}><Text style={styles.metricGlyph}>{item.glyph}</Text><Text style={styles.metricValue}>{item.value}</Text><Text style={styles.metricLabel}>{item.label}</Text></View>)}</View>
  <View style={styles.moduleHeader}><Text style={styles.sectionTitle}>خدمات الإدارة</Text><Text style={styles.metricsHint}>اختر القسم المطلوب</Text></View>
  <View style={styles.moduleGrid}>
    {[{title:'إدارة المهام',sub:'إنشاء ومتابعة التكليفات',glyph:'▣',section:'tasks' as Section},{title:'التقارير',sub:'تقارير الموظفين ومراجعتها',glyph:'▤',section:'reports' as Section},{title:'إدارة الفروع',sub:'إضافة الفروع وتعديلها',glyph:'⌂',section:'branches' as Section},{title:'إدارة الموظفين',sub:'بيانات الموظفين وحساباتهم',glyph:'♟',section:'employees' as Section},...(canDesign?[{title:'مصمم المهام',sub:'قوالب وخطوات ديناميكية',glyph:'✎',section:'task-designer' as Section},{title:'مصمم التقارير',sub:'إنشاء نماذج التقارير',glyph:'▤',section:'task-designer' as Section}]:[]),{title:'سجل النشاط',sub:'مراجعة الأحداث والمرفقات',glyph:'◷',section:'activity' as Section}].map((item,index)=><Pressable key={item.title} style={styles.moduleCard} onPress={()=>onSection(item.section)}><View style={[styles.moduleIcon,index%2===0?styles.moduleIconGold:styles.moduleIconBlue]}><Text style={styles.moduleGlyph}>{item.glyph}</Text></View><View style={styles.moduleCopy}><Text style={styles.moduleTitle}>{item.title}</Text><Text style={styles.moduleSubtitle}>{item.sub}</Text></View><Text style={styles.moduleArrow}>‹</Text></Pressable>)}
    <Pressable style={styles.moduleCard} onPress={onSettings}><View style={styles.moduleIcon}><Text style={styles.moduleGlyph}>⚙</Text></View><View style={styles.moduleCopy}><Text style={styles.moduleTitle}>الصلاحيات والإعدادات</Text><Text style={styles.moduleSubtitle}>إدارة حسابات المستخدمين</Text></View><Text style={styles.moduleArrow}>‹</Text></Pressable>
  </View>
  <View style={styles.branchFooter}><Text style={styles.branchFooterTitle}>الفروع المسجلة</Text><Text style={styles.branchFooterValue}>{(data?.branches ?? []).filter((branch)=>branch.isActive).length} فروع نشطة</Text></View>
  <View style={styles.activityPreview}><Text style={styles.sectionTitle}>آخر النشاط</Text>{(data?.activity ?? []).slice(0,3).map((item)=><View style={styles.activityPreviewRow} key={item.id}><Text style={styles.cardTitle}>{item.action}</Text><Text style={styles.meta}>{fmt(item.createdAt)}</Text></View>)}{!(data?.activity ?? []).length&&<Text style={styles.muted}>لا توجد أنشطة حديثة.</Text>}</View>
</>; }

function TasksSection({ data, designerTemplates, showCreate, setShowCreate, draft, setDraft, createTask, fmt, onOpenTasks }: any) {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
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
      <Pressable style={styles.taskCreateButton} onPress={() => setShowCreate(!showCreate)}><Text style={styles.taskCreateButtonText}>{showCreate?'إغلاق':'＋ إنشاء تكليف'}</Text></Pressable>
    </View>
    {showCreate && <View style={styles.form}>
      <View style={styles.formTitleRow}><Text style={styles.formTitle}>بيانات التكليف الجديد</Text><Text style={styles.formStep}>1 · التفاصيل</Text></View>
      {[['title', 'عنوان المهمة'], ['description', 'وصف وتعليمات التنفيذ']].map(([key, label]) => <TextInput key={key} style={styles.input} placeholder={label} value={draft[key]} onChangeText={(value) => setDraft({ ...draft, [key]: value })} multiline={key === 'description'} />)}
      <AdenDeadlinePicker date={draft.dueDate} time={draft.dueTime} onChange={(dueDate, dueTime) => setDraft({ ...draft, dueDate, dueTime })} />
      <Text style={styles.fieldLabel}>التصنيف الوظيفي المستهدف</Text>
      <View style={styles.choices}>{roleCodes.map((role) => <Pressable key={role} style={[styles.choice, draft.roleCode === role && styles.choiceSelected]} onPress={() => setDraft({ ...draft, roleCode: role, assignedEmployeeId: '', templateId: '', reportTemplateId: designerTemplates.some((item: ReportTemplate) => item.id === draft.reportTemplateId && item.role_code === role) ? draft.reportTemplateId : '' })}><Text style={draft.roleCode === role ? styles.choiceSelectedText : styles.choiceText}>{roleLabel(role)}</Text></Pressable>)}</View>
      <Text style={styles.fieldLabel}>الفرع</Text>
      <View style={styles.choices}><Pressable style={[styles.choice, !draft.branchId && styles.choiceSelected]} onPress={() => setDraft({ ...draft, branchId: '', assignedEmployeeId: '' })}><Text style={!draft.branchId ? styles.choiceSelectedText : styles.choiceText}>كل الفروع</Text></Pressable>{(data?.branches ?? []).map((branch: any) => <Pressable key={branch.id} style={[styles.choice, draft.branchId === branch.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, branchId: branch.id, assignedEmployeeId: '' })}><Text style={draft.branchId === branch.id ? styles.choiceSelectedText : styles.choiceText}>{branch.name}</Text></Pressable>)}</View>
      <Text style={styles.fieldLabel}>الموظف المستلم</Text>
      <View style={styles.choices}>{(data?.employees ?? []).filter((employee: any) => employee.active && employee.roles.includes(draft.roleCode) && (!draft.branchId || employee.branchId === draft.branchId)).map((employee: any) => <Pressable key={employee.id} style={[styles.choice, draft.assignedEmployeeId === employee.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, assignedEmployeeId: employee.id })}><Text style={draft.assignedEmployeeId === employee.id ? styles.choiceSelectedText : styles.choiceText}>{employee.name} · رقم {employee.employeeNo ?? 'غير مسجل'}</Text></Pressable>)}</View>
      {!((data?.employees ?? []).some((employee: any) => employee.active && employee.roles.includes(draft.roleCode) && (!draft.branchId || employee.branchId === draft.branchId))) && <Text style={styles.error}>لا يوجد موظف نشط بهذا التصنيف والفرع.</Text>}
      <Text style={styles.fieldLabel}>نموذج التقرير المرتبط بالتكليف</Text>
      <View style={styles.choices}><Pressable style={[styles.choice, !draft.reportTemplateId && styles.choiceSelected]} onPress={() => setDraft({ ...draft, reportTemplateId: '' })}><Text style={!draft.reportTemplateId ? styles.choiceSelectedText : styles.choiceText}>بدون نموذج تقرير</Text></Pressable>{designerTemplates.filter((template: ReportTemplate) => template.role_code === draft.roleCode).map((template: ReportTemplate) => <Pressable key={template.id} style={[styles.choice, draft.reportTemplateId === template.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, reportTemplateId: template.id })}><Text style={draft.reportTemplateId === template.id ? styles.choiceSelectedText : styles.choiceText}>{template.title} · إصدار {template.approved_version_no}</Text></Pressable>)}</View>
      <Pressable style={styles.secondary} onPress={() => setDraft({ ...draft, reportRequired: !draft.reportRequired })}><Text style={styles.secondaryText}>{draft.reportRequired ? 'التقرير مطلوب ✓' : 'التقرير اختياري'}</Text></Pressable>
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
        <View style={styles.taskListFooter}><Text style={styles.taskDueLabel}>الموعد: {fmt(task.dueAt)}</Text><Text style={styles.taskIdLabel}>#{String(task.id).slice(0,8)}</Text></View>
      </View>;
    }) : <View style={styles.taskEmpty}><Text style={styles.taskEmptyGlyph}>▤</Text><Text style={styles.taskEmptyTitle}>لا توجد مهام مطابقة</Text><Text style={styles.taskEmptyText}>{tasks.length?'جرّب تغيير البحث أو حالة المهمة.':'ابدأ بإنشاء أول تكليف للمؤسسة.'}</Text></View>}
    <Pressable style={styles.taskOpenExecution} onPress={onOpenTasks}><Text style={styles.taskOpenExecutionText}>فتح شاشة تنفيذ المهام والتقارير والمرفقات ←</Text></Pressable>
  </View>;
}
function ReportsSection({ data, fmt }: any) { return <><Text style={styles.sectionTitle}>تقارير الموظفين</Text><Text style={styles.copy}>التقارير المرتبطة بالمهام وتنتظر المراجعة أو تم اعتمادها.</Text>{(data?.reports ?? []).length ? data.reports.map((report: any) => <View style={styles.card} key={report.id}><Text style={styles.cardTitle}>{report.status === 'submitted' ? 'بانتظار المراجعة' : report.status === 'approved' ? 'معتمد' : 'معاد للتصحيح'}</Text><Text style={styles.meta}>{fmt(report.submittedAt)} · {report.id.slice(0, 8)}</Text></View>) : <Text style={styles.muted}>لا توجد تقارير مسجلة حاليًا.</Text>}</>; }
function BranchesSection({ data, canManage, onReload }: any) {
  const [code, setCode] = useState('');
  const [name, setName] = useState('');
  const [renames, setRenames] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [branchError, setBranchError] = useState('');
  const [branchNotice, setBranchNotice] = useState('');
  async function manage(action: 'create' | 'update' | 'archive' | 'activate', branchId?: string, branchName?: string) {
    if (!supabase) return;
    setBusy(true); setBranchError(''); setBranchNotice('');
    try {
      const { error } = await supabase.functions.invoke('employee-code-auth', { body: {
        action: 'manage_branch', branchAction: action, branchId: branchId ?? null,
        code: action === 'create' ? code.trim().toUpperCase() : null,
        name: action === 'create' ? name.trim() : branchName?.trim() ?? null,
      }});
      if (error) throw error;
      setBranchNotice(action === 'create' ? 'تمت إضافة الفرع.' : action === 'update' ? 'تم تعديل اسم الفرع.' : action === 'archive' ? 'تم أرشفة الفرع وإيقاف استخدامه.' : 'تمت إعادة تفعيل الفرع.');
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
      {canManage && !branch.isActive && <Pressable disabled={busy} style={styles.secondary} onPress={() => void manage('activate',branch.id)}><Text style={styles.secondaryText}>إعادة تفعيل الفرع</Text></Pressable>}
    </View>)}
  </>;
}
function EmployeesSection({ data }: any) { return <><Text style={styles.sectionTitle}>الموظفون والتصنيفات الوظيفية</Text>{(data?.employees ?? []).map((employee: any) => <View style={styles.card} key={employee.id}><Text style={styles.cardTitle}>{employee.name}</Text><Text style={styles.meta}>{employee.employeeNo || 'بدون رقم'} · {employee.active ? 'نشط' : 'غير نشط'}</Text><Text style={styles.meta}>{employee.roles.length ? employee.roles.map(roleLabel).join('، ') : 'دون تصنيف'} · {employee.branchName ?? 'دون فرع'}</Text></View>)}</>; }
function ActivitySection({ data, fmt }: any) { return <><Text style={styles.sectionTitle}>سجل النشاط والمرفقات</Text><Text style={styles.copy}>السجل يعرض الأحداث المسموح بها حسب RLS. إدارة المرفقات تتم من داخل تقرير المهمة.</Text>{(data?.activity ?? []).map((item: any) => <View style={styles.row} key={item.id}><Text style={styles.cardTitle}>{item.action}</Text><Text style={styles.meta}>المهمة {item.taskId.slice(0, 8)} · {fmt(item.createdAt)}</Text></View>)}</>; }
function Unavailable({ title, text }: { title: string; text: string }) { return <View style={styles.unavailable}><Text style={styles.sectionTitle}>{title}</Text><Text style={styles.copy}>{text}</Text></View>; }

function TaskTemplatesSection({ templates, categories, onReload }: { templates: StoredTaskTemplate[]; categories: TaskCategoryRow[]; onReload: () => Promise<void> }) {
  const [selected, setSelected] = useState<StoredTaskTemplate | null>(null);
  const [editing, setEditing] = useState(false);
  const [mode, setMode] = useState<'tasks' | 'reports'>('tasks');
  const [saveError, setSaveError] = useState('');
  const subcategoryOptions = Object.fromEntries(categories.filter((category) => category.parent_id).map((category) => [categories.find((parent) => parent.id === category.parent_id)?.code, [...(categories.filter((item) => item.parent_id === category.parent_id).map((item) => item.title))]])) as Partial<Record<'finance' | 'sales' | 'purchases' | 'warehouse' | 'items' | 'admin' | 'other', string[]>>;
  async function save(draft: TaskTemplateDraft) {
    try {
      setSaveError('');
      await saveTaskDesignerTemplate(draft, categories);
      setSelected(null);
      setEditing(false);
      await onReload();
    } catch (cause) {
      setSaveError(friendlyDataError(cause, 'تعذر حفظ قالب المهمة. تحقق من الصلاحيات ونماذج التقارير المعتمدة.'));
    }
  }
  return <View style={{ gap: 12 }}>
    <View style={styles.choices}><Pressable style={[styles.choice, mode === 'tasks' && styles.choiceSelected]} onPress={() => setMode('tasks')}><Text style={mode === 'tasks' ? styles.choiceSelectedText : styles.choiceText}>مصمم المهام</Text></Pressable><Pressable style={[styles.choice, mode === 'reports' && styles.choiceSelected]} onPress={() => setMode('reports')}><Text style={mode === 'reports' ? styles.choiceSelectedText : styles.choiceText}>مصمم التقارير الديناميكي</Text></Pressable></View>
    {mode === 'reports' ? <ReportDesigner /> : <>
    <View style={styles.card}><Text style={styles.sectionTitle}>مصمم المهمة والتقرير</Text><Text style={styles.copy}>أنشئ المهمة وخطواتها وحقول تقرير الموظف من شاشة واحدة. حفظ القالب يحفظ التصميم فقط ولا يرسل تكليفًا؛ لإرسال مهمة فعلية اختر «إسناد من قالب مهام» وحدد الموظفين والفرع. تحفظ نسخة ثابتة من التقرير لكل تكليف جديد.</Text><Pressable style={styles.primary} onPress={() => { setSelected(null); setEditing(true); setSaveError(''); }}><Text style={styles.primaryText}>قالب جديد</Text></Pressable></View>
    {templates.map((template) => <View key={template.id} style={styles.card}><View style={styles.taskLine}><Text style={styles.cardTitle}>{template.title}</Text><Text style={styles.badge}>{template.isActive ? 'نشط' : 'مؤرشف'}</Text></View><Text style={styles.meta}>{roleLabel(template.roleCode)} · {template.steps.length} خطوات · {template.reports.length} نماذج تقارير · إصدار القالب {template.version}</Text><View style={styles.actionsRow}><Pressable style={styles.secondary} onPress={() => { setSelected(template); setEditing(true); setSaveError(''); }}><Text style={styles.secondaryText}>تعديل القالب</Text></Pressable><Pressable style={styles.secondary} onPress={() => { setSelected({ ...template, id: undefined, title: `نسخة من ${template.title}`, isActive: false }); setEditing(true); setSaveError(''); }}><Text style={styles.secondaryText}>نسخ القالب</Text></Pressable><Pressable style={styles.secondary} onPress={async () => { try { await setTaskDesignerTemplateActive(template.id!, !template.isActive); await onReload(); } catch (cause) { setSaveError(friendlyDataError(cause, 'تعذر تغيير حالة القالب.')); } }}><Text style={styles.secondaryText}>{template.isActive ? 'أرشفة' : 'إعادة تفعيل'}</Text></Pressable></View></View>)}
    {!!saveError && <Text accessibilityRole="alert" style={styles.error}>{saveError}</Text>}
    {editing && <TaskDesigner key={selected?.id ?? 'new-task-template'} initialTemplate={selected ?? undefined} subcategoryOptions={subcategoryOptions} onSave={save} onList={onReload} />}
    {templates.length === 0 && <Text style={styles.muted}>لا توجد قوالب بعد؛ أنشئ قالبًا جديدًا للبدء.</Text>}
    </>}
  </View>;
}

function TaskAssignmentSection({ templates, data, onReload, onEditTemplates }: { templates: StoredTaskTemplate[]; data: DashboardData | null; onReload: () => Promise<void>; onEditTemplates: () => void }) {
  const initial = currentAdenDateTime();
  const [templateId, setTemplateId] = useState('');
  const [employeeIds, setEmployeeIds] = useState<string[]>([]);
  const [branchId, setBranchId] = useState('');
  const [startDate, setStartDate] = useState(initial.date);
  const [startTime, setStartTime] = useState(initial.time);
  const [dueDate, setDueDate] = useState(initial.date);
  const [dueTime, setDueTime] = useState(initial.time);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [priority, setPriority] = useState<StoredTaskTemplate['priority']>('normal');
  const [instructions, setInstructions] = useState('');
  const [reportRequired, setReportRequired] = useState<Record<string, boolean>>({});
  const selectedTemplate = templates.find((item) => item.id === templateId && item.isActive);
  const reportChoices = selectedTemplate?.reports ?? [];
  const employees = (data?.employees ?? []).filter((item) => item.active && Boolean(item.userId) && (!selectedTemplate || item.assignments.some((assignment) => assignment.roleCode === selectedTemplate.roleCode && (!branchId || assignment.branchId === branchId))));
  const selectedEmployees = employees.filter((item) => employeeIds.includes(item.id));
  async function assign() {
    setError(''); setNotice('');
    const startsAt = adenDateTimeToIso(startDate, startTime);
    const dueAt = adenDateTimeToIso(dueDate, dueTime);
    if (!selectedTemplate) { setError('اختر قالبًا نشطًا أولًا.'); return; }
    if (!selectedEmployees.length) { setError('اختر موظفًا واحدًا على الأقل لإرسال المهمة إليه.'); return; }
    if (!startsAt || !dueAt) { setError('أدخل تاريخًا ووقتًا صالحين لبداية المهمة وموعدها النهائي.'); return; }
    if (new Date(dueAt).getTime() < new Date(startsAt).getTime()) { setError('لا يمكن أن يسبق الموعد النهائي بداية المهمة.'); return; }
    setBusy(true);
    try {
      let assignedCount = 0;
      const failures: Array<{ id: string; name: string; message: string }> = [];
      for (const employee of selectedEmployees) {
        try {
          await assignTaskFromTemplate({ templateId: selectedTemplate.id!, assignedTo: employee.userId!, branchId: branchId || null, startsAt, dueAt, priority, instructions, reportOverrides: reportChoices.map((report) => ({ approvedVersionId: report.approvedVersionId, required: report.required || reportRequired[report.approvedVersionId] === true })) });
          assignedCount += 1;
        } catch (cause) {
          failures.push({ id: employee.id, name: employee.name, message: friendlyDataError(cause, 'تعذر إنشاء المهمة لهذا الموظف.') });
        }
      }
      if (assignedCount > 0) {
        setNotice(`تم إرسال «${selectedTemplate.title}» وإسنادها إلى ${assignedCount} من ${selectedEmployees.length} موظفًا. ستظهر في شاشة الموظف ضمن المهام النشطة.`);
        if (assignedCount === selectedEmployees.length) {
          setTemplateId(''); setEmployeeIds([]); setBranchId(''); setInstructions(''); setPriority('normal'); setReportRequired({});
        } else setEmployeeIds(failures.map((item) => item.id));
        await onReload();
      }
      if (failures.length) setError(`تعذر الإسناد إلى ${failures.length} موظفًا: ${failures.map((item) => `${item.name} — ${item.message}`).join('؛ ')}`);
      if (!assignedCount && failures.length === 0) setError('لم تُنشأ أي مهمة. اختر موظفًا نشطًا مرتبطًا بحساب موظف قبل الإرسال.');
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر إسناد القالب. تأكد من تطابق الدور والفرع وصلاحية إدارة المهام.'));
    } finally { setBusy(false); }
  }
  return <View style={styles.form}>
    <Text style={styles.sectionTitle}>إسناد من قالب مهام</Text>
    <Text style={styles.copy}>يُنشأ التكليف مع نسخة ثابتة من خطواته وكل نموذج تقرير مرتبط به. يمكن تعديل القالب لاحقًا دون تغيير التكليفات السابقة.</Text>
    <Text style={styles.fieldLabel}>القالب</Text>
    <View style={styles.choices}>{templates.filter((item) => item.isActive).map((item) => <Pressable key={item.id} style={[styles.choice, templateId === item.id && styles.choiceSelected]} onPress={() => { setTemplateId(item.id ?? ''); setEmployeeIds([]); }}><Text style={templateId === item.id ? styles.choiceSelectedText : styles.choiceText}>{item.title} · {roleLabel(item.roleCode)}</Text></Pressable>)}</View>
    {!templates.some((item) => item.isActive) && <Text style={styles.muted}>لا توجد قوالب نشطة.</Text>}
    <Pressable style={styles.secondary} onPress={onEditTemplates}><Text style={styles.secondaryText}>إدارة قوالب المهام</Text></Pressable>
    {selectedTemplate && <>
      <Text style={styles.fieldLabel}>الموظفون المستهدفون ({roleLabel(selectedTemplate.roleCode)}) · يمكن اختيار أكثر من موظف</Text>
      <View style={styles.choices}>{employees.map((employee) => { const selected = employeeIds.includes(employee.id); return <Pressable key={employee.id} style={[styles.choice, selected && styles.choiceSelected]} onPress={() => setEmployeeIds((current) => selected ? current.filter((id) => id !== employee.id) : [...current, employee.id])}><Text style={selected ? styles.choiceSelectedText : styles.choiceText}>{selected ? '✓ ' : ''}{employee.name}{employee.employeeNo ? ` · ${employee.employeeNo}` : ''}</Text></Pressable>; })}</View>
      {!employees.length && <Text style={styles.muted}>{branchId ? 'لا يوجد موظف نشط مرتبط بحساب وله هذا الدور في الفرع المحدد.' : 'لا يوجد موظف نشط مرتبط بحساب وله هذا الدور.'}</Text>}
      <Text style={styles.fieldLabel}>الأولوية لهذا التكليف</Text><View style={styles.choices}>{(['normal','important','urgent','critical'] as const).map((value) => <Pressable key={value} style={[styles.choice, priority === value && styles.choiceSelected]} onPress={() => setPriority(value)}><Text style={priority === value ? styles.choiceSelectedText : styles.choiceText}>{priorityLabels[value]}</Text></Pressable>)}</View>
      <TextInput style={[styles.input, { minHeight: 70 }]} value={instructions} onChangeText={setInstructions} placeholder="تعليمات إضافية لهذا التكليف (اختياري)" multiline accessibilityLabel="تعليمات إضافية لهذا التكليف" />
      {!!reportChoices.length && <><Text style={styles.fieldLabel}>اختيارات التقارير لهذا التكليف</Text><View style={styles.choices}>{reportChoices.map((report) => { const required = report.required || reportRequired[report.approvedVersionId] === true; return <Pressable key={report.approvedVersionId} style={[styles.choice, required && styles.choiceSelected]} onPress={() => { if (report.required) return; setReportRequired((current) => ({ ...current, [report.approvedVersionId]: !required })); }}><Text style={required ? styles.choiceSelectedText : styles.choiceText}>{required ? 'إلزامي' : 'اختياري'} · {report.approvedVersionId.slice(0, 8)}</Text></Pressable>; })}</View></>}
      {reportChoices.some((report) => report.required) && <Text style={styles.meta}>التقارير الإلزامية في القالب لا يمكن تحويلها إلى اختيارية أثناء التكليف.</Text>}
      <Text style={styles.fieldLabel}>الفرع (اختياري، يتحقق الخادم من تكليف الموظف به)</Text>
    <View style={styles.choices}><Pressable style={[styles.choice, !branchId && styles.choiceSelected]} onPress={() => { setBranchId(''); setEmployeeIds([]); }}><Text style={!branchId ? styles.choiceSelectedText : styles.choiceText}>كل الفروع</Text></Pressable>{(data?.branches ?? []).filter((branch) => branch.isActive).map((branch) => <Pressable key={branch.id} style={[styles.choice, branchId === branch.id && styles.choiceSelected]} onPress={() => { setBranchId(branch.id); setEmployeeIds([]); }}><Text style={branchId === branch.id ? styles.choiceSelectedText : styles.choiceText}>{branch.name}</Text></Pressable>)}</View>
      <Text style={styles.fieldLabel}>بداية المهمة · توقيت عدن</Text><AdenDeadlinePicker date={startDate} time={startTime} onChange={(date, time) => { setStartDate(date); setStartTime(time); }} />
      <Text style={styles.fieldLabel}>الموعد النهائي · توقيت عدن</Text><AdenDeadlinePicker date={dueDate} time={dueTime} onChange={(date, time) => { setDueDate(date); setDueTime(time); }} />
      <Text style={styles.meta}>الأولوية الافتراضية: {priorityLabels[selectedTemplate.priority] ?? selectedTemplate.priority} · {selectedTemplate.steps.length} خطوات · {selectedTemplate.reports.length} تقارير مستقلة</Text>
    <Pressable disabled={busy} style={[styles.primary, busy && { opacity: 0.6 }]} onPress={() => void assign()}><Text style={styles.primaryText}>{busy ? 'جارٍ الإرسال…' : employeeIds.length ? `إرسال وإسناد المهمة إلى ${employeeIds.length} موظف` : 'إرسال وإسناد المهمة'}</Text></Pressable>
    </>}
    {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
    {!!notice && <Text style={styles.notice}>{notice}</Text>}
  </View>;
}

const styles = StyleSheet.create({
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
  bottomBar: { flexDirection:'row-reverse', backgroundColor:'#103967', paddingTop:8, paddingBottom:8, paddingHorizontal:7, borderTopWidth:3, borderTopColor:'#e7ae28', minHeight:76, elevation:12, shadowColor:'#102f52', shadowOpacity:0.14, shadowRadius:8, shadowOffset:{width:0,height:-3} },
  bottomItem: { flex:1, minHeight:58, alignItems:'center', justifyContent:'center', borderRadius:13, gap:1 },
  bottomItemActive: { backgroundColor:'#eab22e' },
  bottomGlyph: { color:'#fff', fontSize:23, fontWeight:'900' },
  bottomGlyphActive: { color:'#103967' },
  bottomLabel: { color:'#fff', fontSize:11, fontWeight:'800' },
  bottomLabelActive: { color:'#103967' },
  safe: { flex: 1, backgroundColor: '#f4f7f8' }, content: { padding: 16, paddingTop: 12, paddingBottom: 124, gap: 12 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 }, topbar: { flexDirection: 'row-reverse', justifyContent: 'space-between', alignItems: 'center' }, eyebrow: { color: '#718394', fontWeight: '700', textAlign: 'right' }, title: { color: '#17324d', fontSize: 28, fontWeight: '900', textAlign: 'right', marginTop: 3 }, signOut: { borderWidth: 1, borderColor: '#b55248', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 9 }, signOutText: { color: '#a8443d', fontWeight: '800' }, nav: { flexDirection: 'row-reverse', gap: 8, paddingVertical: 5 }, navChip: { borderWidth: 1, borderColor: '#ccd9df', borderRadius: 20, paddingHorizontal: 12, paddingVertical: 9 }, navChipSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, navText: { color: '#39556a', fontSize: 13 }, navTextSelected: { color: '#fff', fontWeight: '800', fontSize: 13 }, sectionTitle: { color: '#17324d', fontSize: 19, fontWeight: '900', textAlign: 'right', marginTop: 8 }, sectionHeader: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between' }, metrics: { flexDirection: 'row-reverse', flexWrap: 'wrap', justifyContent: 'space-between', rowGap: 10 }, metric: { width: '48%', minHeight: 112, backgroundColor: '#fff', borderRadius: 17, borderWidth: 1, borderBottomWidth: 4, borderColor: '#e0e8eb', paddingVertical: 12, paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center', shadowColor: '#17324d', shadowOpacity: 0.06, shadowRadius: 6, shadowOffset: { width: 0, height: 2 }, elevation: 2 }, metricValue: { color: '#17324d', fontSize: 25, fontWeight: '900' }, metricLabel: { color: '#718394', fontSize: 12, textAlign: 'center', marginTop: 3 }, primary: { minHeight: 48, backgroundColor: '#17324d', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 12 }, primarySmall: { backgroundColor: '#17324d', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10 }, primaryText: { color: '#fff', fontWeight: '800' }, secondary: { minHeight: 46, backgroundColor: '#e8f0f3', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 12 }, secondaryText: { color: '#17324d', fontWeight: '800' }, card: { backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e0e8eb', padding: 14, gap: 5 }, row: { backgroundColor: '#fff', borderRightWidth: 3, borderRightColor: '#2f6654', borderRadius: 12, padding: 13, gap: 4 }, actionsRow: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7 }, taskLine: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8 }, cardTitle: { color: '#17324d', fontSize: 15, fontWeight: '800', textAlign: 'right' }, badge: { color: '#23633c', backgroundColor: '#e8f5eb', paddingHorizontal: 8, paddingVertical: 5, borderRadius: 12, fontSize: 12 }, meta: { color: '#718394', fontSize: 12, lineHeight: 19, textAlign: 'right' }, copy: { color: '#536978', lineHeight: 22, textAlign: 'right' }, form: { backgroundColor: '#fff', borderRadius: 14, padding: 14, gap: 10, borderWidth: 1, borderColor: '#dce6e9' }, input: { minHeight: 46, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, textAlign: 'right', backgroundColor: '#fbfcfc' }, fieldLabel: { color: '#29475a', fontWeight: '800', textAlign: 'right' }, choices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7 }, choice: { borderWidth: 1, borderColor: '#ccd9df', borderRadius: 18, paddingHorizontal: 10, paddingVertical: 8 }, choiceSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, choiceText: { color: '#39556a', fontSize: 12 }, choiceSelectedText: { color: '#fff', fontWeight: '800', fontSize: 12 }, error: { color: '#a8443d', backgroundColor: '#fff0ef', borderRadius: 10, padding: 11, textAlign: 'right', lineHeight: 21 }, notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 10, padding: 11, textAlign: 'right' }, muted: { color: '#718394', textAlign: 'right', paddingVertical: 10 }, unavailable: { backgroundColor: '#fff7e8', borderColor: '#efddb7', borderWidth: 1, borderRadius: 14, padding: 15, gap: 8 }, settings: { minHeight: 46, borderWidth: 1, borderColor: '#17324d', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 11, marginTop: 8 }, settingsText: { color: '#17324d', fontWeight: '800' } });
