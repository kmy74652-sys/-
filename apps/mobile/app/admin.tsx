import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, AppState, Pressable, RefreshControl, SafeAreaView, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { friendlyDataError, getMyEmployeeProfile } from '../lib/mobileData';
import { createAdministrativeTask, loadDashboardData, listTaskTemplates, roleLabel, statusLabel, type DashboardData } from '../lib/adminData';
import { supabase } from '../lib/supabase';
import { listApprovedDesignerTemplates, type ReportTemplate } from '../lib/reportDesigner';
import ReportDesigner from '../components/ReportDesigner';

type Section = 'overview' | 'tasks' | 'reports' | 'designer' | 'branches' | 'employees' | 'activity' | 'warehouse' | 'finance';
const sections: Array<[Section, string]> = [['overview', 'الرئيسية'], ['tasks', 'إدارة المهام'], ['reports', 'تقارير الموظفين'], ['designer', 'مصمم التقارير'], ['branches', 'الفروع'], ['employees', 'الموظفون'], ['activity', 'السجل والمرفقات'], ['warehouse', 'المخازن والجرد'], ['finance', 'المالية']];
const roleCodes = ['owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'];
const priorityLabels: Record<string, string> = { normal: 'عادية', important: 'مهمة', urgent: 'عاجلة', critical: 'حرجة' };

export default function AdminScreen() {
  const router = useRouter();
  const [section, setSection] = useState<Section>('overview');
  const [data, setData] = useState<DashboardData | null>(null);
  const [templates, setTemplates] = useState<Array<{ id: string; title: string; role_code: string; description: string | null; recurrence_type: string }>>([]);
  const [designerTemplates, setDesignerTemplates] = useState<ReportTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [draft, setDraft] = useState({ title: '', description: '', dueAt: '', priority: 'normal', roleCode: 'admin_followup', branchId: '', templateId: '', reportTemplateId: '', reportRequired: true });

  const load = useCallback(async () => {
    setError('');
    try {
      const identity = await getMyEmployeeProfile();
      if (!identity?.employee) throw new Error('employee_not_active');
      if (!identity.employee.permissions.includes('tasks.manage')) throw new Error('permission_denied');
      const [dashboard, taskTemplates, reportTemplates] = await Promise.all([loadDashboardData(), listTaskTemplates(), listApprovedDesignerTemplates()]);
      setData(dashboard);
      setTemplates(taskTemplates);
      setDesignerTemplates(reportTemplates);
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
    if (!draft.title.trim() || !draft.dueAt.trim()) { setError('أدخل عنوان المهمة والموعد النهائي.'); return; }
    try {
      setError(''); setNotice('');
      const selectedReport = designerTemplates.find((template) => template.id === draft.reportTemplateId && template.role_code === draft.roleCode);
      if (draft.reportTemplateId && !selectedReport?.approved_version_id) throw new Error('report_form_version_requires_approval');
      await createAdministrativeTask({
        title: draft.title, description: draft.description, dueAt: draft.dueAt, priority: draft.priority,
        roleCode: draft.roleCode, branchId: draft.branchId || null, templateId: draft.templateId || null,
        reportTemplateId: selectedReport?.id ?? null, reportVersionId: selectedReport?.approved_version_id ?? null,
        reportRequired: draft.reportRequired,
      });
      setDraft({ title: '', description: '', dueAt: '', priority: 'normal', roleCode: 'admin_followup', branchId: '', templateId: '', reportTemplateId: '', reportRequired: true });
      setShowCreate(false); setNotice('تم إنشاء المهمة وربطها بأول موظف نشط ضمن التصنيف المحدد.'); await load();
    } catch (cause) { setError(friendlyDataError(cause, 'تعذر إنشاء المهمة. تأكد من وجود موظف نشط ضمن التصنيف والفرع المحددين.')); }
  }
  const fmt = (value: string | null) => value ? new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : 'غير محدد';

  if (loading) return <SafeAreaView style={styles.safe}><View style={styles.center}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.muted}>جارٍ تحميل لوحة الإدارة…</Text></View></SafeAreaView>;
  return <SafeAreaView style={styles.safe}>
    <Stack.Screen options={{ headerShown: false }} />
    <ScrollView refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); void load(); }} />} contentContainerStyle={styles.content}>
      <View style={styles.topbar}><View><Text style={styles.eyebrow}>إدارة مؤسسة الشاعري</Text><Text style={styles.title}>لوحة التحكم</Text></View><Pressable style={styles.signOut} onPress={() => void signOut()}><Text style={styles.signOutText}>خروج</Text></Pressable></View>
      {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
      {!!notice && <Text style={styles.notice}>{notice}</Text>}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.nav}>{sections.map(([key, label]) => <Pressable key={key} onPress={() => setSection(key)} style={[styles.navChip, section === key && styles.navChipSelected]}><Text style={section === key ? styles.navTextSelected : styles.navText}>{label}</Text></Pressable>)}</ScrollView>
      {section === 'overview' && <Overview counts={counts} data={data} fmt={fmt} onTasks={() => setSection('tasks')} />}
      {section === 'tasks' && <TasksSection data={data} templates={templates} designerTemplates={designerTemplates} showCreate={showCreate} setShowCreate={setShowCreate} draft={draft} setDraft={setDraft} createTask={createTask} fmt={fmt} onOpenTasks={() => router.push('/tasks')} />}
      {section === 'reports' && <ReportsSection data={data} fmt={fmt} />}
      {section === 'designer' && <DesignerSection />}
      {section === 'branches' && <BranchesSection data={data} />}
      {section === 'employees' && <EmployeesSection data={data} />}
      {section === 'activity' && <ActivitySection data={data} fmt={fmt} />}
      {section === 'warehouse' && <Unavailable title="المخازن والجرد" text="لا توجد جداول مخازن وجرد في مخطط Supabase الحالي، لذلك لم أضع أزرارًا وهمية. يلزم اعتماد مخطط المخازن قبل تفعيل هذا القسم." />}
      {section === 'finance' && <Unavailable title="التقارير المالية" text="لا توجد جداول مالية في مخطط Supabase الحالي. سيظهر هذا القسم فعليًا بعد تطبيق مخطط الحسابات والتقارير المالية، دون اختلاق أرقام من خارج قاعدة البيانات." />}
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

function TasksSection({ data, templates, designerTemplates, showCreate, setShowCreate, draft, setDraft, createTask, fmt, onOpenTasks }: any) { return <><View style={styles.sectionHeader}><Text style={styles.sectionTitle}>إدارة المهام</Text><Pressable style={styles.primarySmall} onPress={() => setShowCreate(!showCreate)}><Text style={styles.primaryText}>{showCreate ? 'إلغاء' : 'إنشاء مهمة'}</Text></Pressable></View>{showCreate && <View style={styles.form}>{[['title', 'عنوان المهمة'], ['description', 'الوصف'], ['dueAt', 'الموعد النهائي بصيغة ISO']].map(([key, label]) => <TextInput key={key} style={styles.input} placeholder={label} value={draft[key]} onChangeText={(value) => setDraft({ ...draft, [key]: value })} multiline={key === 'description'} />)}<Text style={styles.fieldLabel}>التصنيف الوظيفي</Text><View style={styles.choices}>{roleCodes.map((role) => <Pressable key={role} style={[styles.choice, draft.roleCode === role && styles.choiceSelected]} onPress={() => setDraft({ ...draft, roleCode: role, templateId: templates.some((item: any) => item.id === draft.templateId && item.role_code === role) ? draft.templateId : '', reportTemplateId: designerTemplates.some((item: ReportTemplate) => item.id === draft.reportTemplateId && item.role_code === role) ? draft.reportTemplateId : '' })}><Text style={draft.roleCode === role ? styles.choiceSelectedText : styles.choiceText}>{roleLabel(role)}</Text></Pressable>)}</View><Text style={styles.fieldLabel}>الفرع</Text><View style={styles.choices}>{(data?.branches ?? []).map((branch: any) => <Pressable key={branch.id} style={[styles.choice, draft.branchId === branch.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, branchId: branch.id })}><Text style={draft.branchId === branch.id ? styles.choiceSelectedText : styles.choiceText}>{branch.name}</Text></Pressable>)}</View><Text style={styles.fieldLabel}>قالب التقرير القديم</Text><View style={styles.choices}><Pressable style={[styles.choice, !draft.templateId && styles.choiceSelected]} onPress={() => setDraft({ ...draft, templateId: '' })}><Text style={!draft.templateId ? styles.choiceSelectedText : styles.choiceText}>بدون قالب قديم</Text></Pressable>{templates.filter((template: any) => template.role_code === draft.roleCode).map((template: any) => <Pressable key={template.id} style={[styles.choice, draft.templateId === template.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, templateId: template.id })}><Text style={draft.templateId === template.id ? styles.choiceSelectedText : styles.choiceText}>{template.title}</Text></Pressable>)}</View><Text style={styles.fieldLabel}>نموذج المصمم مع حفظ نسخة للمهمة</Text><View style={styles.choices}><Pressable style={[styles.choice, !draft.reportTemplateId && styles.choiceSelected]} onPress={() => setDraft({ ...draft, reportTemplateId: '' })}><Text style={!draft.reportTemplateId ? styles.choiceSelectedText : styles.choiceText}>بدون نموذج مصمم</Text></Pressable>{designerTemplates.filter((template: ReportTemplate) => template.role_code === draft.roleCode).map((template: ReportTemplate) => <Pressable key={template.id} style={[styles.choice, draft.reportTemplateId === template.id && styles.choiceSelected]} onPress={() => setDraft({ ...draft, reportTemplateId: template.id })}><Text style={draft.reportTemplateId === template.id ? styles.choiceSelectedText : styles.choiceText}>{template.title} · إصدار {template.approved_version_no}</Text></Pressable>)}</View><Pressable style={styles.secondary} onPress={() => setDraft({ ...draft, reportRequired: !draft.reportRequired })}><Text style={styles.secondaryText}>{draft.reportRequired ? 'التقرير مطلوب ✓' : 'التقرير اختياري'}</Text></Pressable><Pressable style={styles.primary} onPress={() => void createTask()}><Text style={styles.primaryText}>حفظ ونشر المهمة</Text></Pressable></View>}<Pressable style={styles.secondary} onPress={onOpenTasks}><Text style={styles.secondaryText}>فتح شاشة التنفيذ والتقارير والمرفقات</Text></Pressable>{(data?.tasks ?? []).map((task: any) => <View style={styles.card} key={task.id}><View style={styles.taskLine}><Text style={styles.cardTitle}>{task.title}</Text><Text style={styles.badge}>{statusLabel(task.status)}</Text></View><Text style={styles.meta}>{task.branchName || 'كل الفروع'} · {priorityLabels[task.priority] || task.priority} · {fmt(task.dueAt)}</Text></View>)}</>; }
function ReportsSection({ data, fmt }: any) { return <><Text style={styles.sectionTitle}>تقارير الموظفين</Text><Text style={styles.copy}>التقارير المرتبطة بالمهام وتنتظر المراجعة أو تم اعتمادها.</Text>{(data?.reports ?? []).length ? data.reports.map((report: any) => <View style={styles.card} key={report.id}><Text style={styles.cardTitle}>{report.status === 'submitted' ? 'بانتظار المراجعة' : report.status === 'approved' ? 'معتمد' : 'معاد للتصحيح'}</Text><Text style={styles.meta}>{fmt(report.submittedAt)} · {report.id.slice(0, 8)}</Text></View>) : <Text style={styles.muted}>لا توجد تقارير مسجلة حاليًا.</Text>}</>; }
function BranchesSection({ data }: any) { return <><Text style={styles.sectionTitle}>إدارة الفروع</Text><Text style={styles.copy}>عرض الفروع الثانية والثالثة مع عدد المهام الحالية. الإضافة والتعديل ستستخدم نفس جداول الفروع عند تفعيل صلاحية الإدارة.</Text>{(data?.branches ?? []).map((branch: any) => <View style={styles.card} key={branch.id}><Text style={styles.cardTitle}>{branch.name}</Text><Text style={styles.meta}>الكود: {branch.code} · المستوى: {branch.level || 'غير محدد'} · {branch.isActive ? 'نشط' : 'متوقف'}</Text></View>)}</>; }
function EmployeesSection({ data }: any) { return <><Text style={styles.sectionTitle}>الموظفون والتصنيفات الوظيفية</Text>{(data?.employees ?? []).map((employee: any) => <View style={styles.card} key={employee.id}><Text style={styles.cardTitle}>{employee.name}</Text><Text style={styles.meta}>{employee.employeeNo || 'بدون رقم'} · {employee.active ? 'نشط' : 'غير نشط'}</Text><Text style={styles.meta}>{employee.roles.length ? employee.roles.map(roleLabel).join('، ') : 'دون تصنيف'}</Text></View>)}</>; }
function ActivitySection({ data, fmt }: any) { return <><Text style={styles.sectionTitle}>سجل النشاط والمرفقات</Text><Text style={styles.copy}>السجل يعرض الأحداث المسموح بها حسب RLS. إدارة المرفقات تتم من داخل تقرير المهمة.</Text>{(data?.activity ?? []).map((item: any) => <View style={styles.row} key={item.id}><Text style={styles.cardTitle}>{item.action}</Text><Text style={styles.meta}>المهمة {item.taskId.slice(0, 8)} · {fmt(item.createdAt)}</Text></View>)}</>; }
function Unavailable({ title, text }: { title: string; text: string }) { return <View style={styles.unavailable}><Text style={styles.sectionTitle}>{title}</Text><Text style={styles.copy}>{text}</Text></View>; }

function DesignerSection() {
  return <ReportDesigner />;
}

const styles = StyleSheet.create({ safe: { flex: 1, backgroundColor: '#f4f7f8' }, content: { padding: 16, paddingBottom: 40, gap: 12 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 }, topbar: { flexDirection: 'row-reverse', justifyContent: 'space-between', alignItems: 'center' }, eyebrow: { color: '#718394', fontWeight: '700', textAlign: 'right' }, title: { color: '#17324d', fontSize: 28, fontWeight: '900', textAlign: 'right', marginTop: 3 }, signOut: { borderWidth: 1, borderColor: '#b55248', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 9 }, signOutText: { color: '#a8443d', fontWeight: '800' }, nav: { flexDirection: 'row-reverse', gap: 8, paddingVertical: 5 }, navChip: { borderWidth: 1, borderColor: '#ccd9df', borderRadius: 20, paddingHorizontal: 12, paddingVertical: 9 }, navChipSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, navText: { color: '#39556a', fontSize: 13 }, navTextSelected: { color: '#fff', fontWeight: '800', fontSize: 13 }, sectionTitle: { color: '#17324d', fontSize: 19, fontWeight: '900', textAlign: 'right', marginTop: 8 }, sectionHeader: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between' }, metrics: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 8 }, metric: { width: '31%', minHeight: 83, backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e0e8eb', padding: 10, alignItems: 'center', justifyContent: 'center' }, metricValue: { color: '#17324d', fontSize: 25, fontWeight: '900' }, metricLabel: { color: '#718394', fontSize: 12, textAlign: 'center', marginTop: 3 }, primary: { minHeight: 48, backgroundColor: '#17324d', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 12 }, primarySmall: { backgroundColor: '#17324d', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10 }, primaryText: { color: '#fff', fontWeight: '800' }, secondary: { minHeight: 46, backgroundColor: '#e8f0f3', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 12 }, secondaryText: { color: '#17324d', fontWeight: '800' }, card: { backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#e0e8eb', padding: 14, gap: 5 }, row: { backgroundColor: '#fff', borderRightWidth: 3, borderRightColor: '#2f6654', borderRadius: 12, padding: 13, gap: 4 }, taskLine: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8 }, cardTitle: { color: '#17324d', fontSize: 15, fontWeight: '800', textAlign: 'right' }, badge: { color: '#23633c', backgroundColor: '#e8f5eb', paddingHorizontal: 8, paddingVertical: 5, borderRadius: 12, fontSize: 12 }, meta: { color: '#718394', fontSize: 12, lineHeight: 19, textAlign: 'right' }, copy: { color: '#536978', lineHeight: 22, textAlign: 'right' }, form: { backgroundColor: '#fff', borderRadius: 14, padding: 14, gap: 10, borderWidth: 1, borderColor: '#dce6e9' }, input: { minHeight: 46, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, textAlign: 'right', backgroundColor: '#fbfcfc' }, fieldLabel: { color: '#29475a', fontWeight: '800', textAlign: 'right' }, choices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 7 }, choice: { borderWidth: 1, borderColor: '#ccd9df', borderRadius: 18, paddingHorizontal: 10, paddingVertical: 8 }, choiceSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, choiceText: { color: '#39556a', fontSize: 12 }, choiceSelectedText: { color: '#fff', fontWeight: '800', fontSize: 12 }, error: { color: '#a8443d', backgroundColor: '#fff0ef', borderRadius: 10, padding: 11, textAlign: 'right', lineHeight: 21 }, notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 10, padding: 11, textAlign: 'right' }, muted: { color: '#718394', textAlign: 'right', paddingVertical: 10 }, unavailable: { backgroundColor: '#fff7e8', borderColor: '#efddb7', borderWidth: 1, borderRadius: 14, padding: 15, gap: 8 }, settings: { minHeight: 46, borderWidth: 1, borderColor: '#17324d', borderRadius: 11, alignItems: 'center', justifyContent: 'center', padding: 11, marginTop: 8 }, settingsText: { color: '#17324d', fontWeight: '800' } });
