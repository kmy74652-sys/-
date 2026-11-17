import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, AppState, Pressable, RefreshControl, SafeAreaView, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import AdenDeadlinePicker, { adenDateTimeToIso, currentAdenDateTime } from '../components/AdenDeadlinePicker';
import { friendlyDataError, getMyEmployeeProfile } from '../lib/mobileData';
import { createAdministrativeTask, loadDashboardData, roleLabel, statusLabel, type DashboardData } from '../lib/adminData';
import { supabase } from '../lib/supabase';
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
  const [draft, setDraft] = useState({ title: '', description: '', dueDate: initialDeadline.date, dueTime: initialDeadline.time, priority: 'normal', roleCode: 'admin_followup', branchId: '', templateId: '', reportTemplateId: '', reportRequired: true });

  const load = useCallback(async () => {
    setError('');
    try {
      const identity = await getMyEmployeeProfile();
      if (!identity?.employee) throw new Error('employee_not_active');
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

  async function signOut() { await supabase?.auth.signOut(); router.replace('/'); }
  async function createTask() {
    const dueAt = adenDateTimeToIso(draft.dueDate, draft.dueTime);
    if (!draft.title.trim() || !dueAt) { setError('أدخل عنوان المهمة واختر تاريخًا ووقتًا صالحين للموعد النهائي.'); return; }
    const startAt = new Date();
    if (new Date(dueAt).getTime() < startAt.getTime()) { setError('لا يمكن أن يسبق الموعد النهائي بداية المهمة. اختر موعدًا الآن أو لاحقًا بتوقيت عدن.'); return; }
    try {
      setError(''); setNotice('');
      const selectedReport = designerTemplates.find((template) => template.id === draft.reportTemplateId && template.role_code === draft.roleCode);
      if (draft.reportTemplateId && !selectedReport?.approved_version_id) throw new Error('report_form_version_requires_approval');
      await createAdministrativeTask({
        title: draft.title, description: draft.description, dueAt, priority: draft.priority,
        roleCode: draft.roleCode, branchId: draft.branchId || null, templateId: draft.templateId || null,
        reportTemplateId: selectedReport?.id ?? null, reportVersionId: selectedReport?.approved_version_id ?? null,
        reportRequired: draft.reportRequired,
      });
      const nextDeadline = currentAdenDateTime();
      setDraft({ title: '', description: '', dueDate: nextDeadline.date, dueTime: nextDeadline.time, priority: 'normal', roleCode: 'admin_followup', branchId: '', templateId: '', reportTemplateId: '', reportRequired: true });
      setShowCreate(false); setNotice('تم إنشاء المهمة وربطها بأول موظف نشط ضمن التصنيف المحدد.'); await load();
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر إنشاء المهمة. تأكد من وجود موظف نشط ضمن التصنيف والفرع المحددين.')); }
  }
  const canManageTaskLibrary = permissions.includes('task_library.manage');
  const visibleSections = sections.filter(([key]) => key !== 'task-designer' || canManageTaskLibrary);
  const fmt = (value: string | null) => value ? new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : 'غير محدد';

  if (loading) return <SafeAreaView style={styles.safe}><View style={styles.center}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.muted}>جارٍ تحميل لوحة الإدارة…</Text></View></SafeAreaView>;
  return <SafeAreaView style={styles.safe}>
    <Stack.Screen options={{ headerShown: false }} />
    <ScrollView refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); void load(); }} />} contentContainerStyle={styles.content}>
      <View style={styles.topbar}><View><Text style={styles.eyebrow}>إدارة مؤسسة الشاعري</Text><Text style={styles.title}>لوحة التحكم</Text></View><Pressable style={styles.signOut} onPress={() => void signOut()}><Text style={styles.signOutText}>خروج</Text></Pressable></View>
      {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
      {!!notice && <Text style={styles.notice}>{notice}</Text>}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.nav}>{visibleSections.map(([key, label]) => <Pressable key={key} onPress={() => setSection(key)} style={[styles.navChip, section === key && styles.navChipSelected]}><Text style={section === key ? styles.navTextSelected : styles.navText}>{label}</Text></Pressable>)}</ScrollView>
      {section === 'overview' && <Overview counts={counts} data={data} fmt={fmt} onTasks={() => setSection('tasks')} />}
      {section === 'tasks' && <>{canManageTaskLibrary && <TaskAssignmentSection templates={taskDesignerTemplates} data={data} onReload={load} onEditTemplates={() => setSection('task-designer')} />}<TasksSection data={data} designerTemplates={designerTemplates} showCreate={showCreate} setShowCreate={setShowCreate} draft={draft} setDraft={setDraft} createTask={createTask} fmt={fmt} onOpenTasks={() => router.push('/tasks')} /></>}
      {section === 'task-designer' && canManageTaskLibrary && <TaskTemplatesSection templates={taskDesignerTemplates} categories={taskCategories} onReload={load} />}
      {section === 'reports' && <ReportsSection data={data} fmt={fmt} />}
      {section === 'branches' && <BranchesSection data={data} />}
      {section === 'employees' && <EmployeesSection data={data} />}
      {section === 'activity' && <ActivitySection data={data} fmt={fmt} />}
      <Pressable style={styles.settings} onPress={() => router.push('/settings')}><Text style={styles.settingsText}>الإعدادات والصلاحيات ورموز الموظفين</Text></Pressable>
    </ScrollView>
  </SafeAreaView>;
}

function Overview({ counts, data, fmt, onTasks }: { counts: { all: number; new: number; active: number; review: number; late: number; done: number }; data: DashboardData | null; fmt: (v: string | null) => string; onTasks: () => void }) { return <>
  <Text style={styles.sectionTitle}>ملخص أداء المؤسسة</Text><View style={styles.metrics}>{[['كل المهام', counts.all], ['جديدة', counts.new], ['قيد التنفيذ', counts.active], ['بانتظار الاعتماد', counts.review], ['متأخرة', counts.late], ['منجزة', counts.done]].map(([label, value]) => <View style={styles.metric} key={String(label)}><Text style={styles.metricValue}>{value}</Text><Text style={styles.metricLabel}>{label}</Text></View>)}</View>
  <Pressable style={styles.primary} onPress={onTasks}><Text style={styles.primaryText}>فتح إدارة المهام والمتابعة</Text></Pressable>
  <Text style={styles.sectionTitle}>الفروع</Text>{(data?.branches ?? []).length ? data?.branches.map((branch) => <View style={styles.card} key={branch.id}><Text style={styles.cardTitle}>{branch.name}</Text><Text style={styles.meta}>{branch.code} · {branch.level || 'مؤسسة'}</Text><Text style={styles.meta}>{data.tasks.filter((task) => task.branchId === branch.id).length} مهمة مرتبطة</Text></View>) : <Text style={styles.muted}>لا توجد فروع مسجلة حاليًا.</Text>}
  <Text style={styles.sectionTitle}>آخر القرارات والنشاط</Text>{(data?.activity ?? []).slice(0, 5).map((item) => <View style={styles.row} key={item.id}><Text style={styles.cardTitle}>{item.action}</Text><Text style={styles.meta}>{fmt(item.createdAt)} · مهمة {item.taskId.slice(0, 8)}</Text></View>)}
</>; }

function TasksSection({ data, designerTemplates, showCreate, setShowCreate, draft, setDraft, createTask, fmt, onOpenTasks }: any) { return <><View style={styles.sectionHeader}><Text style={styles.sectionTitle}>إدارة المهام</Text><Pressable style={styles.primarySmall} onPress={() => setShowCreate(!showCreate)}><Text style={styles.primaryText}>{showCreate ? 'إلغاء' : 'إنشاء مهمة'}</Text></Pressable></View>{showCreate && <View style={styles.form}>{[['title', 'عنوان المهمة'], ['description', 'الوصف']].map(([key, label]) => <TextInput key={key} style={styles.input} placeholder={label} value={draft[key]} onChangeText={(value) => setDraft({ ...draft, [key]: value })} multiline={key === 'description'} />)}<AdenDeadlinePicker date={draft.dueDate} time={draft.dueTime} onChange={(dueDate, dueTime) => setDraft({ ...draft, dueDate, dueTime })} /><Text style={styles.fieldLabel}>التصنيف الوظيفي</Text><View style={styles.choices}>{roleCodes.map((role) => <Pressable key={role} style={[styles.choice, draft.roleCode === role && styles.choiceSelected]} onPress={() => setDraft({ ...draft, roleCode: role, templateId: '', reportTemplateId: designerTemplates.some((item: ReportTemplate) => item.id === draft.reportTemplateId && item.role_code === role) ? draft.reportTemplateId : '' })}><Text style={draft.roleCode === role ? styles.choiceSelectedText : styles.choiceText}>{roleLabel(role)}</Text></Pressable>)}</View><Text style={styles.fieldLabel}>الفرع</Text><View style={styles.choices}>{(data?.branches ?? []).map((branch: any) => <Pressable key={branch.id} style={[styles.choice, draft.branchId === branch.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, branchId: branch.id })}><Text style={draft.branchId === branch.id ? styles.choiceSelectedText : styles.choiceText}>{branch.name}</Text></Pressable>)}</View><Text style={styles.fieldLabel}>نموذج التقرير الديناميكي مع حفظ نسخة للمهمة</Text><View style={styles.choices}><Pressable style={[styles.choice, !draft.reportTemplateId && styles.choiceSelected]} onPress={() => setDraft({ ...draft, reportTemplateId: '' })}><Text style={!draft.reportTemplateId ? styles.choiceSelectedText : styles.choiceText}>بدون نموذج تقرير</Text></Pressable>{designerTemplates.filter((template: ReportTemplate) => template.role_code === draft.roleCode).map((template: ReportTemplate) => <Pressable key={template.id} style={[styles.choice, draft.reportTemplateId === template.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, reportTemplateId: template.id })}><Text style={draft.reportTemplateId === template.id ? styles.choiceSelectedText : styles.choiceText}>{template.title} · إصدار {template.approved_version_no}</Text></Pressable>)}</View><Pressable style={styles.secondary} onPress={() => setDraft({ ...draft, reportRequired: !draft.reportRequired })}><Text style={styles.secondaryText}>{draft.reportRequired ? 'التقرير مطلوب ✓' : 'التقرير اختياري'}</Text></Pressable><Pressable style={styles.primary} onPress={() => void createTask()}><Text style={styles.primaryText}>حفظ ونشر المهمة للمستخدم</Text></Pressable></View>}<Pressable style={styles.secondary} onPress={onOpenTasks}><Text style={styles.secondaryText}>فتح شاشة التنفيذ والتقارير والمرفقات</Text></Pressable>{(data?.tasks ?? []).map((task: any) => <View style={styles.card} key={task.id}><View style={styles.taskLine}><Text style={styles.cardTitle}>{task.title}</Text><Text style={styles.badge}>{statusLabel(task.status)}</Text></View><Text style={styles.meta}>{task.branchName || 'كل الفروع'} · {priorityLabels[task.priority] || task.priority} · {fmt(task.dueAt)}</Text></View>)}</>; }
function ReportsSection({ data, fmt }: any) { return <><Text style={styles.sectionTitle}>تقارير الموظفين</Text><Text style={styles.copy}>التقارير المرتبطة بالمهام وتنتظر المراجعة أو تم اعتمادها.</Text>{(data?.reports ?? []).length ? data.reports.map((report: any) => <View style={styles.card} key={report.id}><Text style={styles.cardTitle}>{report.status === 'submitted' ? 'بانتظار المراجعة' : report.status === 'approved' ? 'معتمد' : 'معاد للتصحيح'}</Text><Text style={styles.meta}>{fmt(report.submittedAt)} · {report.id.slice(0, 8)}</Text></View>) : <Text style={styles.muted}>لا توجد تقارير مسجلة حاليًا.</Text>}</>; }
function BranchesSection({ data }: any) { return <><Text style={styles.sectionTitle}>إدارة الفروع</Text><Text style={styles.copy}>عرض الفروع الثانية والثالثة مع عدد المهام الحالية. الإضافة والتعديل ستستخدم نفس جداول الفروع عند تفعيل صلاحية الإدارة.</Text>{(data?.branches ?? []).map((branch: any) => <View style={styles.card} key={branch.id}><Text style={styles.cardTitle}>{branch.name}</Text><Text style={styles.meta}>الكود: {branch.code} · المستوى: {branch.level || 'غير محدد'} · {branch.isActive ? 'نشط' : 'متوقف'}</Text></View>)}</>; }
function EmployeesSection({ data }: any) { return <><Text style={styles.sectionTitle}>الموظفون والتصنيفات الوظيفية</Text>{(data?.employees ?? []).map((employee: any) => <View style={styles.card} key={employee.id}><Text style={styles.cardTitle}>{employee.name}</Text><Text style={styles.meta}>{employee.employeeNo || 'بدون رقم'} · {employee.active ? 'نشط' : 'غير نشط'}</Text><Text style={styles.meta}>{employee.roles.length ? employee.roles.map(roleLabel).join('، ') : 'دون تصنيف'}</Text></View>)}</>; }
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
    <View style={styles.card}><Text style={styles.sectionTitle}>مصمم المهمة والتقرير</Text><Text style={styles.copy}>أنشئ المهمة وخطواتها وحقول تقرير الموظف من شاشة واحدة. حفظ القالب ينشئ نسخة تقرير مرتبطة به تلقائيًا، ولا يغير التقارير القديمة.</Text><Pressable style={styles.primary} onPress={() => { setSelected(null); setEditing(true); setSaveError(''); }}><Text style={styles.primaryText}>قالب جديد</Text></Pressable></View>
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
  const [employeeId, setEmployeeId] = useState('');
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
  const employees = (data?.employees ?? []).filter((item) => item.active && (!selectedTemplate || item.roles.includes(selectedTemplate.roleCode)));
  async function assign() {
    setError(''); setNotice('');
    const startsAt = adenDateTimeToIso(startDate, startTime);
    const dueAt = adenDateTimeToIso(dueDate, dueTime);
    if (!selectedTemplate) { setError('اختر قالبًا نشطًا أولًا.'); return; }
    if (!employeeId) { setError('اختر الموظف المكلف بالمهمة.'); return; }
    if (!startsAt || !dueAt) { setError('أدخل تاريخًا ووقتًا صالحين لبداية المهمة وموعدها النهائي.'); return; }
    if (new Date(dueAt).getTime() < new Date(startsAt).getTime()) { setError('لا يمكن أن يسبق الموعد النهائي بداية المهمة.'); return; }
    setBusy(true);
    try {
      await assignTaskFromTemplate({ templateId: selectedTemplate.id!, assignedTo: employeeId, branchId: branchId || null, startsAt, dueAt, priority, instructions, reportOverrides: reportChoices.map((report) => ({ approvedVersionId: report.approvedVersionId, required: report.required || reportRequired[report.approvedVersionId] === true })) });
      setNotice(`تم إسناد «${selectedTemplate.title}» وحفظ لقطات الخطوات والتقارير لهذا التكليف.`);
      setTemplateId(''); setEmployeeId(''); setBranchId(''); setInstructions(''); setPriority('normal'); setReportRequired({});
      await onReload();
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر إسناد القالب. تأكد من تطابق الدور والفرع وصلاحية إدارة المهام.'));
    } finally { setBusy(false); }
  }
  return <View style={styles.form}>
    <Text style={styles.sectionTitle}>إسناد من قالب مهام</Text>
    <Text style={styles.copy}>يُنشأ التكليف مع نسخة ثابتة من خطواته وكل نموذج تقرير مرتبط به. يمكن تعديل القالب لاحقًا دون تغيير التكليفات السابقة.</Text>
    <Text style={styles.fieldLabel}>القالب</Text>
    <View style={styles.choices}>{templates.filter((item) => item.isActive).map((item) => <Pressable key={item.id} style={[styles.choice, templateId === item.id && styles.choiceSelected]} onPress={() => { setTemplateId(item.id ?? ''); setEmployeeId(''); }}><Text style={templateId === item.id ? styles.choiceSelectedText : styles.choiceText}>{item.title} · {roleLabel(item.roleCode)}</Text></Pressable>)}</View>
    {!templates.some((item) => item.isActive) && <Text style={styles.muted}>لا توجد قوالب نشطة.</Text>}
    <Pressable style={styles.secondary} onPress={onEditTemplates}><Text style={styles.secondaryText}>إدارة قوالب المهام</Text></Pressable>
    {selectedTemplate && <>
      <Text style={styles.fieldLabel}>الموظف المسؤول ({roleLabel(selectedTemplate.roleCode)})</Text>
      <View style={styles.choices}>{employees.map((employee) => <Pressable key={employee.id} style={[styles.choice, employeeId === employee.id && styles.choiceSelected]} onPress={() => setEmployeeId(employee.id)}><Text style={employeeId === employee.id ? styles.choiceSelectedText : styles.choiceText}>{employee.name}</Text></Pressable>)}</View>
      {!employees.length && <Text style={styles.muted}>لا يوجد موظف نشط بهذا الدور.</Text>}
      <Text style={styles.fieldLabel}>الأولوية لهذا التكليف</Text><View style={styles.choices}>{(['normal','important','urgent','critical'] as const).map((value) => <Pressable key={value} style={[styles.choice, priority === value && styles.choiceSelected]} onPress={() => setPriority(value)}><Text style={priority === value ? styles.choiceSelectedText : styles.choiceText}>{priorityLabels[value]}</Text></Pressable>)}</View>
      <TextInput style={[styles.input, { minHeight: 70 }]} value={instructions} onChangeText={setInstructions} placeholder="تعليمات إضافية لهذا التكليف (اختياري)" multiline accessibilityLabel="تعليمات إضافية لهذا التكليف" />
      {!!reportChoices.length && <><Text style={styles.fieldLabel}>اختيارات التقارير لهذا التكليف</Text><View style={styles.choices}>{reportChoices.map((report) => { const required = report.required || reportRequired[report.approvedVersionId] === true; return <Pressable key={report.approvedVersionId} style={[styles.choice, required && styles.choiceSelected]} onPress={() => { if (report.required) return; setReportRequired((current) => ({ ...current, [report.approvedVersionId]: !required })); }}><Text style={required ? styles.choiceSelectedText : styles.choiceText}>{required ? 'إلزامي' : 'اختياري'} · {report.approvedVersionId.slice(0, 8)}</Text></Pressable>; })}</View></>}
      {reportChoices.some((report) => report.required) && <Text style={styles.meta}>التقارير الإلزامية في القالب لا يمكن تحويلها إلى اختيارية أثناء التكليف.</Text>}
      <Text style={styles.fieldLabel}>الفرع (اختياري، يتحقق الخادم من تكليف الموظف به)</Text>
      <View style={styles.choices}><Pressable style={[styles.choice, !branchId && styles.choiceSelected]} onPress={() => setBranchId('')}><Text style={!branchId ? styles.choiceSelectedText : styles.choiceText}>كل الفروع</Text></Pressable>{(data?.branches ?? []).filter((branch) => branch.isActive).map((branch) => <Pressable key={branch.id} style={[styles.choice, branchId === branch.id && styles.choiceSelected]} onPress={() => setBranchId(branch.id)}><Text style={branchId === branch.id ? styles.choiceSelectedText : styles.choiceText}>{branch.name}</Text></Pressable>)}</View>
      <Text style={styles.fieldLabel}>بداية المهمة · توقيت عدن</Text><AdenDeadlinePicker date={startDate} time={startTime} onChange={(date, time) => { setStartDate(date); setStartTime(time); }} />
      <Text style={styles.fieldLabel}>الموعد النهائي · توقيت عدن</Text><AdenDeadlinePicker date={dueDate} time={dueTime} onChange={(date, time) => { setDueDate(date); setDueTime(time); }} />
      <Text style={styles.meta}>الأولوية الافتراضية: {priorityLabels[selectedTemplate.priority] ?? selectedTemplate.priority} · {selectedTemplate.steps.length} خطوات · {selectedTemplate.reports.length} تقارير مستقلة</Text>
      <Pressable disabled={busy || !employeeId} style={[styles.primary, busy && { opacity: 0.6 }]} onPress={() => void assign()}><Text style={styles.primaryText}>{busy ? 'جارٍ الإسناد…' : 'إسناد المهمة'}</Text></Pressable>
    </>}
    {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
    {!!notice && <Text style={styles.notice}>{notice}</Text>}
  </View>;
}

const styles = StyleSheet.create({ safe: { flex: 1, backgroundColor: '#f4f7f8' }, content: { padding: 16, paddingBottom: 40, gap: 12 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 }, topbar: { flexDirection: 'row-reverse', justifyContent: 'space-between', alignItems: 'center' }, eyebrow: { color: '#718394', fontWeight: '700', textAlign: 'right' }, title: { color: '#17324d', fontSize: 28, fontWeight: '900', textAlign: 'right', marginTop: 3 }, signOut: { borderWidth: 1, borderColor: '#b55248', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 9 }, signOutText: { color: '#a8443d', fontWeight: '800' }, nav: { flexDirection: 'row-reverse', gap: 8, paddingVertical: 5 }, navChip: { borderWidth: 1, borderColor: '#ccd9df', borderRadius: 20, paddingHorizontal: 12, paddingVertical: 9 }, navChipSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, navText: { color: '#39556a', fontSize: 13 }, navTextSelected: { color: '#fff', fontWeight: '800', fontSize: 13 }, sectionTitle: { color: '#17324d', fontSize: 19, fontWeight: '900', textAlign: 'right', marginTop: 8 }, sectionHeader: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between' }, metrics: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 8 }, metric: { width: '31%', minHeight: 83, backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e0e8eb', padding: 10, alignItems: 'center', justifyContent: 'center' }, metricValue: { color: '#17324d', fontSize: 25, fontWeight: '900' }, metricLabel: { color: '#718394', fontSize: 12, textAlign: 'center', marginTop: 3 }, primary: { minHeight: 48, backgroundColor: '#17324d', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 12 }, primarySmall: { backgroundColor: '#17324d', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10 }, primaryText: { color: '#fff', fontWeight: '800' }, secondary: { minHeight: 46, backgroundColor: '#e8f0f3', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 12 }, secondaryText: { color: '#17324d', fontWeight: '800' }, card: { backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e0e8eb', padding: 14, gap: 5 }, row: { backgroundColor: '#fff', borderRightWidth: 3, borderRightColor: '#2f6654', borderRadius: 12, padding: 13, gap: 4 }, actionsRow: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7 }, taskLine: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8 }, cardTitle: { color: '#17324d', fontSize: 15, fontWeight: '800', textAlign: 'right' }, badge: { color: '#23633c', backgroundColor: '#e8f5eb', paddingHorizontal: 8, paddingVertical: 5, borderRadius: 12, fontSize: 12 }, meta: { color: '#718394', fontSize: 12, lineHeight: 19, textAlign: 'right' }, copy: { color: '#536978', lineHeight: 22, textAlign: 'right' }, form: { backgroundColor: '#fff', borderRadius: 14, padding: 14, gap: 10, borderWidth: 1, borderColor: '#dce6e9' }, input: { minHeight: 46, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, textAlign: 'right', backgroundColor: '#fbfcfc' }, fieldLabel: { color: '#29475a', fontWeight: '800', textAlign: 'right' }, choices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7 }, choice: { borderWidth: 1, borderColor: '#ccd9df', borderRadius: 18, paddingHorizontal: 10, paddingVertical: 8 }, choiceSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, choiceText: { color: '#39556a', fontSize: 12 }, choiceSelectedText: { color: '#fff', fontWeight: '800', fontSize: 12 }, error: { color: '#a8443d', backgroundColor: '#fff0ef', borderRadius: 10, padding: 11, textAlign: 'right', lineHeight: 21 }, notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 10, padding: 11, textAlign: 'right' }, muted: { color: '#718394', textAlign: 'right', paddingVertical: 10 }, unavailable: { backgroundColor: '#fff7e8', borderColor: '#efddb7', borderWidth: 1, borderRadius: 14, padding: 15, gap: 8 }, settings: { minHeight: 46, borderWidth: 1, borderColor: '#17324d', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 11, marginTop: 8 }, settingsText: { color: '#17324d', fontWeight: '800' } });
